import 'dart:math' as math;

enum PipeCategory {
  small,
  large;

  String get displayName => this == PipeCategory.small ? 'Small' : 'Large';
}

class PipeDetection {
  final int id;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final double angle; // in degrees (-90 to +90)
  final double area; // in px^2
  final PipeCategory category;
  final double confidence;
  final double solidity; // contourArea / convexHullArea (0.0 to 1.0)

  const PipeDetection({
    required this.id,
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.angle,
    required this.area,
    this.category = PipeCategory.small,
    this.confidence = 1.0,
    this.solidity = 1.0,
  });

  /// Approximate radius based on average of semi-axes
  double get averageRadius => (width + height) / 4.0;

  /// Aspect ratio: minor axis / major axis (0.0 to 1.0)
  double get aspectRatio {
    final major = math.max(width, height);
    final minor = math.min(width, height);
    return major > 0 ? (minor / major) : 1.0;
  }

  PipeDetection copyWith({
    int? id,
    double? cx,
    double? cy,
    double? width,
    double? height,
    double? angle,
    double? area,
    PipeCategory? category,
    double? confidence,
    double? solidity,
  }) {
    return PipeDetection(
      id: id ?? this.id,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      width: width ?? this.width,
      height: height ?? this.height,
      angle: angle ?? this.angle,
      area: area ?? this.area,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      solidity: solidity ?? this.solidity,
    );
  }

  /// Scale detection coordinates by a factor (e.g., from processed thumbnail to original size)
  PipeDetection scaled(double factor) {
    if (factor == 1.0) return this;
    final newWidth = width * factor;
    final newHeight = height * factor;
    final newArea = math.pi * (newWidth / 2.0) * (newHeight / 2.0);
    return PipeDetection(
      id: id,
      cx: cx * factor,
      cy: cy * factor,
      width: newWidth,
      height: newHeight,
      angle: angle,
      area: newArea,
      category: category,
      confidence: confidence,
      solidity: solidity,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cx': cx,
      'cy': cy,
      'width': width,
      'height': height,
      'angle': angle,
      'area': area,
      'category': category.name,
      'confidence': confidence,
      'solidity': solidity,
    };
  }

  factory PipeDetection.fromMap(Map<String, dynamic> map) {
    return PipeDetection(
      id: map['id'] as int,
      cx: (map['cx'] as num).toDouble(),
      cy: (map['cy'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
      angle: (map['angle'] as num).toDouble(),
      area: (map['area'] as num).toDouble(),
      category: map['category'] == 'large' ? PipeCategory.large : PipeCategory.small,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      solidity: (map['solidity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class DetectionResult {
  final List<PipeDetection> pipes;
  final int imageWidth;
  final int imageHeight;
  final Duration processingTime;
  final String engineName;
  final double currentThreshold;

  const DetectionResult({
    required this.pipes,
    required this.imageWidth,
    required this.imageHeight,
    required this.processingTime,
    required this.engineName,
    required this.currentThreshold,
  });

  int get totalCount => pipes.length;

  int get smallCount =>
      pipes.where((p) => p.category == PipeCategory.small).length;

  int get largeCount =>
      pipes.where((p) => p.category == PipeCategory.large).length;

  double get minArea {
    if (pipes.isEmpty) return 0.0;
    return pipes.map((p) => p.area).reduce(math.min);
  }

  double get maxArea {
    if (pipes.isEmpty) return 1000.0;
    return pipes.map((p) => p.area).reduce(math.max);
  }

  double get medianArea {
    if (pipes.isEmpty) return 500.0;
    final sorted = pipes.map((p) => p.area).toList()..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
  }

  /// Instantly recalculate categories based on a new size threshold without re-running detection
  DetectionResult reclassifiedWithThreshold(double threshold) {
    final updated = pipes.map((p) {
      final cat = p.area < threshold ? PipeCategory.small : PipeCategory.large;
      return p.copyWith(category: cat);
    }).toList();

    return DetectionResult(
      pipes: updated,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      processingTime: processingTime,
      engineName: engineName,
      currentThreshold: threshold,
    );
  }
}
