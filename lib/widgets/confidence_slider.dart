import 'package:flutter/material.dart';

class ConfidenceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final bool isEngineA;
  final bool isAutoEnabled;
  final ValueChanged<bool>? onToggleAuto;

  const ConfidenceSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.isEngineA = true,
    this.isAutoEnabled = true,
    this.onToggleAuto,
  });

  @override
  Widget build(BuildContext context) {
    final title = isEngineA ? 'Edge Sensitivity (Canny)' : 'Confidence Threshold (ML)';
    final subtitle = isEngineA
        ? (isAutoEnabled
            ? '⚡ Auto-tuned from image gradient SNR. Drag to adjust manually.'
            : 'Manual: Higher = catches fainter rims, lower = ignores noise.')
        : 'Higher = stricter ML box filter (requires re-running detection)';

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
                      child: Icon(Icons.tune, size: 15, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (onToggleAuto != null && isEngineA)
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
                        '${(value * 100).toInt()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 2),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: value,
                min: 0.10,
                max: 0.90,
                divisions: 16,
                onChanged: (val) {
                  if (isAutoEnabled && onToggleAuto != null) {
                    onToggleAuto!(false); // Dragging switches to manual
                  }
                  onChanged(val);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
