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

class _ImageCanvasWidgetState extends ConsumerState<ImageCanvasWidget> with TickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  late final AnimationController _scanAnimController;
  late final AnimationController _progressAnimController;
  bool _showProgressCard = false;

  // Normalized crop rectangle: 0.0 to 1.0 in image coordinates
  Rect _cropBoxNorm = const Rect.fromLTWH(0.08, 0.08, 0.84, 0.84);
  int? _activeCropHandle; // 0..3: corners, 4..7: edges, 8: center drag

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _progressAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  String _getDynamicStageText(int pct) {
    if (pct >= 100) return 'Detection Complete!';
    if (pct >= 85) return 'Eliminating duplicates & nested classification ($pct%)...';
    if (pct >= 60) return 'Fitting pipe rims & concentric hollows ($pct%)...';
    if (pct >= 35) return 'Scanning pipe centers & Hough accumulator ($pct%)...';
    if (pct >= 12) return 'Detecting pipe edges & gradient field ($pct%)...';
    return 'Calibrating contrast & dynamic range ($pct%)...';
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
                      'Pipe #${pipe.id} ${pipe.isNested ? "(Nested Inside #${pipe.nestedInId})" : (pipe.isManual ? "(Manual)" : "(AI Detected)")}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
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
    ref.listen<bool>(
      detectionProvider.select((s) => s.isProcessing),
      (prev, isProcessing) {
        if (isProcessing) {
          setState(() {
            _showProgressCard = true;
          });
          _progressAnimController.reset();
          _progressAnimController.animateTo(
            0.95,
            duration: const Duration(milliseconds: 2200),
            curve: Curves.easeOutCubic,
          );
        } else if (prev == true && !isProcessing) {
          _progressAnimController.animateTo(
            1.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          ).then((_) async {
            await Future.delayed(const Duration(milliseconds: 400));
            if (mounted) {
              setState(() {
                _showProgressCard = false;
              });
            }
          });
        }
      },
    );

    final state = ref.watch(detectionProvider);
    final notifier = ref.read(detectionProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;

        final scaleX = canvasW / widget.imageWidth;
        final scaleY = canvasH / widget.imageHeight;
        final scale = math.min(scaleX, scaleY);

        final renderedW = widget.imageWidth * scale;
        final renderedH = widget.imageHeight * scale;

        final isPanMode = state.selectedTool == CanvasTool.pan;
        final isCropMode = state.selectedTool == CanvasTool.crop;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Dark viewport background
            Container(color: const Color(0xFF111318)),

            // Interactive viewer for pinch zoom and pan
            InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.5,
              maxScale: 10.0,
              panEnabled: isPanMode,
              scaleEnabled: !isCropMode,
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

                      // Ellipse & dot overlay
                      CustomPaint(
                        painter: PipeOverlayPainter(
                          imageWidth: widget.imageWidth,
                          imageHeight: widget.imageHeight,
                          detections: widget.detections,
                          scale: scale,
                          showLabels: state.showNumbers,
                        ),
                      ),

                      // Crop Viewport Overlay when Crop Tool is active
                      if (isCropMode)
                        CustomPaint(
                          painter: CropOverlayPainter(
                            cropNorm: _cropBoxNorm,
                            renderedSize: Size(renderedW, renderedH),
                          ),
                        ),

                      // Gesture overlay for manual interactions
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: isCropMode
                              ? (details) {
                                  _onCropPanStart(details.localPosition, renderedW, renderedH);
                                }
                              : null,
                          onPanUpdate: isCropMode
                              ? (details) {
                                  _onCropPanUpdate(details.localPosition, renderedW, renderedH);
                                }
                              : null,
                          onPanEnd: isCropMode
                              ? (_) {
                                  _activeCropHandle = null;
                                }
                              : null,
                          onTapUp: (details) {
                            if (!state.isProcessing && !isCropMode) {
                              _handleImageTap(details.localPosition, scale);
                            }
                          },
                          onLongPressStart: (details) {
                            if (!state.isProcessing && !isCropMode) {
                              _handlePipeLongPress(details.localPosition, scale);
                            }
                          },
                        ),
                      ),

                      // Real-time laser scanning line
                      if (_showProgressCard)
                        AnimatedBuilder(
                          animation: _progressAnimController,
                          builder: (context, child) {
                            return Positioned(
                              top: _progressAnimController.value * renderedH,
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

            // Progress card in center
            if (_showProgressCard)
              AnimatedBuilder(
                animation: _progressAnimController,
                builder: (context, child) {
                  final pct = (_progressAnimController.value * 100).clamp(0, 100).toInt();
                  final isDone = pct >= 100;
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        color: const Color(0xEE1E222A),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: (isDone ? Colors.greenAccent : Colors.cyanAccent).withValues(alpha: 0.7),
                          width: 1.5,
                        ),
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
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: isDone
                                    ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22)
                                    : const CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation(Colors.cyanAccent),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isDone ? 'AI Counting Pipes: Complete (100%)' : 'AI Counting Pipes ($pct%)',
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _progressAnimController.value,
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation(
                                isDone ? Colors.greenAccent : Colors.cyanAccent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getDynamicStageText(pct),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            // Top Toolbar: Modern Frosted Glass Pill
            Positioned(
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xEE1A1E26),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
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
                      tool: CanvasTool.crop,
                      currentTool: state.selectedTool,
                      icon: Icons.crop,
                      label: 'Crop ROI',
                      onPressed: () => notifier.setSelectedTool(CanvasTool.crop),
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
                top: 64,
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

            // Crop Action Floating Bar when Crop Tool is active
            if (isCropMode)
              Positioned(
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFA1E222A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 18, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () {
                          final imgRect = Rect.fromLTWH(
                            _cropBoxNorm.left * widget.imageWidth,
                            _cropBoxNorm.top * widget.imageHeight,
                            _cropBoxNorm.width * widget.imageWidth,
                            _cropBoxNorm.height * widget.imageHeight,
                          );
                          notifier.applyCrop(imgRect);
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Apply Crop', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      if (state.isCropped) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          onPressed: () => notifier.resetCrop(),
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('Reset Full'),
                        ),
                      ],
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        onPressed: () => notifier.setSelectedTool(CanvasTool.pan),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),

            // Mode hint indicator banner
            if (!isCropMode && state.selectedTool != CanvasTool.pan && !state.isProcessing)
              Positioned(
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

  void _onCropPanStart(Offset pos, double w, double h) {
    final normX = (pos.dx / w).clamp(0.0, 1.0);
    final normY = (pos.dy / h).clamp(0.0, 1.0);

    const hitDist = 0.06;
    final l = _cropBoxNorm.left;
    final r = _cropBoxNorm.right;
    final t = _cropBoxNorm.top;
    final b = _cropBoxNorm.bottom;

    if ((normX - l).abs() < hitDist && (normY - t).abs() < hitDist) {
      _activeCropHandle = 0; // Top-left
    } else if ((normX - r).abs() < hitDist && (normY - t).abs() < hitDist) {
      _activeCropHandle = 1; // Top-right
    } else if ((normX - r).abs() < hitDist && (normY - b).abs() < hitDist) {
      _activeCropHandle = 2; // Bottom-right
    } else if ((normX - l).abs() < hitDist && (normY - b).abs() < hitDist) {
      _activeCropHandle = 3; // Bottom-left
    } else if (_cropBoxNorm.contains(Offset(normX, normY))) {
      _activeCropHandle = 8; // Center drag
    } else {
      _activeCropHandle = null;
    }
  }

  void _onCropPanUpdate(Offset pos, double w, double h) {
    if (_activeCropHandle == null) return;
    final normX = (pos.dx / w).clamp(0.0, 1.0);
    final normY = (pos.dy / h).clamp(0.0, 1.0);

    setState(() {
      double l = _cropBoxNorm.left;
      double r = _cropBoxNorm.right;
      double t = _cropBoxNorm.top;
      double b = _cropBoxNorm.bottom;

      switch (_activeCropHandle) {
        case 0: // Top-left
          l = math.min(normX, r - 0.05);
          t = math.min(normY, b - 0.05);
          break;
        case 1: // Top-right
          r = math.max(normX, l + 0.05);
          t = math.min(normY, b - 0.05);
          break;
        case 2: // Bottom-right
          r = math.max(normX, l + 0.05);
          b = math.max(normY, t + 0.05);
          break;
        case 3: // Bottom-left
          l = math.min(normX, r - 0.05);
          b = math.max(normY, t + 0.05);
          break;
        case 8: // Center drag
          final boxW = _cropBoxNorm.width;
          final boxH = _cropBoxNorm.height;
          l = (normX - boxW / 2).clamp(0.0, 1.0 - boxW);
          t = (normY - boxH / 2).clamp(0.0, 1.0 - boxH);
          r = l + boxW;
          b = t + boxH;
          break;
      }
      _cropBoxNorm = Rect.fromLTRB(l, t, r, b);
    });
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

class CropOverlayPainter extends CustomPainter {
  final Rect cropNorm;
  final Size renderedSize;

  CropOverlayPainter({required this.cropNorm, required this.renderedSize});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      cropNorm.left * renderedSize.width,
      cropNorm.top * renderedSize.height,
      cropNorm.right * renderedSize.width,
      cropNorm.bottom * renderedSize.height,
    );

    // Dim area outside the crop rectangle
    final darkPaint = Paint()..color = const Color(0xB3000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, renderedSize.width, renderedSize.height))
      ..addRect(rect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, darkPaint);

    // Bounding border
    final borderPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, borderPaint);

    // 4 Corner handles
    final handlePaint = Paint()..color = const Color(0xFF38BDF8);
    final handleRadius = 6.0;
    canvas.drawCircle(rect.topLeft, handleRadius, handlePaint);
    canvas.drawCircle(rect.topRight, handleRadius, handlePaint);
    canvas.drawCircle(rect.bottomLeft, handleRadius, handlePaint);
    canvas.drawCircle(rect.bottomRight, handleRadius, handlePaint);

    // Handle borders
    final handleBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(rect.topLeft, handleRadius, handleBorder);
    canvas.drawCircle(rect.topRight, handleRadius, handleBorder);
    canvas.drawCircle(rect.bottomLeft, handleRadius, handleBorder);
    canvas.drawCircle(rect.bottomRight, handleRadius, handleBorder);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) {
    return oldDelegate.cropNorm != cropNorm || oldDelegate.renderedSize != renderedSize;
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
        if (pipe.isNested) {
          // Nested Pipe: Draw distinct double ring with glowing cyan accent to highlight inside status
          final nestedOuterPaint = Paint()
            ..color = baseColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, 1.4 * scale).clamp(1.2, 2.0)
            ..isAntiAlias = true;
          canvas.drawOval(ellipseRect, nestedOuterPaint);

          final innerGlow = Paint()
            ..color = const Color(0xFF38BDF8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          canvas.drawOval(ellipseRect.deflate(2.0), innerGlow);

          canvas.drawCircle(Offset.zero, 2.2, Paint()..color = const Color(0xFF38BDF8));
        } else {
          // Standard pipe ring
          final outlinePaint = Paint()
            ..color = baseColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, 1.2 * scale).clamp(1.0, 1.6)
            ..isAntiAlias = true;

          canvas.drawOval(ellipseRect, outlinePaint);
          canvas.drawCircle(Offset.zero, 1.8, Paint()..color = baseColor);
        }
      } else {
        // Excluded pipe
        final excludedPaint = Paint()
          ..color = Colors.grey.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true;

        canvas.drawOval(ellipseRect, excludedPaint);

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
        final labelText = pipe.isNested ? '#${pipe.id} (in #${pipe.nestedInId})' : '#${pipe.id}';
        final textPainter = TextPainter(
          text: TextSpan(
            text: labelText,
            style: TextStyle(
              color: pipe.isNested ? const Color(0xFF38BDF8) : Colors.white,
              fontSize: math.max(9.0, 11.0 * scale).clamp(9.0, 13.0),
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
          Paint()..color = Colors.black.withValues(alpha: 0.8),
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
