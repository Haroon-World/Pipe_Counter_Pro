import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pipe_counter_pro/services/classical_cv_detector.dart';

void main() {
  test('ClassicalCVDetector detects concentric nested pipe inside larger pipe', () async {
    final testImg = img.Image(width: 300, height: 300);
    img.fill(testImg, color: img.ColorRgb8(20, 20, 25));

    const cx = 150;
    const cy = 150;
    const outerPipeOuterR = 55;
    const outerPipeInnerR = 48;
    const innerPipeOuterR = 24;
    const innerPipeInnerR = 18;

    for (int y = 0; y < 300; y++) {
      for (int x = 0; x < 300; x++) {
        final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        // Outer pipe rim
        if (d <= outerPipeOuterR && d >= outerPipeInnerR) {
          testImg.setPixel(x, y, img.ColorRgb8(230, 230, 235));
        }
        // Inner pipe rim
        else if (d <= innerPipeOuterR && d >= innerPipeInnerR) {
          testImg.setPixel(x, y, img.ColorRgb8(210, 210, 215));
        }
        // Hollow cavity of inner pipe
        else if (d < innerPipeInnerR) {
          testImg.setPixel(x, y, img.ColorRgb8(5, 5, 8));
        }
      }
    }

    final encoded = img.encodePng(testImg);

    final result = await ClassicalCVDetector.detect(
      encoded,
      sensitivity: 0.60,
      minRadius: 15.0,
      maxRadius: 65.0,
      solidityThreshold: 0.80,
    );

    // Both inner and outer circles should survive NMS
    expect(result.pipes.length, greaterThanOrEqualTo(2),
        reason: 'Both the inner pipe and the outer sleeve pipe should be detected');

    final nestedPipes = result.pipes.where((p) => p.isNested);
    expect(nestedPipes, isNotEmpty,
        reason: 'The inner pipe should be marked as nested');
  });
}
