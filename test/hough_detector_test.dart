import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pipe_counter_pro/services/hough_circle_detector.dart';
import 'package:pipe_counter_pro/services/image_filters.dart';

void main() {
  test('HoughCircleDetector detects circle candidates', () {
    final testImg = img.Image(width: 300, height: 300);
    img.fill(testImg, color: img.ColorRgb8(20, 20, 20));

    // Draw bright circle at (150, 150) with radius 35
    for (int y = 0; y < 300; y++) {
      for (int x = 0; x < 300; x++) {
        final d = math.sqrt((x - 150) * (x - 150) + (y - 150) * (y - 150));
        if (d >= 32 && d <= 38) {
          testImg.setPixel(x, y, img.ColorRgb8(220, 220, 220));
        } else if (d < 32) {
          testImg.setPixel(x, y, img.ColorRgb8(5, 5, 5));
        }
      }
    }

    final gray = ImageFilters.toGrayscale(testImg);
    final circles = HoughCircleDetector.detectCircles(
      gray,
      300,
      300,
      minRadius: 20.0,
      maxRadius: 50.0,
      sensitivity: 0.50,
    );

    expect(circles, isNotEmpty);
    final best = circles.first;
    expect(best.cx, closeTo(150.0, 6.0));
    expect(best.cy, closeTo(150.0, 6.0));
    expect(best.radius, closeTo(35.0, 5.0));
  });
}
