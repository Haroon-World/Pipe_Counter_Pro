import 'package:flutter/material.dart';
import '../models/pipe_detection.dart';

class CountSummaryCard extends StatelessWidget {
  final DetectionResult? result;

  const CountSummaryCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final total = result?.totalCount ?? 0;
    final active = result?.activeCount ?? 0;
    final deselected = result?.deselectedCount ?? 0;
    final small = result?.smallCount ?? 0;
    final medium = result?.mediumCount ?? 0;
    final large = result?.largeCount ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pipe Count Summary',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (deselected > 0)
                      Text(
                        '$deselected pipe${deselected == 1 ? "" : "s"} excluded',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                if (result != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${result!.processingTime.inMilliseconds} ms',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Total / Active Count Tile
                Expanded(
                  flex: 3,
                  child: _MetricTile(
                    label: deselected > 0 ? 'COUNTED' : 'TOTAL',
                    value: deselected > 0 ? '$active' : '$total',
                    subValue: deselected > 0 ? 'of $total' : null,
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.all_inclusive,
                  ),
                ),
                const SizedBox(width: 6),
                // Small (Green)
                Expanded(
                  flex: 2,
                  child: _MetricTile(
                    label: 'SMALL',
                    value: '$small',
                    color: const Color(0xFF22C55E),
                    icon: Icons.lens,
                  ),
                ),
                const SizedBox(width: 6),
                // Medium (Yellow)
                Expanded(
                  flex: 2,
                  child: _MetricTile(
                    label: 'MED',
                    value: '$medium',
                    color: const Color(0xFFEAB308),
                    icon: Icons.lens,
                  ),
                ),
                const SizedBox(width: 6),
                // Large (Red)
                Expanded(
                  flex: 2,
                  child: _MetricTile(
                    label: 'LARGE',
                    value: '$large',
                    color: const Color(0xFFEF4444),
                    icon: Icons.lens,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final Color color;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    this.subValue,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subValue != null)
            Text(
              subValue!,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: color.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }
}
