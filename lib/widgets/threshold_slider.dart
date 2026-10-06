import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/pipe_detection.dart';

class ThresholdSlider extends StatelessWidget {
  final DetectionResult? result;
  final double currentThreshold;
  final ValueChanged<double> onChanged;
  final VoidCallback? onAutoSnap;

  const ThresholdSlider({
    super.key,
    required this.result,
    required this.currentThreshold,
    required this.onChanged,
    this.onAutoSnap,
  });

  @override
  Widget build(BuildContext context) {
    if (result == null || result!.pipes.isEmpty) {
      return const SizedBox.shrink();
    }

    final minArea = result!.minArea;
    final maxArea = result!.maxArea;

    final sliderMin = minArea;
    final sliderMax = (maxArea <= minArea) ? minArea + 1000.0 : maxArea;
    final activeValue = currentThreshold.clamp(sliderMin, sliderMax);
    final approxDiam = 2.0 * math.sqrt(activeValue / math.pi);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.straighten, size: 16, color: Colors.amber.shade800),
                    ),
                    const SizedBox(width: 8),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Size Split Ruler',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Auto-snapped to distribution valley',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Ø ${approxDiam.toStringAsFixed(1)} px (${activeValue.toStringAsFixed(0)} px²)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.amber.shade700,
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.2),
                thumbColor: Colors.amber.shade800,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              ),
              child: Slider(
                value: activeValue,
                min: sliderMin,
                max: sliderMax,
                onChanged: onChanged,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Small 🟢  < ${approxDiam.toStringAsFixed(0)} px',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF22C55E)),
                ),
                if (onAutoSnap != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onAutoSnap,
                    icon: const Icon(Icons.auto_awesome, size: 12, color: Colors.amber),
                    label: const Text('Re-snap Auto', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                Text(
                  '> ${approxDiam.toStringAsFixed(0)} px  🔴 Large',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
