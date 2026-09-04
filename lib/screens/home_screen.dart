import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../providers/detection_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/confidence_slider.dart';
import '../widgets/count_summary_card.dart';
import '../widgets/export_dialog.dart';
import '../widgets/image_canvas.dart';
import '../widgets/radius_range_slider.dart';
import '../widgets/threshold_slider.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detectionState = ref.watch(detectionProvider);
    final settings = ref.watch(settingsProvider);
    final detectionNotifier = ref.read(detectionProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final isMobile = !kIsWeb && (Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 32,
                height: 32,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.blur_circular, color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Pipe Counter Pro',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ActionChip(
              avatar: Icon(
                settings.engine == DetectionEngine.classicalCV ? Icons.auto_fix_high : Icons.model_training,
                size: 16,
              ),
              label: Text(
                settings.engine == DetectionEngine.classicalCV ? 'Engine A' : 'Engine B',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings & Engines',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;

          if (isWide) {
            // Desktop / Tablet Two-Column Layout
            return Row(
              children: [
                // Left 65%: Large Interactive Canvas
                Expanded(
                  flex: 65,
                  child: Container(
                    color: const Color(0xFF141416),
                    child: _buildCanvasArea(context, detectionState, detectionNotifier, isMobile),
                  ),
                ),
                // Right 35%: Controls Sidebar
                Container(
                  width: 390,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: _buildControlsPanel(
                    context,
                    ref,
                    detectionState,
                    settings,
                    detectionNotifier,
                    settingsNotifier,
                    isMobile,
                  ),
                ),
              ],
            );
          } else {
            // Mobile Vertical Layout
            return Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    color: const Color(0xFF141416),
                    child: _buildCanvasArea(context, detectionState, detectionNotifier, isMobile),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: _buildControlsPanel(
                    context,
                    ref,
                    detectionState,
                    settings,
                    detectionNotifier,
                    settingsNotifier,
                    isMobile,
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildCanvasArea(
    BuildContext context,
    DetectionState state,
    DetectionNotifier notifier,
    bool isMobile,
  ) {
    if (!state.hasImage) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_search_outlined,
                size: 72,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Image Loaded',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              const Text(
                'Upload a photo of stacked pipes or take one with your camera to begin counting.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (isMobile)
                    ElevatedButton.icon(
                      onPressed: () => notifier.capturePhotoFromCamera(),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: () => notifier.pickImageFromGallery(),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Upload Image / File'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ImageCanvasWidget(
      imageBytes: state.imageBytes!,
      imageWidth: state.imageWidth,
      imageHeight: state.imageHeight,
      detections: state.result?.pipes ?? const [],
      showLabels: state.showNumbers,
    );
  }

  Widget _buildControlsPanel(
    BuildContext context,
    WidgetRef ref,
    DetectionState detectionState,
    AppSettings settings,
    DetectionNotifier detectionNotifier,
    SettingsNotifier settingsNotifier,
    bool isMobile,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Action Buttons: Camera & Upload Image
        Row(
          children: [
            if (isMobile) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: detectionState.isProcessing ? null : () => detectionNotifier.capturePhotoFromCamera(),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: detectionState.isProcessing ? null : () => detectionNotifier.pickImageFromGallery(),
                icon: const Icon(Icons.file_upload, size: 18),
                label: const Text('Upload'),
              ),
            ),
            if (detectionState.hasImage) ...[
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Clear Image',
                onPressed: detectionState.isProcessing ? null : () => detectionNotifier.clearImage(),
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),

        // Run Detection Main CTA Button
        FilledButton.icon(
          onPressed: (!detectionState.hasImage || detectionState.isProcessing)
              ? null
              : () => detectionNotifier.runDetection(),
          icon: detectionState.isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.play_arrow_rounded, size: 22),
          label: Text(
            detectionState.isProcessing
                ? (detectionState.statusMessage ?? 'Detecting pipes...')
                : (detectionState.hasResults ? 'Re-run Detection' : 'Run Detection'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        if (detectionState.errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detectionState.errorMessage!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Hough Pipe Radius Range Slider with Auto-Estimate
        RadiusRangeSlider(
          minRadius: settings.minRadius,
          maxRadius: settings.maxRadius,
          hasImage: detectionState.hasImage,
          onChanged: (range) {
            settingsNotifier.setRadiusRange(range.start, range.end);
          },
          onAutoEstimate: () {
            detectionNotifier.autoEstimateRadiusRange();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Auto-estimated radius range based on photo resolution. Verify before detecting.'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // Sensitivity / Confidence Slider
        ConfidenceSlider(
          value: settings.sensitivity,
          isEngineA: settings.engine == DetectionEngine.classicalCV,
          onChanged: (val) {
            settingsNotifier.setSensitivity(val);
          },
        ),

        // Size Tier Selector (Uniform, 2 Types, 3 Types, Auto) matching Desktop
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 16, color: Colors.grey),
                    SizedBox(width: 6),
                    Text(
                      'PIPE SIZE COLOR TIERS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: SizeTierMode.values.map((mode) {
                    final isSelected = detectionState.sizeTierMode == mode;
                    return ChoiceChip(
                      label: Text(mode.shortLabel),
                      selected: isSelected,
                      onSelected: (_) {
                        detectionNotifier.setSizeTierMode(mode);
                      },
                      avatar: isSelected ? const Icon(Icons.check, size: 14) : null,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  detectionState.sizeTierMode == SizeTierMode.uniform
                      ? '🟢 All pipes marked same size (Green). Perfect for uniform pipe bundles.'
                      : (detectionState.sizeTierMode == SizeTierMode.twoSizes
                          ? '🟢🔴 Split into 2 size types (Small Green / Large Red).'
                          : (detectionState.sizeTierMode == SizeTierMode.threeSizes
                              ? '🟢🟡🔴 Split into 3 size types (Green / Yellow / Red).'
                              : '⚡ Automatically detects if bundle is uniform or mixed.')),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Live Count Summary Card
        CountSummaryCard(result: detectionState.result),

        if (detectionState.hasResults) ...[
          const SizedBox(height: 14),

          // Instant Size Split Threshold Slider (0ms recolor)
          ThresholdSlider(
            result: detectionState.result,
            currentThreshold: detectionState.sizeThreshold,
            onChanged: (newThreshold) {
              detectionNotifier.updateThreshold(newThreshold);
            },
          ),

          const SizedBox(height: 14),

          // Export Button
          ElevatedButton.icon(
            onPressed: () {
              ExportDialog.show(
                context,
                result: detectionState.result!,
                imageName: detectionState.imageName ?? 'stacked_pipes.jpg',
              );
            },
            icon: const Icon(Icons.file_download, size: 18),
            label: const Text('Export Results (CSV / XLSX)', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],

        const SizedBox(height: 20),
      ],
    );
  }
}
