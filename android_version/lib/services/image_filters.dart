import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageFilters {
  /// Converts an Image into a flat 8-bit grayscale array of size (width * height).
  static Uint8List toGrayscale(img.Image image) {
    final w = image.width;
    final h = image.height;
    final gray = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final luma = ((r * 77 + g * 150 + b * 29) >> 8).clamp(0, 255);
        gray[y * w + x] = luma;
      }
    }
    return gray;
  }

  /// Contrast-Limited Adaptive Histogram Equalization (CLAHE)
  static Uint8List applyCLAHE(
    Uint8List input,
    int width,
    int height, {
    int gridTilesX = 8,
    int gridTilesY = 8,
    double clipLimit = 2.5,
  }) {
    final output = Uint8List(width * height);
    final tileW = (width / gridTilesX).ceil();
    final tileH = (height / gridTilesY).ceil();

    final cdfs = List<Uint8List>.generate(
      gridTilesX * gridTilesY,
      (_) => Uint8List(256),
    );

    for (int ty = 0; ty < gridTilesY; ty++) {
      for (int tx = 0; tx < gridTilesX; tx++) {
        final startX = tx * tileW;
        final startY = ty * tileH;
        final endX = math.min(startX + tileW, width);
        final endY = math.min(startY + tileH, height);
        final numPixels = (endX - startX) * (endY - startY);

        if (numPixels == 0) continue;

        final hist = Int32List(256);
        for (int y = startY; y < endY; y++) {
          final rowOffset = y * width;
          for (int x = startX; x < endX; x++) {
            hist[input[rowOffset + x]]++;
          }
        }

        final clipThreshold = (clipLimit * numPixels / 256).round();
        int excess = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > clipThreshold) {
            excess += hist[i] - clipThreshold;
            hist[i] = clipThreshold;
          }
        }

        final bonus = excess ~/ 256;
        final remainder = excess % 256;
        for (int i = 0; i < 256; i++) {
          hist[i] += bonus;
          if (i < remainder) hist[i]++;
        }

        final cdf = cdfs[ty * gridTilesX + tx];
        int sum = 0;
        for (int i = 0; i < 256; i++) {
          sum += hist[i];
          cdf[i] = ((sum * 255) ~/ numPixels).clamp(0, 255);
        }
      }
    }

    for (int y = 0; y < height; y++) {
      final tyFloat = (y / tileH) - 0.5;
      final ty0 = tyFloat.floor().clamp(0, gridTilesY - 1);
      final ty1 = (ty0 + 1).clamp(0, gridTilesY - 1);
      final yWeight = (tyFloat - tyFloat.floor()).clamp(0.0, 1.0);

      final rowOffset = y * width;

      for (int x = 0; x < width; x++) {
        final txFloat = (x / tileW) - 0.5;
        final tx0 = txFloat.floor().clamp(0, gridTilesX - 1);
        final tx1 = (tx0 + 1).clamp(0, gridTilesX - 1);
        final xWeight = (txFloat - txFloat.floor()).clamp(0.0, 1.0);

        final val = input[rowOffset + x];

        final c00 = cdfs[ty0 * gridTilesX + tx0][val];
        final c10 = cdfs[ty0 * gridTilesX + tx1][val];
        final c01 = cdfs[ty1 * gridTilesX + tx0][val];
        final c11 = cdfs[ty1 * gridTilesX + tx1][val];

        final top = c00 * (1.0 - xWeight) + c10 * xWeight;
        final bottom = c01 * (1.0 - xWeight) + c11 * xWeight;
        final interpolated = top * (1.0 - yWeight) + bottom * yWeight;

        output[rowOffset + x] = interpolated.round().clamp(0, 255);
      }
    }

    return output;
  }


  /// 3x3 Median Blur: Removes speckles while preserving sharp circular pipe edges
  static Uint8List applyMedianBlur(Uint8List input, int width, int height) {
    final output = Uint8List(width * height);
    final window = Uint8List(9);

    for (int y = 1; y < height - 1; y++) {
      final rowPrev = (y - 1) * width;
      final rowCurr = y * width;
      final rowNext = (y + 1) * width;

      for (int x = 1; x < width - 1; x++) {
        window[0] = input[rowPrev + x - 1];
        window[1] = input[rowPrev + x];
        window[2] = input[rowPrev + x + 1];

        window[3] = input[rowCurr + x - 1];
        window[4] = input[rowCurr + x];
        window[5] = input[rowCurr + x + 1];

        window[6] = input[rowNext + x - 1];
        window[7] = input[rowNext + x];
        window[8] = input[rowNext + x + 1];

        window.sort();
        output[rowCurr + x] = window[4]; // 5th element = median
      }
    }

    return output;
  }
  /// 5x5 Separable Gaussian Blur
  static Uint8List applyGaussianBlur(Uint8List input, int width, int height) {
    final temp = Uint8List(width * height);
    final output = Uint8List(width * height);

    for (int y = 0; y < height; y++) {
      final row = y * width;
      for (int x = 0; x < width; x++) {
        final xm2 = math.max(0, x - 2);
        final xm1 = math.max(0, x - 1);
        final xp1 = math.min(width - 1, x + 1);
        final xp2 = math.min(width - 1, x + 2);

        final val = (input[row + xm2] * 1 +
                input[row + xm1] * 4 +
                input[row + x] * 6 +
                input[row + xp1] * 4 +
                input[row + xp2] * 1) >>
            4;
        temp[row + x] = val;
      }
    }

    for (int y = 0; y < height; y++) {
      final ym2 = math.max(0, y - 2) * width;
      final ym1 = math.max(0, y - 1) * width;
      final y0 = y * width;
      final yp1 = math.min(height - 1, y + 1) * width;
      final yp2 = math.min(height - 1, y + 2) * width;

      for (int x = 0; x < width; x++) {
        final val = (temp[ym2 + x] * 1 +
                temp[ym1 + x] * 4 +
                temp[y0 + x] * 6 +
                temp[yp1 + x] * 4 +
                temp[yp2 + x] * 1) >>
            4;
        output[y0 + x] = val;
      }
    }

    return output;
  }

  /// Canny Edge Detector: Sobel gradients + NMS + Hysteresis Thresholding
  static Uint8List applyCanny(
    Uint8List input,
    int width,
    int height, {
    required double sensitivity,
  }) {
    final count = width * height;
    final magnitude = Int32List(count);
    final direction = Uint8List(count);

    for (int y = 1; y < height - 1; y++) {
      final rowPrev = (y - 1) * width;
      final rowCurr = y * width;
      final rowNext = (y + 1) * width;

      for (int x = 1; x < width - 1; x++) {
        final gx = (input[rowPrev + x + 1] - input[rowPrev + x - 1]) +
            2 * (input[rowCurr + x + 1] - input[rowCurr + x - 1]) +
            (input[rowNext + x + 1] - input[rowNext + x - 1]);

        final gy = (input[rowNext + x - 1] - input[rowPrev + x - 1]) +
            2 * (input[rowNext + x] - input[rowPrev + x]) +
            (input[rowNext + x + 1] - input[rowPrev + x + 1]);

        final mag = gx.abs() + gy.abs();
        magnitude[rowCurr + x] = mag;

        final angle = math.atan2(gy.toDouble(), gx.toDouble()) * 180.0 / math.pi;
        final normalized = (angle < 0 ? angle + 180.0 : angle);
        if ((normalized >= 0 && normalized < 22.5) || (normalized >= 157.5 && normalized <= 180)) {
          direction[rowCurr + x] = 0;
        } else if (normalized >= 22.5 && normalized < 67.5) {
          direction[rowCurr + x] = 1;
        } else if (normalized >= 67.5 && normalized < 112.5) {
          direction[rowCurr + x] = 2;
        } else {
          direction[rowCurr + x] = 3;
        }
      }
    }

    final nms = Int32List(count);
    for (int y = 1; y < height - 1; y++) {
      final rowPrev = (y - 1) * width;
      final rowCurr = y * width;
      final rowNext = (y + 1) * width;

      for (int x = 1; x < width - 1; x++) {
        final idx = rowCurr + x;
        final mag = magnitude[idx];
        if (mag == 0) continue;

        final dir = direction[idx];
        int n1 = 0;
        int n2 = 0;

        if (dir == 0) {
          n1 = magnitude[rowCurr + x - 1];
          n2 = magnitude[rowCurr + x + 1];
        } else if (dir == 1) {
          n1 = magnitude[rowPrev + x + 1];
          n2 = magnitude[rowNext + x - 1];
        } else if (dir == 2) {
          n1 = magnitude[rowPrev + x];
          n2 = magnitude[rowNext + x];
        } else if (dir == 3) {
          n1 = magnitude[rowPrev + x - 1];
          n2 = magnitude[rowNext + x + 1];
        }

        if (mag >= n1 && mag >= n2) {
          nms[idx] = mag;
        }
      }
    }

    final highThreshold = ((1.0 - sensitivity * 0.8) * 160.0).clamp(25.0, 220.0).toInt();
    final lowThreshold = (highThreshold * 0.40).round();

    final edges = Uint8List(count);
    final stack = <int>[];

    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = row + x;
        if (nms[idx] >= highThreshold) {
          edges[idx] = 255;
          stack.add(idx);
        }
      }
    }

    while (stack.isNotEmpty) {
      final currIdx = stack.removeLast();
      final cx = currIdx % width;
      final cy = currIdx ~/ width;

      for (int dy = -1; dy <= 1; dy++) {
        final ny = cy + dy;
        if (ny < 1 || ny >= height - 1) continue;
        final nRow = ny * width;

        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          if (nx < 1 || nx >= width - 1) continue;

          final nIdx = nRow + nx;
          if (edges[nIdx] == 0 && nms[nIdx] >= lowThreshold) {
            edges[nIdx] = 255;
            stack.add(nIdx);
          }
        }
      }
    }

    return edges;
  }

  /// 3x3 Morphological Dilation to bridge discrete 1-pixel micro gaps
  static Uint8List applyDilation(Uint8List input, int width, int height) {
    final output = Uint8List(width * height);
    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        if (input[row + x] == 255) {
          for (int dy = -1; dy <= 1; dy++) {
            final nRow = (y + dy) * width;
            for (int dx = -1; dx <= 1; dx++) {
              output[nRow + (x + dx)] = 255;
            }
          }
        }
      }
    }
    return output;
  }
}

