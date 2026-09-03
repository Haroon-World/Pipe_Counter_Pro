import 'package:flutter/material.dart';
import '../models/pipe_detection.dart';

class ThresholdSlider extends StatelessWidget {
  final DetectionResult? result;
  final double currentThreshold;
  final ValueChanged<double> onChanged;

  const ThresholdSlider({
    super.key,
    required this.result,
    required this.currentThreshold,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (result == null || result!.pipes.isEmpty) {
      return const SizedBox.shrink();
    }

    final minArea = result!.minArea;
    final maxArea = result!.maxArea;

    // Safety checks for slider bounds
    final sliderMin = minArea;
    final sliderMax = (maxArea <= minArea) ? minArea + 1000.0 : maxArea;
    final activeValue = currentThreshold.clamp(sliderMin, sliderMax);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.straighten, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Size Split Threshold',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${activeValue.toStringAsFixed(0)} px²',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.amber.shade700,
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
                  'Min: ${sliderMin.toStringAsFixed(0)} px²',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  'Live Instant Recolor',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
                Text(
                  'Max: ${sliderMax.toStringAsFixed(0)} px²',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
