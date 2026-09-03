import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/pipe_detection.dart';
import 'contour_tracer.dart';
import 'ellipse_fit.dart';
import 'geometry_utils.dart';
import 'image_filters.dart';

class TFLiteDetector {
  Interpreter? _interpreter;
  String? _loadedModelPath;

  bool get isModelLoaded => _interpreter != null;
  String? get loadedModelPath => _loadedModelPath;

  Future<void> loadModel(String modelPath) async {
    final file = File(modelPath);
    if (!file.existsSync()) {
      throw Exception('Model file does not exist at: $modelPath');
    }

    try {
      _interpreter?.close();
      _interpreter = Interpreter.fromFile(file);
      _loadedModelPath = modelPath;
    } catch (e) {
      throw Exception('Failed to initialize TFLite interpreter: $e. Ensure the model is a valid 32-bit float or 8-bit quantized TFLite network.');
    }
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _loadedModelPath = null;
  }

  /// Runs inference with bounding-box extraction + ellipse-fitting + solidity refinement
  Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double confidenceThreshold = 0.50,
    double solidityThreshold = 0.85,
    double? initialThreshold,
  }) async {
    if (_interpreter == null) {
      throw Exception(
        'No custom TFLite model loaded. Go to Settings to import your fine-tuned pipe model (.tflite), or switch to Engine A (Classical CV).',
      );
    }

    final stopwatch = Stopwatch()..start();

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image file.');
    }

    final origW = decoded.width;
    final origH = decoded.height;

    // Standard YOLO input size (default 640x640)
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final inH = inputShape.length >= 3 ? inputShape[1] : 640;
    final inW = inputShape.length >= 3 ? inputShape[2] : 640;

    final resized = img.copyResize(decoded, width: inW, height: inH);

    final input = List.generate(
      1,
      (_) => List.generate(
        inH,
        (y) => List.generate(
          inW,
          (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          },
        ),
      ),
    );

    final outputTensor = _interpreter!.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    final output = List.filled(
      outputShape.reduce((a, b) => a * b),
      0.0,
    ).reshape(outputShape);

    _interpreter!.run(input, output);

    final rawBoxes = <_RawBox>[];
    _parseYOLOOutput(output, outputShape, confidenceThreshold, rawBoxes);

    final candidatePipes = <PipeDetection>[];
    int pipeId = 1;

    for (final box in rawBoxes) {
      final boxX1 = (box.x1 * origW).clamp(0, origW - 1).toInt();
      final boxY1 = (box.y1 * origH).clamp(0, origH - 1).toInt();
      final boxX2 = (box.x2 * origW).clamp(0, origW - 1).toInt();
      final boxY2 = (box.y2 * origH).clamp(0, origH - 1).toInt();

      final boxW = boxX2 - boxX1;
      final boxH = boxY2 - boxY1;

      if (boxW < 6 || boxH < 6) continue;

      final crop = img.copyCrop(decoded, x: boxX1, y: boxY1, width: boxW, height: boxH);
      final refResult = _fitEllipseInsideCrop(crop, boxX1.toDouble(), boxY1.toDouble());

      if (refResult != null) {
        // Solidity filter: reject concave gaps
        if (refResult.solidity < solidityThreshold) {
          continue;
        }

        candidatePipes.add(PipeDetection(
          id: pipeId++,
          cx: refResult.ellipse.cx,
          cy: refResult.ellipse.cy,
          width: refResult.ellipse.width,
          height: refResult.ellipse.height,
          angle: refResult.ellipse.angle,
          area: refResult.ellipse.area,
          confidence: box.confidence,
          solidity: refResult.solidity,
        ));
      } else {
        final cx = boxX1 + boxW / 2.0;
        final cy = boxY1 + boxH / 2.0;
        final area = math.pi * (boxW / 2.0) * (boxH / 2.0);
        candidatePipes.add(PipeDetection(
          id: pipeId++,
          cx: cx,
          cy: cy,
          width: boxW.toDouble(),
          height: boxH.toDouble(),
          angle: 0.0,
          area: area,
          confidence: box.confidence,
          solidity: 0.95,
        ));
      }
    }

    double effectiveThreshold = initialThreshold ?? 0.0;
    if (candidatePipes.isNotEmpty && (initialThreshold == null || initialThreshold <= 0)) {
      final sortedAreas = candidatePipes.map((p) => p.area).toList()..sort();
      effectiveThreshold = sortedAreas[sortedAreas.length ~/ 2];
    }

    final categorized = candidatePipes.map((p) {
      final cat = p.area < effectiveThreshold ? PipeCategory.small : PipeCategory.large;
      return p.copyWith(category: cat);
    }).toList();

    stopwatch.stop();

    return DetectionResult(
      pipes: categorized,
      imageWidth: origW,
      imageHeight: origH,
      processingTime: stopwatch.elapsed,
      engineName: 'Engine B (Custom ML: ${_loadedModelPath?.split(Platform.pathSeparator).last ?? 'TFLite'})',
      currentThreshold: effectiveThreshold,
    );
  }

  _RefinedCropResult? _fitEllipseInsideCrop(img.Image crop, double offsetX, double offsetY) {
    try {
      final gray = ImageFilters.toGrayscale(crop);
      final clahe = ImageFilters.applyCLAHE(gray, crop.width, crop.height, gridTilesX: 4, gridTilesY: 4);
      final blurred = ImageFilters.applyMedianBlur(clahe, crop.width, crop.height);
      final edges = ImageFilters.applyCanny(blurred, crop.width, crop.height, sensitivity: 0.50);
      final closed = ImageFilters.applyDilation(edges, crop.width, crop.height);
      final contours = ContourTracer.extractContours(closed, crop.width, crop.height, minPoints: 8);

      if (contours.isEmpty) return null;

      contours.sort((a, b) => b.points.length.compareTo(a.points.length));
      final bestContour = contours.first;

      final solidity = GeometryUtils.calculateSolidity(bestContour.points);
      final fitted = EllipseFitService.fit(bestContour.points);
      if (fitted == null || !fitted.isValid) return null;

      return _RefinedCropResult(
        ellipse: FittedEllipse(
          cx: fitted.cx + offsetX,
          cy: fitted.cy + offsetY,
          width: fitted.width,
          height: fitted.height,
          angle: fitted.angle,
          area: fitted.area,
        ),
        solidity: solidity,
      );
    } catch (_) {
      return null;
    }
  }

  void _parseYOLOOutput(
    dynamic output,
    List<int> shape,
    double confThreshold,
    List<_RawBox> outBoxes,
  ) {
    if (shape.length == 3) {
      if (shape[1] == 5 || shape[1] == 6) {
        final numBoxes = shape[2];
        for (int i = 0; i < numBoxes; i++) {
          final conf = (output[0][4][i] as num).toDouble();
          if (conf >= confThreshold) {
            final cx = (output[0][0][i] as num).toDouble();
            final cy = (output[0][1][i] as num).toDouble();
            final w = (output[0][2][i] as num).toDouble();
            final h = (output[0][3][i] as num).toDouble();
            outBoxes.add(_RawBox(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, conf));
          }
        }
      } else if (shape[2] == 5 || shape[2] == 6) {
        final numBoxes = shape[1];
        for (int i = 0; i < numBoxes; i++) {
          final conf = (output[0][i][4] as num).toDouble();
          if (conf >= confThreshold) {
            final cx = (output[0][i][0] as num).toDouble();
            final cy = (output[0][i][1] as num).toDouble();
            final w = (output[0][i][2] as num).toDouble();
            final h = (output[0][i][3] as num).toDouble();
            outBoxes.add(_RawBox(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, conf));
          }
        }
      }
    }
  }
}

class _RefinedCropResult {
  final FittedEllipse ellipse;
  final double solidity;
  const _RefinedCropResult({required this.ellipse, required this.solidity});
}

class _RawBox {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
  const _RawBox(this.x1, this.y1, this.x2, this.y2, this.confidence);
}
