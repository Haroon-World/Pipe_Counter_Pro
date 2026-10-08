import 'dart:math' as math;
import 'dart:typed_data';

class HoughCircle {
  final double cx;
  final double cy;
  final double radius;
  final double score;

  /// Fraction of the expected circumference backed by real edge pixels (0..~1.5).
  final double support;

  /// True when this circle is a secondary (concentric) radius peak found at the
  /// same accumulator center as a stronger circle — e.g. a small pipe sleeved
  /// inside a bigger pipe.
  final bool isSecondary;

  const HoughCircle({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.score,
    this.support = 0.0,
    this.isSecondary = false,
  });
}

/// Pre-computed Sobel gradient field. Computing it once and sharing it between
/// the global Hough scan, the auto-calibrator and the nested-pipe search avoids
/// recomputing the most expensive pass several times.
class GradientField {
  final int width;
  final int height;
  final Int32List gx;
  final Int32List gy;
  final Int32List mag;
  final int maxMag;

  GradientField._(this.width, this.height, this.gx, this.gy, this.mag, this.maxMag);

  factory GradientField.compute(Uint8List gray, int width, int height) {
    final gx = Int32List(width * height);
    final gy = Int32List(width * height);
    final mag = Int32List(width * height);

    int maxMag = 0;
    for (int y = 1; y < height - 1; y++) {
      final prevRow = (y - 1) * width;
      final currRow = y * width;
      final nextRow = (y + 1) * width;

      for (int x = 1; x < width - 1; x++) {
        final valGx = (gray[prevRow + x + 1] - gray[prevRow + x - 1]) +
            2 * (gray[currRow + x + 1] - gray[currRow + x - 1]) +
            (gray[nextRow + x + 1] - gray[nextRow + x - 1]);

        final valGy = (gray[nextRow + x - 1] - gray[prevRow + x - 1]) +
            2 * (gray[nextRow + x] - gray[prevRow + x]) +
            (gray[nextRow + x + 1] - gray[prevRow + x + 1]);

        final m = valGx.abs() + valGy.abs();
        gx[currRow + x] = valGx;
        gy[currRow + x] = valGy;
        mag[currRow + x] = m;
        if (m > maxMag) maxMag = m;
      }
    }
    return GradientField._(width, height, gx, gy, mag, maxMag);
  }

  /// Returns the magnitude value at the given percentile (0..1) using a
  /// histogram (O(N), no sorting).
  int magnitudePercentile(double p) {
    if (maxMag <= 0) return 0;
    final bins = Int32List(maxMag + 1);
    int count = 0;
    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        bins[mag[row + x]]++;
        count++;
      }
    }
    if (count == 0) return 0;
    final target = (count * p.clamp(0.0, 1.0)).round();
    int acc = 0;
    for (int i = 0; i < bins.length; i++) {
      acc += bins[i];
      if (acc >= target) return i;
    }
    return maxMag;
  }
}

class HoughCircleDetector {
  /// Converts the 0.10–0.90 sensitivity slider value into a Sobel edge threshold.
  static int edgeThresholdForSensitivity(double sensitivity) {
    return ((1.0 - sensitivity * 0.75) * 80.0).clamp(18.0, 150.0).toInt();
  }

  /// Inverse of [edgeThresholdForSensitivity]; used by the auto-calibrator to
  /// express an image-adaptive edge threshold as a slider value.
  static double sensitivityForEdgeThreshold(double edgeThreshold) {
    return ((1.0 - edgeThreshold / 80.0) / 0.75).clamp(0.10, 0.90);
  }

  /// Detects circular candidates using the 2.1D Hough Gradient Accumulator.
  /// Edge gradients vote along normal rays, eliminating concave 3-pipe gaps.
  ///
  /// When [detectConcentric] is true, a second, clearly separated radius peak
  /// at the same center is also emitted (flagged [HoughCircle.isSecondary]) so
  /// pipes nested concentrically inside other pipes are not lost.
  static List<HoughCircle> detectCircles(
    Uint8List gray,
    int width,
    int height, {
    required double minRadius,
    required double maxRadius,
    required double sensitivity, // 0.10 to 0.90
    GradientField? field,
    bool detectConcentric = false,
    int radiusStep = 2,
  }) {
    if (minRadius <= 0 || maxRadius <= minRadius) return [];

    final rMin = minRadius.round().clamp(3, math.min(width, height) ~/ 2);
    final rMax = maxRadius.round().clamp(rMin + 1, math.min(width, height) ~/ 2);

    // 1. Sobel gradients and edge magnitudes (shared if pre-computed)
    final grad = field ?? GradientField.compute(gray, width, height);
    final gx = grad.gx;
    final gy = grad.gy;
    final mag = grad.mag;

    if (grad.maxMag < 20) return [];

    // Edge gradient threshold based on sensitivity
    final edgeThreshold = edgeThresholdForSensitivity(sensitivity);

    // 2. Accumulator grid (scale = 2 for performance and vote clustering)
    const accScale = 2;
    final accW = (width / accScale).ceil();
    final accH = (height / accScale).ceil();
    final accum = Int32List(accW * accH);

    int edgeCount = 0;

    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = row + x;
        final m = mag[idx];
        if (m < edgeThreshold) continue;

        edgeCount++;

        final vx = gx[idx];
        final vy = gy[idx];
        final norm = math.sqrt((vx * vx + vy * vy).toDouble());
        if (norm == 0) continue;

        final dirX = vx / norm;
        final dirY = vy / norm;

        // Cast votes along gradient normal line in both directions (inward and outward)
        for (int r = rMin; r <= rMax; r += radiusStep) {
          final cx1 = ((x + r * dirX) / accScale).round();
          final cy1 = ((y + r * dirY) / accScale).round();
          if (cx1 >= 0 && cx1 < accW && cy1 >= 0 && cy1 < accH) {
            accum[cy1 * accW + cx1]++;
          }

          final cx2 = ((x - r * dirX) / accScale).round();
          final cy2 = ((y - r * dirY) / accScale).round();
          if (cx2 >= 0 && cx2 < accW && cy2 >= 0 && cy2 < accH) {
            accum[cy2 * accW + cx2]++;
          }
        }
      }
    }

    if (edgeCount == 0) return [];

    // Find maximum votes in accumulator
    int peakAccum = 0;
    for (int i = 0; i < accum.length; i++) {
      if (accum[i] > peakAccum) peakAccum = accum[i];
    }

    if (peakAccum < 6) return [];

    // Voting threshold (sensitivity: 0.10 strict, 0.90 sensitive)
    final voteThreshold = math.max(6, ((0.65 - sensitivity * 0.45) * peakAccum).round());

    // 3. Extract local maxima in accumulator
    final candidates = <HoughCircle>[];
    final radiusHist = Int32List(rMax - rMin + 1);

    for (int ay = 1; ay < accH - 1; ay++) {
      final aRow = ay * accW;
      for (int ax = 1; ax < accW - 1; ax++) {
        final votes = accum[aRow + ax];
        if (votes < voteThreshold) continue;

        // 8-neighborhood local maximum check
        bool isPeak = true;
        for (int dy = -1; dy <= 1 && isPeak; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (accum[(ay + dy) * accW + (ax + dx)] > votes) {
              isPeak = false;
              break;
            }
          }
        }

        if (!isPeak) continue;

        final realCx = (ax * accScale + accScale / 2.0);
        final realCy = (ay * accScale + accScale / 2.0);

        // 4. Refine optimal radius for this candidate center. Only the edge
        // pixels inside the candidate's bounding box can contribute, so scan
        // that window instead of every edge pixel in the image.
        radiusHist.fillRange(0, radiusHist.length, 0);
        final searchRMax = rMax + 4;
        final searchRMaxSq = searchRMax * searchRMax;
        final searchRMin = math.max(0, rMin - 4);
        final searchRMinSq = searchRMin * searchRMin;

        final x0 = math.max(1, (realCx - searchRMax).floor());
        final x1 = math.min(width - 2, (realCx + searchRMax).ceil());
        final y0 = math.max(1, (realCy - searchRMax).floor());
        final y1 = math.min(height - 2, (realCy + searchRMax).ceil());

        for (int ey = y0; ey <= y1; ey++) {
          final row = ey * width;
          final dy = ey - realCy;
          final dySq = dy * dy;
          if (dySq > searchRMaxSq) continue;
          for (int ex = x0; ex <= x1; ex++) {
            if (mag[row + ex] < edgeThreshold) continue;
            final dx = ex - realCx;
            final distSq = dx * dx + dySq;
            if (distSq >= searchRMinSq && distSq <= searchRMaxSq) {
              final rIdx = math.sqrt(distSq).round() - rMin;
              if (rIdx >= 0 && rIdx < radiusHist.length) {
                radiusHist[rIdx]++;
              }
            }
          }
        }

        // Smoothed 3-bin support normalised by circumference, so that large
        // circles do not automatically win just because they have more pixels.
        final smoothed = Float64List(radiusHist.length);
        for (int i = 0; i < radiusHist.length; i++) {
          final cPrev = i > 0 ? radiusHist[i - 1] : 0;
          final cNext = i < radiusHist.length - 1 ? radiusHist[i + 1] : 0;
          smoothed[i] = (cPrev + radiusHist[i] + cNext).toDouble();
        }

        int bestRIdx = 0;
        double maxRCount = 0;
        for (int i = 0; i < smoothed.length; i++) {
          if (smoothed[i] > maxRCount) {
            maxRCount = smoothed[i];
            bestRIdx = i;
          }
        }

        final bestR = (rMin + bestRIdx).toDouble();

        // Minimum coverage: circle circumference expected points
        final supportRatio = maxRCount / (2.0 * math.pi * bestR);

        if (supportRatio >= 0.15) {
          candidates.add(HoughCircle(
            cx: realCx,
            cy: realCy,
            radius: bestR,
            score: votes.toDouble(),
            support: supportRatio,
          ));

          // Secondary concentric peak (nested pipe sharing the same center)
          if (detectConcentric) {
            int secIdx = -1;
            double secSupport = 0;
            for (int i = 1; i < smoothed.length - 1; i++) {
              final r = (rMin + i).toDouble();
              final ratio = r < bestR ? r / bestR : bestR / r;
              if (ratio > 0.75) continue; // too close: same pipe's other wall edge
              if (smoothed[i] < smoothed[i - 1] || smoothed[i] < smoothed[i + 1]) continue;
              final s = smoothed[i] / (2.0 * math.pi * r);
              if (s > secSupport) {
                secSupport = s;
                secIdx = i;
              }
            }
            if (secIdx >= 0 && secSupport >= 0.35) {
              candidates.add(HoughCircle(
                cx: realCx,
                cy: realCy,
                radius: (rMin + secIdx).toDouble(),
                score: votes * 0.9,
                support: secSupport,
                isSecondary: true,
              ));
            }
          }
        }
      }
    }

    // 5. Non-Maximum Suppression to deduplicate nearby proposed centers.
    // Circles of clearly different radius (ratio <= 0.75) are never merged so
    // that concentric / nested pipes survive.
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <HoughCircle>[];

    for (final cand in candidates) {
      bool isDupe = false;
      for (final existing in kept) {
        final dx = cand.cx - existing.cx;
        final dy = cand.cy - existing.cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        final avgR = (cand.radius + existing.radius) / 2.0;
        final ratio = math.min(cand.radius, existing.radius) / math.max(cand.radius, existing.radius);

        if (dist < avgR * 0.50 && (!detectConcentric || ratio > 0.75)) {
          isDupe = true;
          break;
        }
      }
      if (!isDupe) {
        kept.add(cand);
      }
    }

    return kept;
  }
}
