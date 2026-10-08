import 'dart:math' as math;

class GeometryUtils {
  /// Computes 2D Convex Hull of points using Monotone Chain (Andrew's algorithm).
  /// Returns vertices of the convex hull in counter-clockwise order.
  static List<math.Point<double>> computeConvexHull(List<math.Point<num>> points) {
    if (points.length <= 2) {
      return points.map((p) => math.Point(p.x.toDouble(), p.y.toDouble())).toList();
    }

    // 1. Sort points lexicographically by X, then by Y
    final sorted = points.map((p) => math.Point(p.x.toDouble(), p.y.toDouble())).toList()
      ..sort((a, b) {
        final cmp = a.x.compareTo(b.x);
        return cmp != 0 ? cmp : a.y.compareTo(b.y);
      });

    // Remove duplicates
    final unique = <math.Point<double>>[];
    for (int i = 0; i < sorted.length; i++) {
      if (i == 0 || sorted[i].x != sorted[i - 1].x || sorted[i].y != sorted[i - 1].y) {
        unique.add(sorted[i]);
      }
    }

    if (unique.length <= 2) return unique;

    // 2D cross product of OA and OB vectors: (A.x - O.x)*(B.y - O.y) - (A.y - O.y)*(B.x - O.x)
    double crossProduct(math.Point<double> o, math.Point<double> a, math.Point<double> b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    // 2. Build lower hull
    final lower = <math.Point<double>>[];
    for (final p in unique) {
      while (lower.length >= 2 && crossProduct(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    // 3. Build upper hull
    final upper = <math.Point<double>>[];
    for (int i = unique.length - 1; i >= 0; i--) {
      final p = unique[i];
      while (upper.length >= 2 && crossProduct(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    // Remove last point of each half because it's repeated
    lower.removeLast();
    upper.removeLast();

    return [...lower, ...upper];
  }

  /// Computes polygon area using the Shoelace formula (Gauss's area formula).
  static double polygonArea(List<math.Point<double>> vertices) {
    final n = vertices.length;
    if (n < 3) return 0.0;

    double sum = 0.0;
    for (int i = 0; i < n; i++) {
      final p1 = vertices[i];
      final p2 = vertices[(i + 1) % n];
      sum += (p1.x * p2.y) - (p2.x * p1.y);
    }
    return (sum.abs()) / 2.0;
  }

  /// Extracts boundary contour vertices sorted radially by polar angle around centroid.
  static List<math.Point<double>> orderBoundaryByAngle(List<math.Point<num>> points, {int sectors = 72}) {
    if (points.length < 3) {
      return points.map((p) => math.Point(p.x.toDouble(), p.y.toDouble())).toList();
    }

    // Centroid
    double sumX = 0.0;
    double sumY = 0.0;
    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
    }
    final cx = sumX / points.length;
    final cy = sumY / points.length;

    // Bin points by angle sector and keep the farthest point in each sector
    final sectorPoints = List<math.Point<double>?>.filled(sectors, null);
    final sectorDistSq = List<double>.filled(sectors, -1.0);

    for (final p in points) {
      final dx = p.x - cx;
      final dy = p.y - cy;
      final angle = math.atan2(dy, dx); // -pi to +pi
      final normalizedAngle = (angle + math.pi) / (2.0 * math.pi); // 0.0 to 1.0
      final secIdx = (normalizedAngle * sectors).floor().clamp(0, sectors - 1);

      final distSq = dx * dx + dy * dy;
      if (distSq > sectorDistSq[secIdx]) {
        sectorDistSq[secIdx] = distSq;
        sectorPoints[secIdx] = math.Point(p.x.toDouble(), p.y.toDouble());
      }
    }

    final ordered = <math.Point<double>>[];
    for (int i = 0; i < sectors; i++) {
      if (sectorPoints[i] != null) {
        ordered.add(sectorPoints[i]!);
      }
    }

    return ordered;
  }

  /// Calculates solidity of a 2D contour: contourArea / convexHullArea.
  /// For closed circular/elliptical pipe openings: solidity is approx 0.90 to 1.0.
  /// For concave gaps between three touching circles: solidity is approx 0.60 to 0.85.
  static double calculateSolidity(List<math.Point<num>> contourPoints, {double? knownContourArea}) {
    if (contourPoints.length < 5) return 1.0;

    final hull = computeConvexHull(contourPoints);
    final hullArea = polygonArea(hull);
    if (hullArea <= 0.001) return 1.0;

    final double contourArea;
    if (knownContourArea != null && knownContourArea > 0) {
      contourArea = knownContourArea;
    } else {
      final ordered = orderBoundaryByAngle(contourPoints);
      contourArea = polygonArea(ordered);
    }

    final solidity = contourArea / hullArea;
    return solidity.clamp(0.0, 1.0);
  }
}
