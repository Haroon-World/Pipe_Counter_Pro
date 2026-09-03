import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pipe_counter_pro/services/classical_cv_detector.dart';

void main() {
  test('ClassicalCVDetector detects circular pipe openings and rejects concave gaps', () async {
    final testImg = img.Image(width: 400, height: 350);
    img.fill(testImg, color: img.ColorRgb8(25, 25, 30));

    void drawPipe(int cx, int cy, int outerR, int innerR) {
      for (int y = cy - outerR - 2; y <= cy + outerR + 2; y++) {
        for (int x = cx - outerR - 2; x <= cx + outerR + 2; x++) {
          if (x < 0 || x >= 400 || y < 0 || y >= 350) continue;
          final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
          if (d <= outerR && d >= innerR) {
            testImg.setPixel(x, y, img.ColorRgb8(225, 225, 230));
          } else if (d < innerR) {
            testImg.setPixel(x, y, img.ColorRgb8(8, 10, 14));
          }
        }
      }
    }

    // Draw 3 pipes packed tightly in a triangular configuration:
    // Pipe 1 (left): (140, 200), radius 36
    // Pipe 2 (right): (220, 200), radius 36
    // Pipe 3 (top): (180, 130), radius 36
    // The interstitial gap between them is centered near (180, 175)
    drawPipe(140, 200, 36, 30);
    drawPipe(220, 200, 36, 30);
    drawPipe(180, 130, 36, 30);

    final encoded = img.encodePng(testImg);

    final result = await ClassicalCVDetector.detect(
      encoded,
      sensitivity: 0.55,
      minRadius: 20.0,
      maxRadius: 50.0,
      solidityThreshold: 0.85,
    );

    // Verify detected pipes
    expect(result.pipes.length, greaterThanOrEqualTo(2));

    // Verify no detection is centered in the hollow interstitial gap between the three pipes
    final falsePositiveGap = result.pipes.where(
      (p) => (p.cx - 180).abs() < 12 && (p.cy - 175).abs() < 12,
    );
    expect(falsePositiveGap, isEmpty,
        reason: 'Interstitial gap between 3 packed pipes must be rejected by Hough + Solidity pipeline');

    // Verify all detected pipes have high solidity (>= 0.85)
    for (final pipe in result.pipes) {
      expect(pipe.solidity, greaterThanOrEqualTo(0.85));
    }
  });
}
