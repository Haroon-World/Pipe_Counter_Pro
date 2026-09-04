import 'dart:math' as math;

enum PipeCategory {
  small,
  medium,
  large;

  String get displayName {
    switch (this) {
      case PipeCategory.small:
        return 'Small';
      case PipeCategory.medium:
        return 'Medium';
      case PipeCategory.large:
        return 'Large';
    }
  }

  String get labelWithColor {
    switch (this) {
      case PipeCategory.small:
        return 'Small (Green)';
      case PipeCategory.medium:
        return 'Medium (Yellow)';
      case PipeCategory.large:
        return 'Large (Red)';
    }
  }

  String get colorHex {
    switch (this) {
      case PipeCategory.small:
        return '#22c55e';
      case PipeCategory.medium:
        return '#eab308';
      case PipeCategory.large:
        return '#ef4444';
    }
  }
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
  final bool isSelected; // True = active/counted, False = deselected/excluded
  final bool isManual; // True if manually added by user

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
    this.isSelected = true,
    this.isManual = false,
  });

  /// Approximate diameter based on average of width and height
  double get diameter => (width + height) / 2.0;

  /// Approximate radius based on average of semi-axes
  double get averageRadius => diameter / 2.0;

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
    bool? isSelected,
    bool? isManual,
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
      isSelected: isSelected ?? this.isSelected,
      isManual: isManual ?? this.isManual,
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
      isSelected: isSelected,
      isManual: isManual,
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
      'isSelected': isSelected,
      'isManual': isManual,
    };
  }

  factory PipeDetection.fromMap(Map<String, dynamic> map) {
    PipeCategory cat;
    final catStr = (map['category'] as String?)?.toLowerCase();
    if (catStr == 'large') {
      cat = PipeCategory.large;
    } else if (catStr == 'medium') {
      cat = PipeCategory.medium;
    } else {
      cat = PipeCategory.small;
    }

    return PipeDetection(
      id: map['id'] as int,
      cx: (map['cx'] as num).toDouble(),
      cy: (map['cy'] as num).toDouble(),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
      angle: (map['angle'] as num).toDouble(),
      area: (map['area'] as num).toDouble(),
      category: cat,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      solidity: (map['solidity'] as num?)?.toDouble() ?? 1.0,
      isSelected: (map['isSelected'] as bool?) ?? true,
      isManual: (map['isManual'] as bool?) ?? false,
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

  /// Total count of all marked pipes
  int get totalCount => pipes.length;

  /// Active (counted) pipes
  int get activeCount => pipes.where((p) => p.isSelected).length;

  /// Deselected / excluded pipes
  int get deselectedCount => pipes.where((p) => !p.isSelected).length;

  int get smallCount =>
      pipes.where((p) => p.isSelected && p.category == PipeCategory.small).length;

  int get mediumCount =>
      pipes.where((p) => p.isSelected && p.category == PipeCategory.medium).length;

  int get largeCount =>
      pipes.where((p) => p.isSelected && p.category == PipeCategory.large).length;

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

  /// Instantly recalculate categories based on a size threshold
  DetectionResult reclassifiedWithThreshold(double threshold) {
    final updated = pipes.map((p) {
      // Keep manual user colors intact unless reclassified
      if (p.isManual) return p;
      final cat = p.area < threshold ? PipeCategory.small : PipeCategory.large;
      return p.copyWith(category: cat);
    }).toList();

    return copyWith(
      pipes: updated,
      currentThreshold: threshold,
    );
  }

  /// Toggle active/excluded state for a pipe
  DetectionResult withPipeToggled(int id) {
    final updated = pipes.map((p) {
      if (p.id == id) {
        return p.copyWith(isSelected: !p.isSelected);
      }
      return p;
    }).toList();
    return copyWith(pipes: updated);
  }

  /// Remove a pipe
  DetectionResult withPipeRemoved(int id) {
    final updated = pipes.where((p) => p.id != id).toList();
    return copyWith(pipes: updated);
  }

  /// Add a manual pipe
  DetectionResult withPipeAdded(PipeDetection pipe) {
    final updated = List<PipeDetection>.from(pipes)..add(pipe);
    return copyWith(pipes: updated);
  }

  /// Change a pipe's category
  DetectionResult withPipeRecolored(int id, PipeCategory newCategory) {
    final updated = pipes.map((p) {
      if (p.id == id) {
        return p.copyWith(category: newCategory);
      }
      return p;
    }).toList();
    return copyWith(pipes: updated);
  }

  DetectionResult copyWith({
    List<PipeDetection>? pipes,
    int? imageWidth,
    int? imageHeight,
    Duration? processingTime,
    String? engineName,
    double? currentThreshold,
  }) {
    return DetectionResult(
      pipes: pipes ?? this.pipes,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      processingTime: processingTime ?? this.processingTime,
      engineName: engineName ?? this.engineName,
      currentThreshold: currentThreshold ?? this.currentThreshold,
    );
  }
}
