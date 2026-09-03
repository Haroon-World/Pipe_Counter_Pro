import 'dart:typed_data';
import '../models/pipe_detection.dart';

class TFLiteDetector {
  bool get isModelLoaded => false;
  String? get loadedModelPath => null;

  Future<void> loadModel(String modelPath) async {
    throw UnsupportedError(
      'Engine B (TFLite) is supported on native Android, iOS, Windows, macOS, and Linux targets. Please use Engine A (Classical CV) in browser mode.',
    );
  }

  void close() {}

  Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double confidenceThreshold = 0.50,
    double solidityThreshold = 0.85,
    double? initialThreshold,
  }) async {
    throw UnsupportedError(
      'Engine B (TFLite) is supported on native Android, iOS, Windows, macOS, and Linux targets. Please use Engine A (Classical CV) in browser mode.',
    );
  }
}

