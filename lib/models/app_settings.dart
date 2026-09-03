enum DetectionEngine {
  classicalCV('Engine A (Classical CV)', 'Hough Circle Transform + ROI Ellipse Refinement + Solidity Convexity Filtering. Completely offline, zero training required.'),
  tflite('Engine B (Custom ML)', 'Custom TensorFlow Lite model (fine-tuned on pipe imagery) with ROI ellipse refinement and solidity check.');

  final String title;
  final String description;
  const DetectionEngine(this.title, this.description);
}

class AppSettings {
  final DetectionEngine engine;
  final double sensitivity; // 0.10 to 0.90 (Hough accumulator or ML confidence)
  final double minRadius; // minimum expected pipe radius in pixels (default 8.0)
  final double maxRadius; // maximum expected pipe radius in pixels (default 65.0)
  final double solidityThreshold; // minimum contour / convex hull solidity (default 0.85)
  final double outlierFraction; // minimum fraction of median area to retain (default 0.12)
  final String? customModelPath;
  final String? customModelName;

  const AppSettings({
    this.engine = DetectionEngine.classicalCV,
    this.sensitivity = 0.50,
    this.minRadius = 8.0,
    this.maxRadius = 65.0,
    this.solidityThreshold = 0.85,
    this.outlierFraction = 0.12,
    this.customModelPath,
    this.customModelName,
  });

  AppSettings copyWith({
    DetectionEngine? engine,
    double? sensitivity,
    double? minRadius,
    double? maxRadius,
    double? solidityThreshold,
    double? outlierFraction,
    String? customModelPath,
    String? customModelName,
    bool clearModel = false,
  }) {
    return AppSettings(
      engine: engine ?? this.engine,
      sensitivity: sensitivity ?? this.sensitivity,
      minRadius: minRadius ?? this.minRadius,
      maxRadius: maxRadius ?? this.maxRadius,
      solidityThreshold: solidityThreshold ?? this.solidityThreshold,
      outlierFraction: outlierFraction ?? this.outlierFraction,
      customModelPath: clearModel ? null : (customModelPath ?? this.customModelPath),
      customModelName: clearModel ? null : (customModelName ?? this.customModelName),
    );
  }
}
