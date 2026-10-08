import 'dart:typed_data';
import '../models/pipe_detection.dart';

class TFLiteDetector {
  bool get isModelLoaded => false;
  String? get loadedModelPath => null;

  Future<void> loadModel(String modelPath) async {
    throw UnsupportedError(
      'Engine A (Classical CV) is the primary engine for high-accuracy offline pipe counting.',
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
      'Engine A (Classical CV) is the primary engine for high-accuracy offline pipe counting.',
    );
  }
}
