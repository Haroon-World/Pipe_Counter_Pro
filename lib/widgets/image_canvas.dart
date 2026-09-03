import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pipe_detection.dart';

class ImageCanvasWidget extends StatefulWidget {
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final List<PipeDetection> detections;
  final bool showLabels;

  const ImageCanvasWidget({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
    this.showLabels = true,
  });

  @override
  State<ImageCanvasWidget> createState() => _ImageCanvasWidgetState();
}

class _ImageCanvasWidgetState extends State<ImageCanvasWidget> {
  final TransformationController _transformController = TransformationController();

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;

        // Calculate aspect-fit dimensions
        final scaleX = canvasW / widget.imageWidth;
        final scaleY = canvasH / widget.imageHeight;
        final scale = math.min(scaleX, scaleY);

        final renderedW = widget.imageWidth * scale;
        final renderedH = widget.imageHeight * scale;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Dark viewport background
            Container(
              color: const Color(0xFF141416),
            ),

            // Interactive viewer for pinch zoom and pan
            InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.5,
              maxScale: 8.0,
              boundaryMargin: const EdgeInsets.all(200),
              child: Center(
                child: SizedBox(
                  width: renderedW,
                  height: renderedH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base image
                      Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),

                      // Ellipse & dot overlay
                      CustomPaint(
                        painter: PipeOverlayPainter(
                          imageWidth: widget.imageWidth,
                          imageHeight: widget.imageHeight,
                          detections: widget.detections,
                          scale: scale,
                          showLabels: widget.showLabels,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Zoom helper controls
            Positioned(
              right: 16,
              bottom: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_out, color: Colors.white, size: 20),
                      tooltip: 'Zoom Out',
                      onPressed: () {
                        _transformController.value = _transformController.value.scaledByDouble(0.8, 0.8, 1.0, 1.0);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      tooltip: 'Reset Zoom & Fit',
                      onPressed: _resetZoom,
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
                      tooltip: 'Zoom In',
                      onPressed: () {
                        _transformController.value = _transformController.value.scaledByDouble(1.25, 1.25, 1.0, 1.0);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PipeOverlayPainter extends CustomPainter {
  final int imageWidth;
  final int imageHeight;
  final List<PipeDetection> detections;
  final double scale;
  final bool showLabels;

  PipeOverlayPainter({
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
    required this.scale,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final greenOutline = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, 2.5 * scale)
      ..isAntiAlias = true;

    final greenFill = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final redOutline = Paint()
      ..color = const Color(0xFFFF3333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, 2.5 * scale)
      ..isAntiAlias = true;

    final redFill = Paint()
      ..color = const Color(0xFFFF3333).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final haloPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final pipe in detections) {
      final isSmall = pipe.category == PipeCategory.small;
      final outlinePaint = isSmall ? greenOutline : redOutline;
      final fillPaint = isSmall ? greenFill : redFill;
      final dotColor = isSmall ? const Color(0xFF00E676) : const Color(0xFFFF3333);

      final renderCx = pipe.cx * scale;
      final renderCy = pipe.cy * scale;
      final renderW = pipe.width * scale;
      final renderH = pipe.height * scale;

      canvas.save();
      canvas.translate(renderCx, renderCy);
      final angleRad = pipe.angle * math.pi / 180.0;
      canvas.rotate(angleRad);

      final ellipseRect = Rect.fromCenter(
        center: Offset.zero,
        width: renderW,
        height: renderH,
      );

      // Draw fitted ellipse outline
      canvas.drawOval(ellipseRect, fillPaint);
      canvas.drawOval(ellipseRect, outlinePaint);

      canvas.restore();

      // Draw centered dot
      final dotRadius = math.max(4.0, math.min(renderW, renderH) * 0.08).clamp(4.0, 9.0);
      final center = Offset(renderCx, renderCy);

      canvas.drawCircle(center, dotRadius + 1.5, haloPaint);
      canvas.drawCircle(center, dotRadius, Paint()..color = dotColor);

      // Draw ID Badge
      if (showLabels && scale >= 0.25) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${pipe.id}',
            style: TextStyle(
              color: Colors.white,
              fontSize: math.max(9.0, 11.0 * scale).clamp(8.0, 15.0),
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(blurRadius: 2.0, color: Colors.black, offset: Offset(1, 1)),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelOffset = Offset(
          renderCx - (textPainter.width / 2),
          renderCy - renderH / 2 - textPainter.height - 3,
        );

        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelOffset.dx - 3,
            labelOffset.dy - 1,
            textPainter.width + 6,
            textPainter.height + 2,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(
          badgeRect,
          Paint()..color = Colors.black.withValues(alpha: 0.75),
        );

        textPainter.paint(canvas, labelOffset);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PipeOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.scale != scale ||
        oldDelegate.showLabels != showLabels;
  }
}


