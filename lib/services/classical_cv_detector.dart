import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/pipe_detection.dart';
import 'ellipse_fit.dart';
import 'geometry_utils.dart';
import 'hough_circle_detector.dart';
import 'image_filters.dart';

class ClassicalCVDetector {
  static const int maxProcessingDimension = 1024;

  /// Runs the full Hollow-Focused Classical CV pipeline:
  /// 1. Grayscale + CLAHE + 3x3 Median Blur
  /// 2. Candidate hollow center proposal via Hough Circle Transform
  /// 3. 24-ray radial profiler to trace the exact inner hollow boundary
  ///    (locating the sharp transition from dark hollow interior to bright pipe wall)
  /// 4. 360-degree boundary enclosure, angular gap, and radial consistency checks
  /// 5. 5-point algebraic ellipse fitting to circle the hollow opening of the pipe
  /// 6. Monotone Chain convex hull solidity filter (rejects concave interstitial gaps)
  /// 7. Physical non-maximum suppression (1 pipe = 1 circle)
  /// 8. Median-based outlier area rejection
  static Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double sensitivity = 0.50, // 0.10 to 0.90
    double minRadius = 8.0,
    double maxRadius = 32.0,
    double solidityThreshold = 0.85,
    double outlierFraction = 0.12,
    double? initialThreshold,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. Decode image
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image file. Format unsupported or corrupted.');
    }

    final origW = decoded.width;
    final origH = decoded.height;

    // 2. Downscale for processing if necessary while tracking scale factor
    img.Image procImage = decoded;
    double scaleFactor = 1.0;

    final maxDim = math.max(origW, origH);
    if (maxDim > maxProcessingDimension) {
      if (origW >= origH) {
        procImage = img.copyResize(decoded, width: maxProcessingDimension);
      } else {
        procImage = img.copyResize(decoded, height: maxProcessingDimension);
      }
      scaleFactor = origW / procImage.width;
    }

    final procW = procImage.width;
    final procH = procImage.height;

    // Scale min/max radius into processed image space
    final scaledMinR = (minRadius / scaleFactor).clamp(4.0, math.min(procW, procH) / 2);
    final scaledMaxR = (maxRadius / scaleFactor).clamp(scaledMinR + 2, math.min(procW, procH) / 2);

    // 3. Grayscale conversion & contrast enhancement
    final gray = ImageFilters.toGrayscale(procImage);
    final clahe = ImageFilters.applyCLAHE(gray, procW, procH);
    final blurred = ImageFilters.applyMedianBlur(clahe, procW, procH);

    // 4. Candidate centers from 2.1D Hough Circle Transform
    final houghSensitivity = (0.45 + sensitivity * 0.35).clamp(0.40, 0.85);
    final houghCircles = HoughCircleDetector.detectCircles(
      blurred,
      procW,
      procH,
      minRadius: scaledMinR,
      maxRadius: scaledMaxR,
      sensitivity: houghSensitivity,
    );

    // 5. Radial Ray-Casting: Inspect every candidate center and trace the exact inner hollow boundary
    final validatedPipes = <_CandidateHollow>[];

    const numRays = 24;
    final rSearchMin = math.max(4.0, scaledMinR * 0.70);
    final rSearchMax = scaledMaxR * 1.20;

    for (final c in houghCircles) {
      if (c.cx < rSearchMin || c.cx >= procW - rSearchMin || c.cy < rSearchMin || c.cy >= procH - rSearchMin) {
        continue;
      }

      // Sample core intensity inside the hollow
      double coreSum = 0;
      int coreCount = 0;
      final coreR = math.max(2, (scaledMinR * 0.25).round());
      for (int dy = -coreR; dy <= coreR; dy++) {
        for (int dx = -coreR; dx <= coreR; dx++) {
          final px = (c.cx + dx).round();
          final py = (c.cy + dy).round();
          if (px >= 0 && px < procW && py >= 0 && py < procH) {
            coreSum += gray[py * procW + px];
            coreCount++;
          }
        }
      }
      final coreAvg = coreCount > 0 ? coreSum / coreCount : 128.0;

      final boundaryPoints = <math.Point<double>>[];
      final rayAngles = <double>[];
      final rayRadii = <double>[];
      final quadrantRays = List<int>.filled(4, 0);
      double rimLumSum = 0;

      for (int i = 0; i < numRays; i++) {
        final angle = i * 2.0 * math.pi / numRays;
        final quad = (i * 4 ~/ numRays).clamp(0, 3);
        final cosA = math.cos(angle);
        final sinA = math.sin(angle);

        double maxGrad = -1;
        double bestR = -1;
        double bestRimLum = 0;

        for (double r = rSearchMin; r <= rSearchMax; r += 1.0) {
          final x1 = (c.cx + (r - 2) * cosA).round();
          final y1 = (c.cy + (r - 2) * sinA).round();
          final x2 = (c.cx + (r + 2) * cosA).round();
          final y2 = (c.cy + (r + 2) * sinA).round();

          if (x1 < 0 || x1 >= procW || y1 < 0 || y1 >= procH || x2 < 0 || x2 >= procW || y2 < 0 || y2 >= procH) {
            continue;
          }

          final lum1 = gray[y1 * procW + x1];
          final lum2 = gray[y2 * procW + x2];
          final grad = (lum2 - lum1).toDouble(); // positive outward step: dark hollow -> bright rim

          if (grad > maxGrad && lum2 > coreAvg + 6.0 && lum2 >= 135) {
            // Check that pixel is not a blue ceiling artifact
            final pPix = procImage.getPixel(x2, y2);
            final isNotBlue = (pPix.r + pPix.g) / 2.0 >= (pPix.b - 20);

            if (isNotBlue) {
              maxGrad = grad;
              bestR = r;
              bestRimLum = lum2.toDouble();
            }
          }
        }

        if (maxGrad >= 6.0 && bestR >= scaledMinR * 0.70 && bestR <= scaledMaxR * 1.15) {
          quadrantRays[quad]++;
          boundaryPoints.add(math.Point(c.cx + bestR * cosA, c.cy + bestR * sinA));
          rayAngles.add(angle);
          rayRadii.add(bestR);
          rimLumSum += bestRimLum;
        }
      }

      // Enclosure check: boundary must exist in at least 3 of 4 quadrants
      final quadsWithEdges = quadrantRays.where((count) => count >= 2).length;
      if (quadsWithEdges < 3 || boundaryPoints.length < 12) continue;

      // Angular gap check: reject open straight grooves, ceiling rafters, or beams
      rayAngles.sort();
      double maxAngularGap = (rayAngles.first + 2.0 * math.pi) - rayAngles.last;
      for (int i = 0; i < rayAngles.length - 1; i++) {
        final gap = rayAngles[i + 1] - rayAngles[i];
        if (gap > maxAngularGap) maxAngularGap = gap;
      }
      if (maxAngularGap > (95.0 * math.pi / 180.0)) continue;

      // Radial consistency check: hollows are circular or mildly elliptical
      final meanR = rayRadii.reduce((a, b) => a + b) / rayRadii.length;
      double varSum = 0;
      for (final r in rayRadii) {
        varSum += (r - meanR) * (r - meanR);
      }
      final stdR = math.sqrt(varSum / rayRadii.length);
      final radialCV = stdR / meanR;
      if (radialCV > 0.32) continue;

      // Contrast check: hollow core must be darker than surrounding rim
      final avgRim = rimLumSum / boundaryPoints.length;
      final contrast = avgRim - coreAvg;
      if (contrast < 6.5 || avgRim < 135.0) continue;

      // Fit ellipse directly to the hollow's inner boundary points
      final fitted = EllipseFitService.fit(boundaryPoints);
      if (fitted == null || !fitted.isValid) continue;

      // Aspect ratio sanity check (circular or mildly perspective-tilted oval)
      final major = math.max(fitted.width, fitted.height);
      final minor = math.min(fitted.width, fitted.height);
      if (minor <= 0 || (major / minor) > 1.75) continue;

      // Solidity check on the detected boundary points
      final solidity = GeometryUtils.calculateSolidity(boundaryPoints);
      if (solidity < solidityThreshold) continue;

      // Scale coordinates back to original image space
      final origCx = fitted.cx * scaleFactor;
      final origCy = fitted.cy * scaleFactor;
      final origW = fitted.width * scaleFactor;
      final origH = fitted.height * scaleFactor;
      final origArea = math.pi * (origW / 2.0) * (origH / 2.0);

      validatedPipes.add(_CandidateHollow(
        pipe: PipeDetection(
          id: 0,
          cx: origCx,
          cy: origCy,
          width: origW,
          height: origH,
          angle: fitted.angle,
          area: origArea,
          confidence: (contrast / 50.0).clamp(0.2, 1.0),
          solidity: solidity,
        ),
        contrast: contrast,
        pointsCount: boundaryPoints.length,
      ));
    }

    // 6. Physical Non-Maximum Suppression:
    // Because pipe hollows are physically separated by pipe walls, two distinct pipe hollows
    // can never overlap. Any centers closer than 1.15 * avgRadius are duplicate detections of the same pipe.
    validatedPipes.sort((a, b) => (b.contrast * b.pointsCount).compareTo(a.contrast * a.pointsCount));
    final deduplicated = <PipeDetection>[];

    for (final cand in validatedPipes) {
      final p = cand.pipe;
      bool isDuplicate = false;

      for (final existing in deduplicated) {
        final dx = p.cx - existing.cx;
        final dy = p.cy - existing.cy;
        final dist = math.sqrt(dx * dx + dy * dy);

        final avgR = (p.averageRadius + existing.averageRadius) / 2.0;

        if (dist < avgR * 1.15) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        deduplicated.add(p);
      }
    }

    // 7. Median-based outlier rejection:
    // If >= 4 pipes detected, drop any detection whose area is below outlierFraction of median area
    var finalSurviving = deduplicated;
    if (finalSurviving.length >= 4) {
      final sortedAreas = finalSurviving.map((p) => p.area).toList()..sort();
      final medianArea = sortedAreas[sortedAreas.length ~/ 2];
      final minAllowedArea = medianArea * outlierFraction;

      finalSurviving = finalSurviving.where((p) => p.area >= minAllowedArea).toList();
    }

    // Sort pipes geometrically (top-to-bottom, left-to-right) for logical sequential IDs
    finalSurviving.sort((a, b) {
      final yDiff = a.cy - b.cy;
      if (yDiff.abs() > 25 * scaleFactor) {
        return yDiff.compareTo(0);
      }
      return a.cx.compareTo(b.cx);
    });

    // 8. Compute default split threshold (median area)
    double effectiveThreshold = initialThreshold ?? 0.0;
    if (finalSurviving.isNotEmpty && (initialThreshold == null || initialThreshold <= 0)) {
      final sortedAreas = finalSurviving.map((p) => p.area).toList()..sort();
      effectiveThreshold = sortedAreas[sortedAreas.length ~/ 2];
    }

    // 9. Assign sequential IDs and category
    final finalPipes = <PipeDetection>[];
    for (int i = 0; i < finalSurviving.length; i++) {
      final p = finalSurviving[i];
      final cat = p.area < effectiveThreshold ? PipeCategory.small : PipeCategory.large;
      finalPipes.add(p.copyWith(id: i + 1, category: cat));
    }

    stopwatch.stop();

    return DetectionResult(
      pipes: finalPipes,
      imageWidth: origW,
      imageHeight: origH,
      processingTime: stopwatch.elapsed,
      engineName: 'Engine A (Classical CV: Hollow Ray Profiler + Solidity)',
      currentThreshold: effectiveThreshold,
    );
  }
}

class _CandidateHollow {
  final PipeDetection pipe;
  final double contrast;
  final int pointsCount;
  const _CandidateHollow({
    required this.pipe,
    required this.contrast,
    required this.pointsCount,
  });
}
