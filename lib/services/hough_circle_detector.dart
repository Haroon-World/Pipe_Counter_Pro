import 'dart:math' as math;
import 'dart:typed_data';

class HoughCircle {
  final double cx;
  final double cy;
  final double radius;
  final double score;

  const HoughCircle({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.score,
  });
}

class HoughCircleDetector {
  /// Detects circular candidates using the 2.1D Hough Gradient Accumulator.
  /// Edge gradients vote along normal rays, eliminating concave 3-pipe gaps.
  static List<HoughCircle> detectCircles(
    Uint8List gray,
    int width,
    int height, {
    required double minRadius,
    required double maxRadius,
    required double sensitivity, // 0.10 to 0.90
  }) {
    if (minRadius <= 0 || maxRadius <= minRadius) return [];

    final rMin = minRadius.round().clamp(3, math.min(width, height) ~/ 2);
    final rMax = maxRadius.round().clamp(rMin + 1, math.min(width, height) ~/ 2);

    // 1. Calculate Sobel gradients and edge magnitudes
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

    if (maxMag < 20) return [];

    // Edge gradient threshold based on sensitivity
    final edgeThreshold = ((1.0 - sensitivity * 0.75) * 80.0).clamp(18.0, 150.0).toInt();

    // 2. Accumulator grid (scale = 2 for performance and vote clustering)
    const accScale = 2;
    final accW = (width / accScale).ceil();
    final accH = (height / accScale).ceil();
    final accum = Int32List(accW * accH);

    final edgePoints = <int>[];

    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = row + x;
        final m = mag[idx];
        if (m < edgeThreshold) continue;

        edgePoints.add(idx);

        final vx = gx[idx];
        final vy = gy[idx];
        final norm = math.sqrt((vx * vx + vy * vy).toDouble());
        if (norm == 0) continue;

        final dirX = vx / norm;
        final dirY = vy / norm;

        // Cast votes along gradient normal line in both directions (inward and outward)
        for (int r = rMin; r <= rMax; r += 2) {
          // Direction 1: x + r * dirX
          final cx1 = ((x + r * dirX) / accScale).round();
          final cy1 = ((y + r * dirY) / accScale).round();
          if (cx1 >= 0 && cx1 < accW && cy1 >= 0 && cy1 < accH) {
            accum[cy1 * accW + cx1]++;
          }

          // Direction 2: x - r * dirX
          final cx2 = ((x - r * dirX) / accScale).round();
          final cy2 = ((y - r * dirY) / accScale).round();
          if (cx2 >= 0 && cx2 < accW && cy2 >= 0 && cy2 < accH) {
            accum[cy2 * accW + cx2]++;
          }
        }
      }
    }

    if (edgePoints.isEmpty) return [];

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

    for (int ay = 1; ay < accH - 1; ay++) {
      final aRow = ay * accW;
      for (int ax = 1; ax < accW - 1; ax++) {
        final votes = accum[aRow + ax];
        if (votes < voteThreshold) continue;

        // 8-neighborhood local maximum check
        bool isPeak = true;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (accum[(ay + dy) * accW + (ax + dx)] > votes) {
              isPeak = false;
              break;
            }
          }
          if (!isPeak) break;
        }

        if (!isPeak) continue;

        final realCx = (ax * accScale + accScale / 2.0);
        final realCy = (ay * accScale + accScale / 2.0);

        // 4. Refine optimal radius for this candidate center
        final radiusHist = Int32List(rMax - rMin + 1);
        final searchRMaxSq = (rMax + 4) * (rMax + 4);
        final searchRMinSq = (rMin - 4) * (rMin - 4);

        for (final edgeIdx in edgePoints) {
          final ex = edgeIdx % width;
          final ey = edgeIdx ~/ width;
          final dx = ex - realCx;
          final dy = ey - realCy;
          final distSq = dx * dx + dy * dy;

          if (distSq >= searchRMinSq && distSq <= searchRMaxSq) {
            final dist = math.sqrt(distSq).round();
            final rIdx = dist - rMin;
            if (rIdx >= 0 && rIdx < radiusHist.length) {
              radiusHist[rIdx]++;
            }
          }
        }

        int bestRIdx = 0;
        int maxRCount = 0;
        for (int i = 0; i < radiusHist.length; i++) {
          // Smooth 3-bin count
          final cPrev = i > 0 ? radiusHist[i - 1] : 0;
          final cCurr = radiusHist[i];
          final cNext = i < radiusHist.length - 1 ? radiusHist[i + 1] : 0;
          final count = cPrev + cCurr + cNext;
          if (count > maxRCount) {
            maxRCount = count;
            bestRIdx = i;
          }
        }

        final bestR = (rMin + bestRIdx).toDouble();

        // Minimum coverage: circle circumference expected points
        final expectedCircumference = 2.0 * math.pi * bestR;
        final supportRatio = maxRCount / expectedCircumference;

        if (supportRatio >= 0.15) {
          candidates.add(HoughCircle(
            cx: realCx,
            cy: realCy,
            radius: bestR,
            score: votes.toDouble(),
          ));
        }
      }
    }

    // 5. Non-Maximum Suppression to deduplicate nearby proposed centers
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <HoughCircle>[];

    for (final cand in candidates) {
      bool isDupe = false;
      for (final existing in kept) {
        final dx = cand.cx - existing.cx;
        final dy = cand.cy - existing.cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        final avgR = (cand.radius + existing.radius) / 2.0;

        if (dist < avgR * 0.50) {
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

