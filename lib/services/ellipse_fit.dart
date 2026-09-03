import 'dart:math' as math;

class FittedEllipse {
  final double cx;
  final double cy;
  final double width; // 2 * major axis (diameter)
  final double height; // 2 * minor axis (diameter)
  final double angle; // in degrees (-90 to +90)
  final double area; // pi * a * b
  final double residualError;

  const FittedEllipse({
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.angle,
    required this.area,
    this.residualError = 0.0,
  });

  bool get isValid =>
      !cx.isNaN &&
      !cy.isNaN &&
      !width.isNaN &&
      !height.isNaN &&
      width > 0 &&
      height > 0 &&
      !angle.isNaN;
}

class EllipseFitService {
  /// Fits an ellipse to a collection of 2D points (minimum 5 points required).
  /// For points along the perimeter, the semi-axes are sqrt(2 * lambda).
  static FittedEllipse? fit(List<math.Point<num>> points) {
    if (points.length < 5) return null;

    final n = points.length;

    // 1. Centroid (cx, cy)
    double sumX = 0;
    double sumY = 0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
    }
    final cx = sumX / n;
    final cy = sumY / n;

    // 2. Central moments
    double mu20 = 0;
    double mu02 = 0;
    double mu11 = 0;

    for (final p in points) {
      final dx = p.x.toDouble() - cx;
      final dy = p.y.toDouble() - cy;
      mu20 += dx * dx;
      mu02 += dy * dy;
      mu11 += dx * dy;
    }

    mu20 /= n;
    mu02 /= n;
    mu11 /= n;

    // 3. Eigenvalues of covariance matrix
    final diff = mu20 - mu02;
    final term = math.sqrt(diff * diff + 4 * mu11 * mu11);

    final lambda1 = (mu20 + mu02 + term) / 2.0;
    final lambda2 = (mu20 + mu02 - term) / 2.0;

    if (lambda1 <= 0 || lambda2 <= 0) return null;

    // For points distributed along an ellipse perimeter:
    // semi_axis = sqrt(2 * lambda) -> full diameter = 2 * sqrt(2 * lambda)
    final majorAxis = 2.0 * math.sqrt(2.0 * lambda1);
    final minorAxis = 2.0 * math.sqrt(2.0 * lambda2);

    // 4. Orientation angle in degrees
    final angleRad = 0.5 * math.atan2(2 * mu11, diff);
    final angleDeg = angleRad * 180.0 / math.pi;

    // Area: pi * a * b
    final area = math.pi * (majorAxis / 2.0) * (minorAxis / 2.0);

    // 5. Residual fitting error
    double totalResidual = 0;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final a = majorAxis / 2.0;
    final b = minorAxis / 2.0;

    if (a > 0 && b > 0) {
      for (final p in points) {
        final dx = p.x.toDouble() - cx;
        final dy = p.y.toDouble() - cy;
        final xPrime = dx * cosA + dy * sinA;
        final yPrime = -dx * sinA + dy * cosA;
        final dist = (xPrime * xPrime) / (a * a) + (yPrime * yPrime) / (b * b) - 1.0;
        totalResidual += dist.abs();
      }
    }
    final avgResidual = totalResidual / n;

    return FittedEllipse(
      cx: cx,
      cy: cy,
      width: majorAxis,
      height: minorAxis,
      angle: angleDeg,
      area: area,
      residualError: avgResidual,
    );
  }
}
