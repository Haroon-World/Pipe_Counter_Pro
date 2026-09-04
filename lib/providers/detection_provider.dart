import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../models/app_settings.dart';
import '../models/pipe_detection.dart';
import '../services/classical_cv_detector.dart';
import '../services/tflite_detector.dart';
import 'settings_provider.dart';

enum CanvasTool {
  pan,
  add,
  delete,
  select;

  String get displayName {
    switch (this) {
      case CanvasTool.pan:
        return 'Pan & Zoom';
      case CanvasTool.add:
        return 'Add Pipe';
      case CanvasTool.delete:
        return 'Delete Pipe';
      case CanvasTool.select:
        return 'Toggle Count';
    }
  }
}

class DetectionState {
  final Uint8List? imageBytes;
  final String? imageName;
  final int imageWidth;
  final int imageHeight;
  final bool isProcessing;
  final String? statusMessage;
  final String? errorMessage;
  final DetectionResult? result;
  final double sizeThreshold;

  // Interactive manual tool states
  final CanvasTool selectedTool;
  final PipeCategory activeAddCategory;
  final double manualAddRadius;
  final List<List<PipeDetection>> undoStack;

  const DetectionState({
    this.imageBytes,
    this.imageName,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.isProcessing = false,
    this.statusMessage,
    this.errorMessage,
    this.result,
    this.sizeThreshold = 500.0,
    this.selectedTool = CanvasTool.pan,
    this.activeAddCategory = PipeCategory.small,
    this.manualAddRadius = 25.0,
    this.undoStack = const [],
  });

  bool get hasImage => imageBytes != null && imageWidth > 0 && imageHeight > 0;
  bool get hasResults => result != null && result!.pipes.isNotEmpty;
  bool get canUndo => undoStack.isNotEmpty;

  DetectionState copyWith({
    Uint8List? imageBytes,
    String? imageName,
    int? imageWidth,
    int? imageHeight,
    bool? isProcessing,
    String? statusMessage,
    String? errorMessage,
    DetectionResult? result,
    double? sizeThreshold,
    CanvasTool? selectedTool,
    PipeCategory? activeAddCategory,
    double? manualAddRadius,
    List<List<PipeDetection>>? undoStack,
    bool clearImage = false,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return DetectionState(
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      imageName: clearImage ? null : (imageName ?? this.imageName),
      imageWidth: clearImage ? 0 : (imageWidth ?? this.imageWidth),
      imageHeight: clearImage ? 0 : (imageHeight ?? this.imageHeight),
      isProcessing: isProcessing ?? this.isProcessing,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      result: clearResult ? null : (result ?? this.result),
      sizeThreshold: sizeThreshold ?? this.sizeThreshold,
      selectedTool: selectedTool ?? this.selectedTool,
      activeAddCategory: activeAddCategory ?? this.activeAddCategory,
      manualAddRadius: manualAddRadius ?? this.manualAddRadius,
      undoStack: undoStack ?? this.undoStack,
    );
  }
}

class DetectionNotifier extends StateNotifier<DetectionState> {
  final Ref ref;
  final TFLiteDetector _tfliteDetector = TFLiteDetector();

  DetectionNotifier(this.ref) : super(const DetectionState());

  @override
  void dispose() {
    _tfliteDetector.close();
    super.dispose();
  }

  // --- Tool & Manual Annotation Controls ---

  void setSelectedTool(CanvasTool tool) {
    state = state.copyWith(selectedTool: tool);
  }

  void setActiveAddCategory(PipeCategory cat) {
    state = state.copyWith(activeAddCategory: cat);
  }

  void setManualAddRadius(double radius) {
    state = state.copyWith(manualAddRadius: radius.clamp(4.0, 300.0));
  }

  void _pushUndo() {
    final currentPipes = state.result?.pipes ?? const <PipeDetection>[];
    final newStack = List<List<PipeDetection>>.from(state.undoStack)..add(List.from(currentPipes));
    // Keep max 20 undo steps
    if (newStack.length > 20) {
      newStack.removeAt(0);
    }
    state = state.copyWith(undoStack: newStack);
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final newStack = List<List<PipeDetection>>.from(state.undoStack);
    final previousPipes = newStack.removeLast();

    final currentResult = state.result ??
        DetectionResult(
          pipes: const [],
          imageWidth: state.imageWidth,
          imageHeight: state.imageHeight,
          processingTime: Duration.zero,
          engineName: 'Manual Annotation',
          currentThreshold: state.sizeThreshold,
        );

    state = state.copyWith(
      result: currentResult.copyWith(pipes: previousPipes),
      undoStack: newStack,
    );
  }

  /// Add a manual pipe circle at image coordinates (cx, cy)
  void addManualPipe(double cx, double cy, {double? radius, PipeCategory? category}) {
    _pushUndo();

    final currentPipes = state.result?.pipes ?? const <PipeDetection>[];
    int nextId = 1;
    if (currentPipes.isNotEmpty) {
      nextId = currentPipes.map((p) => p.id).reduce(math.max) + 1;
    }

    final r = radius ?? state.manualAddRadius;
    final cat = category ?? state.activeAddCategory;
    final diam = r * 2.0;

    final newPipe = PipeDetection(
      id: nextId,
      cx: cx,
      cy: cy,
      width: diam,
      height: diam,
      angle: 0.0,
      area: math.pi * r * r,
      category: cat,
      confidence: 1.0,
      solidity: 1.0,
      isSelected: true,
      isManual: true,
    );

    final currentResult = state.result ??
        DetectionResult(
          pipes: const [],
          imageWidth: state.imageWidth,
          imageHeight: state.imageHeight,
          processingTime: Duration.zero,
          engineName: 'Manual Annotation',
          currentThreshold: state.sizeThreshold,
        );

    state = state.copyWith(
      result: currentResult.withPipeAdded(newPipe),
    );
  }

  /// Delete a pipe by ID
  void deletePipe(int id) {
    if (state.result == null) return;
    _pushUndo();
    state = state.copyWith(
      result: state.result!.withPipeRemoved(id),
    );
  }

  /// Toggle active / excluded state for a pipe
  void togglePipeSelected(int id) {
    if (state.result == null) return;
    _pushUndo();
    state = state.copyWith(
      result: state.result!.withPipeToggled(id),
    );
  }

  /// Recolor a pipe by ID
  void recolorPipe(int id, PipeCategory newCat) {
    if (state.result == null) return;
    _pushUndo();
    state = state.copyWith(
      result: state.result!.withPipeRecolored(id, newCat),
    );
  }

  // --- Image Loading & Camera ---

  /// Pick an image file from device storage/gallery (Cross-Platform)
  Future<void> pickImageFromGallery() async {
    try {
      state = state.copyWith(isProcessing: true, statusMessage: 'Loading image...', clearError: true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.single;
        final bytes = pickedFile.bytes;

        if (bytes != null) {
          _processSelectedBytes(bytes, pickedFile.name);
        } else {
          state = state.copyWith(isProcessing: false);
        }
      } else {
        state = state.copyWith(isProcessing: false);
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to pick image: $e',
      );
    }
  }

  /// Take a photo using device camera (Mobile)
  Future<void> capturePhotoFromCamera() async {
    try {
      state = state.copyWith(isProcessing: true, statusMessage: 'Opening camera...', clearError: true);
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        _processSelectedBytes(bytes, 'camera_capture_${DateTime.now().millisecondsSinceEpoch}.jpg');
      } else {
        state = state.copyWith(isProcessing: false);
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to capture photo: $e',
      );
    }
  }

  void _processSelectedBytes(Uint8List bytes, String name) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: 'Unable to decode image file format.',
        );
        return;
      }

      state = state.copyWith(
        imageBytes: bytes,
        imageName: name,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
        isProcessing: false,
        undoStack: const [],
        clearResult: true,
        clearError: true,
      );

      // Auto-estimate a sensible starting radius range from image dimensions
      autoEstimateRadiusRange();
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Error loading image: $e',
      );
    }
  }

  /// Heuristically auto-estimates radius range based on the image's short side
  void autoEstimateRadiusRange() {
    if (state.imageWidth <= 0 || state.imageHeight <= 0) return;

    final shortSide = math.min(state.imageWidth, state.imageHeight);
    final minR = math.max(8.0, (shortSide * 0.015).roundToDouble());
    final maxR = math.max(minR + 15.0, (shortSide * 0.080).roundToDouble());
    final medianR = ((minR + maxR) / 2.0).roundToDouble();

    ref.read(settingsProvider.notifier).setRadiusRange(minR, maxR);
    state = state.copyWith(manualAddRadius: medianR);
  }

  /// Runs pipe detection using the currently selected engine
  Future<void> runDetection() async {
    if (state.imageBytes == null) {
      state = state.copyWith(errorMessage: 'Please select or take an image first.');
      return;
    }

    final settings = ref.read(settingsProvider);

    if (settings.minRadius >= settings.maxRadius) {
      state = state.copyWith(
        errorMessage: 'Min Pipe Radius (${settings.minRadius.toInt()}px) must be smaller than Max Radius (${settings.maxRadius.toInt()}px).',
      );
      return;
    }

    state = state.copyWith(
      isProcessing: true,
      statusMessage: 'Detecting pipes with ${settings.engine.title}...',
      clearError: true,
    );

    try {
      DetectionResult result;

      if (settings.engine == DetectionEngine.classicalCV) {
        result = await ClassicalCVDetector.detect(
          state.imageBytes!,
          sensitivity: settings.sensitivity,
          minRadius: settings.minRadius,
          maxRadius: settings.maxRadius,
          solidityThreshold: settings.solidityThreshold,
          outlierFraction: settings.outlierFraction,
        );
      } else {
        if (kIsWeb) {
          throw Exception(
            'Engine B (TFLite) runs on native mobile and desktop targets. Please use Engine A (Classical CV) in browser mode.',
          );
        }

        if (settings.customModelPath == null) {
          throw Exception(
            'No custom TFLite model imported. Please go to Settings and import a fine-tuned pipe model (.tflite), or switch to Engine A.',
          );
        }

        if (!_tfliteDetector.isModelLoaded || _tfliteDetector.loadedModelPath != settings.customModelPath) {
          await _tfliteDetector.loadModel(settings.customModelPath!);
        }

        result = await _tfliteDetector.detect(
          state.imageBytes!,
          confidenceThreshold: settings.sensitivity,
          solidityThreshold: settings.solidityThreshold,
        );
      }

      if (result.pipes.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          result: result,
          errorMessage: 'No pipe openings detected automatically. You can adjust Min/Max radius or use the [Add Pipe] tool to mark pipes manually!',
        );
      } else {
        // Update default manual add radius to match detected pipes' average radius
        final avgDetectedRadius = result.pipes.map((p) => p.averageRadius).reduce((a, b) => a + b) / result.pipes.length;

        state = state.copyWith(
          isProcessing: false,
          result: result,
          sizeThreshold: result.currentThreshold,
          manualAddRadius: avgDetectedRadius.roundToDouble(),
          clearError: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Detection failed: $e',
      );
    }
  }

  /// Instantly reclassifies detected pipes in memory when the threshold slider moves
  void updateThreshold(double newThreshold) {
    if (state.result == null) return;
    final updatedResult = state.result!.reclassifiedWithThreshold(newThreshold);
    state = state.copyWith(
      sizeThreshold: newThreshold,
      result: updatedResult,
    );
  }

  void clearImage() {
    state = const DetectionState();
  }
}

final detectionProvider = StateNotifierProvider<DetectionNotifier, DetectionState>((ref) {
  return DetectionNotifier(ref);
});
