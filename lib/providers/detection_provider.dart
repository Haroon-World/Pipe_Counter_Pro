import 'dart:isolate';
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

  // Visual & Interactive settings
  final bool showNumbers;
  final SizeTierMode sizeTierMode;
  final double detectionProgress; // 0.0 to 1.0
  final String detectionStage;

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
    this.showNumbers = false, // Default false: pipes visible without obstructing numbers
    this.sizeTierMode = SizeTierMode.uniform, // Default uniform: all same size/green
    this.detectionProgress = 0.0,
    this.detectionStage = '',
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
    bool? showNumbers,
    SizeTierMode? sizeTierMode,
    double? detectionProgress,
    String? detectionStage,
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
      showNumbers: showNumbers ?? this.showNumbers,
      sizeTierMode: sizeTierMode ?? this.sizeTierMode,
      detectionProgress: detectionProgress ?? this.detectionProgress,
      detectionStage: detectionStage ?? this.detectionStage,
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

  // --- Display & Size Tier Controls ---

  void toggleShowNumbers() {
    state = state.copyWith(showNumbers: !state.showNumbers);
  }

  void setSizeTierMode(SizeTierMode mode) {
    if (state.result != null) {
      final updated = state.result!.reclassifiedWithSizeTiers(mode);
      state = state.copyWith(
        sizeTierMode: mode,
        result: updated,
      );
    } else {
      state = state.copyWith(sizeTierMode: mode);
    }
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

  // --- Image Loading & Camera (Background Offloaded) ---

  Future<void> pickImageFromGallery() async {
    try {
      state = state.copyWith(
        isProcessing: true,
        detectionProgress: 0.1,
        detectionStage: 'Selecting photo...',
        statusMessage: 'Loading photo...',
        clearError: true,
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.single;
        final bytes = pickedFile.bytes;

        if (bytes != null) {
          await _processSelectedBytes(bytes, pickedFile.name);
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

  Future<void> capturePhotoFromCamera() async {
    try {
      state = state.copyWith(
        isProcessing: true,
        detectionProgress: 0.1,
        detectionStage: 'Opening camera...',
        statusMessage: 'Opening camera...',
        clearError: true,
      );

      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        await _processSelectedBytes(bytes, 'camera_capture_${DateTime.now().millisecondsSinceEpoch}.jpg');
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

  Future<void> _processSelectedBytes(Uint8List bytes, String name) async {
    try {
      state = state.copyWith(
        isProcessing: true,
        detectionProgress: 0.3,
        detectionStage: 'Decoding high-resolution image...',
        statusMessage: 'Reading image format...',
      );

      // Offload heavy image decoding to background isolate so UI thread NEVER freezes
      _ImageDims? dims;
      if (kIsWeb) {
        dims = _decodeImageDimensions(bytes);
      } else {
        dims = await Isolate.run(() => _decodeImageDimensions(bytes));
      }

      if (dims == null) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: 'Unable to decode image file format.',
        );
        return;
      }

      state = state.copyWith(
        imageBytes: bytes,
        imageName: name,
        imageWidth: dims.width,
        imageHeight: dims.height,
        isProcessing: false,
        detectionProgress: 0.0,
        detectionStage: '',
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

  void autoEstimateRadiusRange() {
    if (state.imageWidth <= 0 || state.imageHeight <= 0) return;

    final shortSide = math.min(state.imageWidth, state.imageHeight);
    final minR = math.max(8.0, (shortSide * 0.015).roundToDouble());
    final maxR = math.max(minR + 15.0, (shortSide * 0.080).roundToDouble());
    final medianR = ((minR + maxR) / 2.0).roundToDouble();

    ref.read(settingsProvider.notifier).setRadiusRange(minR, maxR);
    state = state.copyWith(manualAddRadius: medianR);
  }

  /// Runs pipe detection using background thread with real-time percentage animation
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
      detectionProgress: 0.15,
      detectionStage: 'Enhancing contrast & gradients (15%)...',
      statusMessage: 'Scanning pipe contours...',
      clearError: true,
    );

    try {
      DetectionResult rawResult;

      if (settings.engine == DetectionEngine.classicalCV) {
        final params = _DetectionParams(
          imageBytes: state.imageBytes!,
          sensitivity: settings.sensitivity,
          minRadius: settings.minRadius,
          maxRadius: settings.maxRadius,
          solidityThreshold: settings.solidityThreshold,
          outlierFraction: settings.outlierFraction,
        );

        // Update progress indication
        state = state.copyWith(
          detectionProgress: 0.45,
          detectionStage: 'Scanning pipe rims & Hough circles (45%)...',
        );

        // Run heavy CV detection in background isolate to keep 60/120 FPS UI fluid
        if (kIsWeb) {
          rawResult = await _runClassicalDetectionIsolate(params);
        } else {
          rawResult = await Isolate.run(() => _runClassicalDetectionIsolate(params));
        }

        state = state.copyWith(
          detectionProgress: 0.85,
          detectionStage: 'Fitting pipe diameters & classifying sizes (85%)...',
        );
      } else {
        if (kIsWeb) {
          throw Exception('Engine B runs on native targets. Please use Engine A in browser.');
        }
        if (settings.customModelPath == null) {
          throw Exception('No custom model imported. Built-in Engine A works offline.');
        }
        if (!_tfliteDetector.isModelLoaded || _tfliteDetector.loadedModelPath != settings.customModelPath) {
          await _tfliteDetector.loadModel(settings.customModelPath!);
        }
        rawResult = await _tfliteDetector.detect(
          state.imageBytes!,
          confidenceThreshold: settings.sensitivity,
          solidityThreshold: settings.solidityThreshold,
        );
      }

      // Apply selected size tier mode (Uniform / 2 Types / 3 Types / Auto)
      final result = rawResult.reclassifiedWithSizeTiers(state.sizeTierMode);

      if (result.pipes.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          detectionProgress: 1.0,
          detectionStage: 'Complete',
          result: result,
          errorMessage: 'No pipe openings detected automatically. You can use the [Add Pipe] tool to mark pipes manually!',
        );
      } else {
        final avgDetectedRadius =
            result.pipes.map((p) => p.averageRadius).reduce((a, b) => a + b) / result.pipes.length;

        state = state.copyWith(
          isProcessing: false,
          detectionProgress: 1.0,
          detectionStage: 'Complete',
          result: result,
          sizeThreshold: result.currentThreshold,
          manualAddRadius: avgDetectedRadius.roundToDouble(),
          clearError: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        detectionProgress: 0.0,
        detectionStage: '',
        errorMessage: 'Detection failed: $e',
      );
    }
  }

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

// --- Background Isolate Helpers ---

class _DetectionParams {
  final Uint8List imageBytes;
  final double sensitivity;
  final double minRadius;
  final double maxRadius;
  final double solidityThreshold;
  final double outlierFraction;

  _DetectionParams({
    required this.imageBytes,
    required this.sensitivity,
    required this.minRadius,
    required this.maxRadius,
    required this.solidityThreshold,
    required this.outlierFraction,
  });
}

Future<DetectionResult> _runClassicalDetectionIsolate(_DetectionParams params) {
  return ClassicalCVDetector.detect(
    params.imageBytes,
    sensitivity: params.sensitivity,
    minRadius: params.minRadius,
    maxRadius: params.maxRadius,
    solidityThreshold: params.solidityThreshold,
    outlierFraction: params.outlierFraction,
  );
}

class _ImageDims {
  final int width;
  final int height;
  _ImageDims(this.width, this.height);
}

_ImageDims? _decodeImageDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return _ImageDims(decoded.width, decoded.height);
}
