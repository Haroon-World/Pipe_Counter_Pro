import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pipe_counter_pro/services/ellipse_fit.dart';

void main() {
  group('EllipseFitService Tests', () {
    test('fits exact circle accurately', () {
      final points = <math.Point<num>>[];
      const cx = 100.0;
      const cy = 150.0;
      const r = 40.0;

      // Generate 36 sample points along a circle
      for (int i = 0; i < 36; i++) {
        final rad = i * 10 * math.pi / 180.0;
        points.add(math.Point(cx + r * math.cos(rad), cy + r * math.sin(rad)));
      }

      final fitted = EllipseFitService.fit(points);
      expect(fitted, isNotNull);
      expect(fitted!.isValid, isTrue);

      // Centroid check
      expect(fitted.cx, closeTo(cx, 0.5));
      expect(fitted.cy, closeTo(cy, 0.5));

      // Diameter check (width and height should be ~2 * r = 80)
      expect(fitted.width, closeTo(80.0, 1.0));
      expect(fitted.height, closeTo(80.0, 1.0));

      // Area check (pi * r^2)
      expect(fitted.area, closeTo(math.pi * r * r, 20.0));
    });

    test('fits rotated ellipse accurately', () {
      final points = <math.Point<num>>[];
      const cx = 200.0;
      const cy = 300.0;
      const a = 50.0; // semi-major
      const b = 30.0; // semi-minor
      const angleDeg = 30.0;
      const angleRad = angleDeg * math.pi / 180.0;

      for (int i = 0; i < 36; i++) {
        final t = i * 10 * math.pi / 180.0;
        final x0 = a * math.cos(t);
        final y0 = b * math.sin(t);
        // Rotate
        final xr = cx + x0 * math.cos(angleRad) - y0 * math.sin(angleRad);
        final yr = cy + x0 * math.sin(angleRad) + y0 * math.cos(angleRad);
        points.add(math.Point(xr, yr));
      }

      final fitted = EllipseFitService.fit(points);
      expect(fitted, isNotNull);
      expect(fitted!.cx, closeTo(cx, 1.0));
      expect(fitted.cy, closeTo(cy, 1.0));
      expect(math.max(fitted.width, fitted.height), closeTo(2 * a, 2.0));
      expect(math.min(fitted.width, fitted.height), closeTo(2 * b, 2.0));
    });

    test('returns null for fewer than 5 points', () {
      final points = [
        const math.Point(0, 0),
        const math.Point(1, 1),
        const math.Point(2, 2),
        const math.Point(3, 3),
      ];
      final fitted = EllipseFitService.fit(points);
      expect(fitted, isNull);
    });
  });
}


