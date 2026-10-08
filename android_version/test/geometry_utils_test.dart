import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pipe_counter_pro/services/geometry_utils.dart';

void main() {
  group('GeometryUtils Convex Hull & Solidity Tests', () {
    test('computes polygon area of a 10x10 square', () {
      final square = [
        const math.Point(0.0, 0.0),
        const math.Point(10.0, 0.0),
        const math.Point(10.0, 10.0),
        const math.Point(0.0, 10.0),
      ];
      expect(GeometryUtils.polygonArea(square), closeTo(100.0, 0.01));
    });

    test('convex circular points have high solidity (> 0.95)', () {
      final circlePts = <math.Point<num>>[];
      for (int i = 0; i < 36; i++) {
        final rad = i * 10 * math.pi / 180.0;
        circlePts.add(math.Point(50 + 20 * math.cos(rad), 50 + 20 * math.sin(rad)));
      }

      final solidity = GeometryUtils.calculateSolidity(circlePts);
      expect(solidity, greaterThanOrEqualTo(0.95));
    });

    test('concave gap shape (3-point star) has low solidity (< 0.80)', () {
      // Simulates the concave interstitial gap between three packed circular pipes:
      // Outer 3 vertices (convex hull points) with deeply indented arcs/cusps between them
      final gapPts = <math.Point<num>>[
        // Top vertex
        const math.Point(50.0, 10.0),
        // Inward concave curve towards center (35, 35)
        const math.Point(45.0, 25.0),
        const math.Point(40.0, 35.0),
        const math.Point(30.0, 45.0),
        // Bottom-left vertex
        const math.Point(15.0, 75.0),
        // Inward concave curve along bottom
        const math.Point(35.0, 60.0),
        const math.Point(50.0, 55.0),
        const math.Point(65.0, 60.0),
        // Bottom-right vertex
        const math.Point(85.0, 75.0),
        // Inward concave curve back to top
        const math.Point(70.0, 45.0),
        const math.Point(60.0, 35.0),
        const math.Point(55.0, 25.0),
      ];

      final solidity = GeometryUtils.calculateSolidity(gapPts);
      expect(solidity, lessThan(0.80),
          reason: 'Concave gap between 3 pipes should have solidity < 0.80, safely failing the 0.85 threshold');
    });
  });
}
