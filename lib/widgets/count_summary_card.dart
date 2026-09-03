import 'package:flutter/material.dart';
import '../models/pipe_detection.dart';

class CountSummaryCard extends StatelessWidget {
  final DetectionResult? result;

  const CountSummaryCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final total = result?.totalCount ?? 0;
    final small = result?.smallCount ?? 0;
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
                const Text(
                  'Pipe Count Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            const SizedBox(height: 16),
            Row(
              children: [
                // Total Count
                Expanded(
                  child: _MetricTile(
                    label: 'TOTAL',
                    value: '$total',
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.all_inclusive,
                  ),
                ),
                const SizedBox(width: 8),
                // Small Count (Green)
                Expanded(
                  child: _MetricTile(
                    label: 'SMALL',
                    value: '$small',
                    color: const Color(0xFF00C853),
                    icon: Icons.lens,
                  ),
                ),
                const SizedBox(width: 8),
                // Large Count (Red)
                Expanded(
                  child: _MetricTile(
                    label: 'LARGE',
                    value: '$large',
                    color: const Color(0xFFD50000),
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
  final Color color;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
