import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pickModelFile(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select Custom Pipe Model (.tflite)',
      );

      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.single;
        final fileName = picked.name;
        final sourcePath = picked.path;

        if (!fileName.toLowerCase().endsWith('.tflite')) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select a valid TensorFlow Lite model (.tflite file).'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        if (sourcePath != null) {
          if (!kIsWeb) {
            final appDocDir = await getApplicationDocumentsDirectory();
            final modelsDir = Directory(p.join(appDocDir.path, 'models'));
            if (!modelsDir.existsSync()) {
              modelsDir.createSync(recursive: true);
            }

            final targetPath = p.join(modelsDir.path, fileName);
            await File(sourcePath).copy(targetPath);

            await ref.read(settingsProvider.notifier).setCustomModel(targetPath, fileName);
          } else {
            await ref.read(settingsProvider.notifier).setCustomModel(sourcePath, fileName);
          }

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Imported custom model: $fileName'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import model: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Detection Engines'),
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        children: [
          // Engine selection section
          const Text(
            'DETECTION ENGINE',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.grey),
          ),
          const SizedBox(height: 8),

          // Clarification banner that no model file is needed
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No external model file needed! Engine A is 100% offline, self-contained, and detects pipes automatically on your device.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Engine A Card
          Card(
            elevation: settings.engine == DetectionEngine.classicalCV ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: settings.engine == DetectionEngine.classicalCV
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: RadioListTile<DetectionEngine>(
              value: DetectionEngine.classicalCV,
              groupValue: settings.engine,
              onChanged: (val) {
                if (val != null) settingsNotifier.setEngine(val);
              },
              title: const Row(
                children: [
                  Text('Engine A — Classical CV', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                  Chip(
                    label: Text('Default / Offline', style: TextStyle(fontSize: 10, color: Colors.green)),
                    backgroundColor: Color(0xFFE8F5E9),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 6.0),
                child: Text(
                  'Hough Circle Transform + ROI-crop ellipse fitting + Monotone Chain convex hull solidity filtering. Rejects concave gaps between stacked pipes. Completely offline with zero training.',
                  style: TextStyle(fontSize: 12, height: 1.3),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Engine B Card
          Card(
            elevation: settings.engine == DetectionEngine.tflite ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: settings.engine == DetectionEngine.tflite
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                children: [
                  RadioListTile<DetectionEngine>(
                    value: DetectionEngine.tflite,
                    groupValue: settings.engine,
                    onChanged: (val) {
                      if (val != null) settingsNotifier.setEngine(val);
                    },
                    title: const Row(
                      children: [
                        Text('Engine B — Custom ML Model', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(width: 8),
                        Chip(
                          label: Text('User-Supplied', style: TextStyle(fontSize: 10, color: Colors.blue)),
                          backgroundColor: Color(0xFFE3F2FD),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 6.0),
                      child: Text(
                        'Uses a user-imported TensorFlow Lite (.tflite) model with ROI-crop contour ellipse refinement and solidity checking.',
                        style: TextStyle(fontSize: 12, height: 1.3),
                      ),
                    ),
                  ),

                  // Model import
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                settings.customModelPath != null ? Icons.check_circle : Icons.warning_amber_rounded,
                                color: settings.customModelPath != null ? Colors.green : Colors.amber.shade800,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  settings.customModelName ?? 'No model file imported yet',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              if (settings.customModelPath != null)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  tooltip: 'Remove Model',
                                  onPressed: () => settingsNotifier.clearCustomModel(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _pickModelFile(context, ref),
                            icon: const Icon(Icons.file_upload_outlined, size: 18),
                            label: Text(settings.customModelPath != null ? 'Replace .tflite Model' : 'Import .tflite Model'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(38),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Advanced Parameters Section (Solidity & Outlier Rejection)
          const Text(
            'ADVANCED FILTERING PARAMETERS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.grey),
          ),
          const SizedBox(height: 10),

          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Solidity Threshold Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Solidity Threshold',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          settings.solidityThreshold.toStringAsFixed(2),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: settings.solidityThreshold,
                    min: 0.70,
                    max: 0.98,
                    divisions: 28,
                    onChanged: (val) => settingsNotifier.setSolidityThreshold(val),
                  ),
                  Text(
                    'Ratio of contour area to convex hull area (default 0.85). Real pipe rims are convex (~0.90–1.0); interstitial gaps between 3 touching pipes are concave (~0.60–0.82) and get rejected.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),

                  const Divider(height: 28),

                  // Median Outlier Rejection Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Median Outlier Rejection',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${(settings.outlierFraction * 100).toInt()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: settings.outlierFraction,
                    min: 0.05,
                    max: 0.30,
                    divisions: 25,
                    onChanged: (val) => settingsNotifier.setOutlierFraction(val),
                  ),
                  Text(
                    'Drops candidate shapes whose area is less than this percentage of the median pipe area (default 12%). Active when >= 4 pipes are detected.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Technical constraint alert
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade900),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Important Notice on Pretrained ML Models',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A stock pretrained COCO detection model (e.g. standard YOLOv8/MobileNet) has NO "pipe" class and will fail to detect pipes. Engine B is designed exclusively for custom models fine-tuned on pipe datasets. For zero-training immediate detection, keep Engine A selected.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
