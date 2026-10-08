import 'package:flutter/material.dart';

class RadiusRangeSlider extends StatelessWidget {
  final double minRadius;
  final double maxRadius;
  final bool isAutoEnabled;
  final ValueChanged<RangeValues> onChanged;
  final ValueChanged<bool>? onToggleAuto;
  final VoidCallback onAutoEstimate;
  final bool hasImage;

  const RadiusRangeSlider({
    super.key,
    required this.minRadius,
    required this.maxRadius,
    this.isAutoEnabled = true,
    required this.onChanged,
    this.onToggleAuto,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.radio_button_unchecked, size: 15, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Pipe Radius Range',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (onToggleAuto != null)
                      InkWell(
                        onTap: () => onToggleAuto!(!isAutoEnabled),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: isAutoEnabled ? const Color(0xFF38BDF8).withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isAutoEnabled ? const Color(0xFF38BDF8) : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 11,
                                color: isAutoEnabled ? const Color(0xFF38BDF8) : Colors.grey,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isAutoEnabled ? 'Auto ON' : 'Manual',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isAutoEnabled ? const Color(0xFF38BDF8) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              ],
            ),
            const SizedBox(height: 4),
            RangeSlider(
              values: RangeValues(currentStart, currentEnd),
              min: sliderMin,
              max: sliderMax,
              divisions: 98,
              labels: RangeLabels('${currentStart.toInt()} px', '${currentEnd.toInt()} px'),
              onChanged: (val) {
                if (isAutoEnabled && onToggleAuto != null) {
                  onToggleAuto!(false); // Dragging slider automatically switches to manual override
                }
                onChanged(val);
              },
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
                  icon: const Icon(Icons.refresh, size: 13),
                  label: const Text(
                    'Re-calibrate',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ],
        ),
      ),
    );
  }
}
