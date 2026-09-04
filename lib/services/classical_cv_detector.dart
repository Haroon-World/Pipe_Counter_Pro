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
  /// 3. Adaptive 24-ray radial profiler to trace inner hollow boundaries
  /// 4. Ellipse fitting to circle the hollow opening of each pipe
  /// 5. Convexity & physical non-maximum suppression
  /// 6. Automatic 3-tier color sizing (Green / Yellow / Red) matching desktop
  static Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double sensitivity = 0.50, // 0.10 to 0.90
    double minRadius = 4.0,
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
    final houghSensitivity = (0.40 + sensitivity * 0.45).clamp(0.35, 0.92);
    final houghCircles = HoughCircleDetector.detectCircles(
      blurred,
      procW,
      procH,
      minRadius: scaledMinR,
      maxRadius: scaledMaxR,
      sensitivity: houghSensitivity,
    );

    // 5. Radial Ray-Casting: Inspect candidate centers and trace inner hollow boundary
    final validatedPipes = <_CandidateHollow>[];

    const numRays = 24;
    final rSearchMin = math.max(3.0, scaledMinR * 0.65);
    final rSearchMax = scaledMaxR * 1.30;

    for (final c in houghCircles) {
      if (c.cx < rSearchMin || c.cx >= procW - rSearchMin || c.cy < rSearchMin || c.cy >= procH - rSearchMin) {
        continue;
      }

      // Local center refinement: lock candidate center into the hollow luminance minimum
      int bestX = c.cx.round();
      int bestY = c.cy.round();
      int minLum = 255;
      final searchR = math.max(1, (c.radius * 0.25).round());
      for (int dy = -searchR; dy <= searchR; dy++) {
        for (int dx = -searchR; dx <= searchR; dx++) {
          final px = (c.cx + dx).round();
          final py = (c.cy + dy).round();
          if (px >= 0 && px < procW && py >= 0 && py < procH) {
            final lum = gray[py * procW + px];
            if (lum < minLum) {
              minLum = lum;
              bestX = px;
              bestY = py;
            }
          }
        }
      }
      final refinedCx = bestX.toDouble();
      final refinedCy = bestY.toDouble();

      // Sample core intensity inside the hollow
      double coreSum = 0;
      int coreCount = 0;
      final coreR = math.max(2, (c.radius * 0.25).round());
      for (int dy = -coreR; dy <= coreR; dy++) {
        for (int dx = -coreR; dx <= coreR; dx++) {
          final px = (refinedCx + dx).round();
          final py = (refinedCy + dy).round();
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
          final x1 = (refinedCx + (r - 2) * cosA).round();
          final y1 = (refinedCy + (r - 2) * sinA).round();
          final x2 = (refinedCx + (r + 2) * cosA).round();
          final y2 = (refinedCy + (r + 2) * sinA).round();

          if (x1 < 0 || x1 >= procW || y1 < 0 || y1 >= procH || x2 < 0 || x2 >= procW || y2 < 0 || y2 >= procH) {
            continue;
          }

          final lum1 = gray[y1 * procW + x1];
          final lum2 = gray[y2 * procW + x2];
          final grad = (lum2 - lum1).abs().toDouble(); // Adaptive: handles both dark hollows and bright pipes

          if (grad > maxGrad) {
            maxGrad = grad;
            bestR = r;
            bestRimLum = lum2.toDouble();
          }
        }

        if (maxGrad >= 4.0 && bestR >= scaledMinR * 0.60 && bestR <= scaledMaxR * 1.35) {
          quadrantRays[quad]++;
          boundaryPoints.add(math.Point(refinedCx + bestR * cosA, refinedCy + bestR * sinA));
          rayAngles.add(angle);
          rayRadii.add(bestR);
          rimLumSum += bestRimLum;
        }
      }

      // Enclosure check: boundary must exist in at least 2 of 4 quadrants, with >= 8 points
      final quadsWithEdges = quadrantRays.where((count) => count >= 1).length;
      if (quadsWithEdges < 2 || boundaryPoints.length < 8) {
        continue;
      }

      // Angular gap check: allow up to 160 degrees for touching pipes
      rayAngles.sort();
      double maxAngularGap = (rayAngles.first + 2.0 * math.pi) - rayAngles.last;
      for (int i = 0; i < rayAngles.length - 1; i++) {
        final gap = rayAngles[i + 1] - rayAngles[i];
        if (gap > maxAngularGap) maxAngularGap = gap;
      }
      if (maxAngularGap > (160.0 * math.pi / 180.0)) {
        continue;
      }

      // Radial consistency check
      final meanR = rayRadii.reduce((a, b) => a + b) / rayRadii.length;
      double varSum = 0;
      for (final r in rayRadii) {
        varSum += (r - meanR) * (r - meanR);
      }
      final stdR = math.sqrt(varSum / rayRadii.length);
      final radialCV = stdR / meanR;
      if (radialCV > 0.45) {
        continue;
      }

      // Fit ellipse to boundary points
      final fitted = EllipseFitService.fit(boundaryPoints);
      if (fitted == null || !fitted.isValid) {
        continue;
      }

      // Aspect ratio sanity check
      final major = math.max(fitted.width, fitted.height);
      final minor = math.min(fitted.width, fitted.height);
      if (minor <= 0 || (major / minor) > 2.2) {
        continue;
      }

      // Solidity check
      final solidity = GeometryUtils.calculateSolidity(boundaryPoints);
      if (solidity < solidityThreshold * 0.85) {
        continue;
      }

      // Scale coordinates back to original image space
      final origCx = fitted.cx * scaleFactor;
      final origCy = fitted.cy * scaleFactor;
      final origW = fitted.width * scaleFactor;
      final origH = fitted.height * scaleFactor;
      final origArea = math.pi * (origW / 2.0) * (origH / 2.0);

      final avgRim = rimLumSum / boundaryPoints.length;
      final contrast = (avgRim - coreAvg).abs();

      validatedPipes.add(_CandidateHollow(
        pipe: PipeDetection(
          id: 0,
          cx: origCx,
          cy: origCy,
          width: origW,
          height: origH,
          angle: fitted.angle,
          area: origArea,
          confidence: (contrast / 40.0).clamp(0.4, 1.0),
          solidity: solidity,
          isSelected: true,
          isManual: false,
        ),
        contrast: contrast,
        pointsCount: boundaryPoints.length,
      ));
    }

    // If ray profiler eliminated all candidates, populate directly from Hough circles
    if (validatedPipes.isEmpty) {
      for (final c in houghCircles) {
        _addHoughFallback(validatedPipes, c, scaleFactor);
      }
    }

    // 6. Physical Non-Maximum Suppression
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

        if (dist < avgR * 0.85) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        deduplicated.add(p);
      }
    }

    // 7. Median-based outlier rejection
    var finalSurviving = deduplicated;
    if (finalSurviving.length >= 4) {
      final sortedAreas = finalSurviving.map((p) => p.area).toList()..sort();
      final medianArea = sortedAreas[sortedAreas.length ~/ 2];
      final minAllowedArea = medianArea * outlierFraction;
      finalSurviving = finalSurviving.where((p) => p.area >= minAllowedArea).toList();
    }

    // Sort pipes geometrically (top-to-bottom, left-to-right) for clean sequential IDs
    finalSurviving.sort((a, b) {
      final yDiff = a.cy - b.cy;
      if (yDiff.abs() > 30 * scaleFactor) {
        return yDiff.compareTo(0);
      }
      return a.cx.compareTo(b.cx);
    });

    // 8. 3-Tier Sizing Classification: Green (Small), Yellow (Medium), Red (Large)
    final sortedAreas = finalSurviving.map((p) => p.area).toList()..sort();
    double effectiveThreshold = initialThreshold ?? 0.0;

    if (finalSurviving.isNotEmpty && (initialThreshold == null || initialThreshold <= 0)) {
      effectiveThreshold = sortedAreas[sortedAreas.length ~/ 2];
    }

    double p33 = 0.0;
    double p66 = 0.0;
    bool hasMultiSizes = false;

    if (sortedAreas.length >= 6) {
      final minA = sortedAreas.first;
      final maxA = sortedAreas.last;
      if (maxA > minA * 1.5) {
        // Clear multi-size stack
        hasMultiSizes = true;
        p33 = sortedAreas[sortedAreas.length ~/ 3];
        p66 = sortedAreas[(sortedAreas.length * 2) ~/ 3];
      }
    }

    // 9. Assign sequential IDs and category
    final finalPipes = <PipeDetection>[];
    for (int i = 0; i < finalSurviving.length; i++) {
      final p = finalSurviving[i];
      PipeCategory cat;
      if (hasMultiSizes) {
        if (p.area < p33) {
          cat = PipeCategory.small; // Green
        } else if (p.area < p66) {
          cat = PipeCategory.medium; // Yellow
        } else {
          cat = PipeCategory.large; // Red
        }
      } else {
        // Uniform stack: default to Small (Green), or split by threshold if custom
        if (initialThreshold != null && initialThreshold > 0) {
          cat = p.area < initialThreshold ? PipeCategory.small : PipeCategory.large;
        } else {
          cat = PipeCategory.small; // Default Green for uniform pipes
        }
      }
      finalPipes.add(p.copyWith(id: i + 1, category: cat, isSelected: true, isManual: false));
    }

    stopwatch.stop();

    return DetectionResult(
      pipes: finalPipes,
      imageWidth: origW,
      imageHeight: origH,
      processingTime: stopwatch.elapsed,
      engineName: 'Engine A (Classical CV: Adaptive Hough & Radial Profiler)',
      currentThreshold: effectiveThreshold,
    );
  }

  static void _addHoughFallback(List<_CandidateHollow> list, HoughCircle c, double scaleFactor) {
    final diam = c.radius * 2.0 * scaleFactor;
    final r = c.radius * scaleFactor;
    list.add(_CandidateHollow(
      pipe: PipeDetection(
        id: 0,
        cx: c.cx * scaleFactor,
        cy: c.cy * scaleFactor,
        width: diam,
        height: diam,
        angle: 0.0,
        area: math.pi * r * r,
        confidence: 0.70,
        solidity: 0.95,
        isSelected: true,
        isManual: false,
      ),
      contrast: 15.0,
      pointsCount: 16,
    ));
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
