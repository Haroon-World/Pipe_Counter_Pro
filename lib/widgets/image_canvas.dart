import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pipe_detection.dart';
import '../providers/detection_provider.dart';

class ImageCanvasWidget extends ConsumerStatefulWidget {
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
    this.showLabels = false,
  });

  @override
  ConsumerState<ImageCanvasWidget> createState() => _ImageCanvasWidgetState();
}

class _ImageCanvasWidgetState extends ConsumerState<ImageCanvasWidget> with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  late final AnimationController _scanAnimController;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _handleImageTap(Offset localPos, double scale) {
    final state = ref.read(detectionProvider);
    final notifier = ref.read(detectionProvider.notifier);

    final imageX = localPos.dx / scale;
    final imageY = localPos.dy / scale;

    if (state.selectedTool == CanvasTool.add) {
      notifier.addManualPipe(imageX, imageY);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added pipe #${(state.result?.pipes.length ?? 0) + 1} (${state.activeAddCategory.displayName})'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (state.selectedTool == CanvasTool.delete) {
      final target = _findNearestPipe(imageX, imageY);
      if (target != null) {
        notifier.deletePipe(target.id);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted pipe #${target.id}'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (state.selectedTool == CanvasTool.select) {
      final target = _findNearestPipe(imageX, imageY);
      if (target != null) {
        notifier.togglePipeSelected(target.id);
        final statusStr = target.isSelected ? 'excluded' : 'counted';
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pipe #${target.id} is now $statusStr'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handlePipeLongPress(Offset localPos, double scale) {
    final imageX = localPos.dx / scale;
    final imageY = localPos.dy / scale;
    final target = _findNearestPipe(imageX, imageY);
    if (target != null) {
      _showPipeOptionsSheet(target);
    }
  }

  PipeDetection? _findNearestPipe(double imageX, double imageY) {
    if (widget.detections.isEmpty) return null;

    PipeDetection? bestPipe;
    double bestDist = double.infinity;

    for (final p in widget.detections) {
      final dx = p.cx - imageX;
      final dy = p.cy - imageY;
      final dist = math.sqrt(dx * dx + dy * dy);
      final hitRadius = math.max(p.averageRadius * 1.35, 24.0);

      if (dist <= hitRadius && dist < bestDist) {
        bestDist = dist;
        bestPipe = p;
      }
    }

    return bestPipe;
  }

  void _showPipeOptionsSheet(PipeDetection pipe) {
    final notifier = ref.read(detectionProvider.notifier);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Pipe #${pipe.id} (${pipe.isManual ? "Manual" : "AI Detected"})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text(
                  'Diameter: ${pipe.diameter.toStringAsFixed(1)} px • Status: ${pipe.isSelected ? "Counted" : "Excluded"}',
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Change Color / Size Tier:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildColorOption(ctx, notifier, pipe, PipeCategory.small, '🟢 Small', const Color(0xFF22C55E)),
                    const SizedBox(width: 8),
                    _buildColorOption(ctx, notifier, pipe, PipeCategory.medium, '🟡 Medium', const Color(0xFFEAB308)),
                    const SizedBox(width: 8),
                    _buildColorOption(ctx, notifier, pipe, PipeCategory.large, '🔴 Large', const Color(0xFFEF4444)),
                  ],
                ),
                const Divider(height: 28, color: Colors.white24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                        ),
                        onPressed: () {
                          notifier.togglePipeSelected(pipe.id);
                          Navigator.pop(ctx);
                        },
                        icon: Icon(pipe.isSelected ? Icons.cancel_outlined : Icons.check_circle_outline),
                        label: Text(pipe.isSelected ? 'Exclude Pipe' : 'Count Pipe'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                        onPressed: () {
                          notifier.deletePipe(pipe.id);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorOption(
    BuildContext ctx,
    DetectionNotifier notifier,
    PipeDetection pipe,
    PipeCategory cat,
    String label,
    Color color,
  ) {
    final isSelected = pipe.category == cat;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          notifier.recolorPipe(pipe.id, cat);
          Navigator.pop(ctx);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.25) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(detectionProvider);
    final notifier = ref.read(detectionProvider.notifier);

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

        final isPanMode = state.selectedTool == CanvasTool.pan;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Dark viewport background
            Container(color: const Color(0xFF141416)),

            // Interactive viewer for pinch zoom and pan
            InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.5,
              maxScale: 10.0,
              panEnabled: isPanMode,
              scaleEnabled: true,
              boundaryMargin: const EdgeInsets.all(300),
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

                      // Ellipse & dot overlay (shows numbers ONLY if state.showNumbers is true)
                      CustomPaint(
                        painter: PipeOverlayPainter(
                          imageWidth: widget.imageWidth,
                          imageHeight: widget.imageHeight,
                          detections: widget.detections,
                          scale: scale,
                          showLabels: state.showNumbers,
                        ),
                      ),

                      // Gesture overlay for manual pipe interaction
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            if (!state.isProcessing) {
                              _handleImageTap(details.localPosition, scale);
                            }
                          },
                          onLongPressStart: (details) {
                            if (!state.isProcessing) {
                              _handlePipeLongPress(details.localPosition, scale);
                            }
                          },
                        ),
                      ),

                      // Scanning laser beam during detection
                      if (state.isProcessing)
                        AnimatedBuilder(
                          animation: _scanAnimController,
                          builder: (context, child) {
                            return Positioned(
                              top: _scanAnimController.value * renderedH,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.cyanAccent.withValues(alpha: 0.0),
                                      Colors.cyanAccent,
                                      Colors.cyanAccent.withValues(alpha: 0.0),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.cyanAccent.withValues(alpha: 0.8),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Scanning progress overlay card in center
            if (state.isProcessing)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E222A),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.6), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.cyanAccent),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'AI Counting Pipes (${(state.detectionProgress * 100).toInt()}%)',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: state.detectionProgress > 0 ? state.detectionProgress : null,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.detectionStage.isNotEmpty ? state.detectionStage : 'Analyzing pipe contours...',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            // Top Toolbar: Interactive Editing Mode Selector (matching desktop navbar pill)
            Positioned(
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xEE1E222A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 3)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToolButton(
                      tool: CanvasTool.pan,
                      currentTool: state.selectedTool,
                      icon: Icons.pan_tool_outlined,
                      label: 'Pan',
                      onPressed: () => notifier.setSelectedTool(CanvasTool.pan),
                    ),
                    _buildToolButton(
                      tool: CanvasTool.add,
                      currentTool: state.selectedTool,
                      icon: Icons.add_circle_outline,
                      label: 'Add',
                      badgeColor: state.activeAddCategory == PipeCategory.small
                          ? const Color(0xFF22C55E)
                          : (state.activeAddCategory == PipeCategory.medium ? const Color(0xFFEAB308) : const Color(0xFFEF4444)),
                      onPressed: () => notifier.setSelectedTool(CanvasTool.add),
                    ),
                    _buildToolButton(
                      tool: CanvasTool.delete,
                      currentTool: state.selectedTool,
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      onPressed: () => notifier.setSelectedTool(CanvasTool.delete),
                    ),
                    _buildToolButton(
                      tool: CanvasTool.select,
                      currentTool: state.selectedTool,
                      icon: Icons.touch_app_outlined,
                      label: 'Toggle',
                      onPressed: () => notifier.setSelectedTool(CanvasTool.select),
                    ),
                    // Toggle Numbers Button (Default OFF so pipes are 100% visible)
                    Container(width: 1, height: 20, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
                    InkWell(
                      onTap: () => notifier.toggleShowNumbers(),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: state.showNumbers ? Colors.cyanAccent.withValues(alpha: 0.25) : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.pin_outlined,
                              size: 14,
                              color: state.showNumbers ? Colors.cyanAccent : Colors.white60,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              state.showNumbers ? '# ON' : '# OFF',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: state.showNumbers ? FontWeight.bold : FontWeight.normal,
                                color: state.showNumbers ? Colors.cyanAccent : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (state.canUndo) ...[
                      Container(width: 1, height: 20, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
                      IconButton(
                        icon: const Icon(Icons.undo, color: Colors.white, size: 18),
                        tooltip: 'Undo Last Action',
                        onPressed: () => notifier.undo(),
                        constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Secondary Floating Bar when in "Add Pipe" Mode: Color & Radius Adjuster
            if (state.selectedTool == CanvasTool.add)
              Positioned(
                top: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E222A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAddColorChip(notifier, state.activeAddCategory, PipeCategory.small, '🟢 Small', const Color(0xFF22C55E)),
                      const SizedBox(width: 6),
                      _buildAddColorChip(notifier, state.activeAddCategory, PipeCategory.medium, '🟡 Med', const Color(0xFFEAB308)),
                      const SizedBox(width: 6),
                      _buildAddColorChip(notifier, state.activeAddCategory, PipeCategory.large, '🔴 Large', const Color(0xFFEF4444)),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 18, color: Colors.white24),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          notifier.setManualAddRadius(state.manualAddRadius - 5);
                        },
                        child: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 18),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '${state.manualAddRadius.toInt()}px',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          notifier.setManualAddRadius(state.manualAddRadius + 5);
                        },
                        child: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

            // Mode hint indicator banner
            if (state.selectedTool != CanvasTool.pan && !state.isProcessing)
              Positioned(
                bottom: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    state.selectedTool == CanvasTool.add
                        ? '👉 Tap anywhere on image to add a pipe circle'
                        : (state.selectedTool == CanvasTool.delete
                            ? '👉 Tap any pipe circle to delete it'
                            : '👉 Tap any pipe to toggle Active/Excluded'),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

            // Bottom-Right Zoom & Fit controls
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xDD1E222A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_out, color: Colors.white, size: 18),
                      tooltip: 'Zoom Out',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _transformController.value = _transformController.value.scaledByDouble(0.8, 0.8, 1.0, 1.0);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.fit_screen_outlined, color: Colors.white, size: 18),
                      tooltip: 'Fit View',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: _resetZoom,
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                      tooltip: 'Zoom In',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
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

  Widget _buildToolButton({
    required CanvasTool tool,
    required CanvasTool currentTool,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? badgeColor,
  }) {
    final isActive = tool == currentTool;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? const Color(0xFF38BDF8) : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
            if (badgeColor != null) ...[
              const SizedBox(width: 4),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddColorChip(
    DetectionNotifier notifier,
    PipeCategory activeCat,
    PipeCategory targetCat,
    String label,
    Color color,
  ) {
    final isSelected = activeCat == targetCat;
    return GestureDetector(
      onTap: () => notifier.setActiveAddCategory(targetCat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white24,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class PipeOverlayPainter extends CustomPainter {
  final int imageWidth;
  final int imageHeight;
  final List<PipeDetection> detections;
  final double scale;
  final bool showLabels; // When false: NO numbers are painted at all!

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

    for (final pipe in detections) {
      final renderCx = pipe.cx * scale;
      final renderCy = pipe.cy * scale;
      final renderW = pipe.width * scale;
      final renderH = pipe.height * scale;

      Color baseColor;
      switch (pipe.category) {
        case PipeCategory.small:
          baseColor = const Color(0xFF22C55E); // Green
          break;
        case PipeCategory.medium:
          baseColor = const Color(0xFFEAB308); // Yellow
          break;
        case PipeCategory.large:
          baseColor = const Color(0xFFEF4444); // Red
          break;
      }

      canvas.save();
      canvas.translate(renderCx, renderCy);
      final angleRad = pipe.angle * math.pi / 180.0;
      canvas.rotate(angleRad);

      final ellipseRect = Rect.fromCenter(
        center: Offset.zero,
        width: renderW,
        height: renderH,
      );

      if (pipe.isSelected) {
        // Active / Counted pipe: Clear, crisp circular outline with no obstructing numbers
        final fillPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill;

        final outlinePaint = Paint()
          ..color = baseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.8, 2.2 * scale).clamp(1.8, 4.0)
          ..isAntiAlias = true;

        canvas.drawOval(ellipseRect, fillPaint);
        canvas.drawOval(ellipseRect, outlinePaint);

        // Center dot with dark halo
        canvas.drawCircle(Offset.zero, 3.5, Paint()..color = Colors.black87);
        canvas.drawCircle(Offset.zero, 2.5, Paint()..color = baseColor);
      } else {
        // Excluded / Deselected pipe (Muted dashed outline with red X)
        final excludedPaint = Paint()
          ..color = Colors.grey.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..isAntiAlias = true;

        canvas.drawOval(ellipseRect, excludedPaint);

        // Draw small red 'X' in center
        final xPaint = Paint()
          ..color = const Color(0xFFEF4444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        const xSize = 5.0;
        canvas.drawLine(const Offset(-xSize, -xSize), const Offset(xSize, xSize), xPaint);
        canvas.drawLine(const Offset(-xSize, xSize), const Offset(xSize, -xSize), xPaint);
      }

      canvas.restore();

      // Draw Pipe ID Badge (#1, #2...) ONLY if showLabels is explicitly enabled
      if (showLabels && scale >= 0.20 && pipe.isSelected) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '#${pipe.id}',
            style: TextStyle(
              color: Colors.white,
              fontSize: math.max(9.0, 11.0 * scale).clamp(9.0, 14.0),
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
