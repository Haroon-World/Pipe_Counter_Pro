import 'package:flutter/material.dart';

class RadiusRangeSlider extends StatelessWidget {
  final double minRadius;
  final double maxRadius;
  final ValueChanged<RangeValues> onChanged;
  final VoidCallback onAutoEstimate;
  final bool hasImage;

  const RadiusRangeSlider({
    super.key,
    required this.minRadius,
    required this.maxRadius,
    required this.onChanged,
    required this.onAutoEstimate,
    required this.hasImage,
  });

  @override
  Widget build(BuildContext context) {
    const sliderMin = 4.0;
    const sliderMax = 200.0;

    final currentStart = minRadius.clamp(sliderMin, sliderMax - 2.0);
    final currentEnd = maxRadius.clamp(currentStart + 1.0, sliderMax);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.radio_button_unchecked, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Pipe Radius Range (Hough)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${currentStart.toInt()} - ${currentEnd.toInt()} px',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            RangeSlider(
              values: RangeValues(currentStart, currentEnd),
              min: sliderMin,
              max: sliderMax,
              divisions: 98,
              labels: RangeLabels('${currentStart.toInt()} px', '${currentEnd.toInt()} px'),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: ${currentStart.toInt()} px',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                TextButton.icon(
                  onPressed: hasImage ? onAutoEstimate : null,
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text(
                    'Auto-Estimate',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                Text(
                  'Max: ${currentEnd.toInt()} px',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sets Hough circle search bounds. Range set too low introduces gap noise; range set too high misses smaller pipes.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
