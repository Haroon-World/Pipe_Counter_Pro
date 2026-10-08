import 'package:flutter/material.dart';
import '../models/pipe_detection.dart';
import '../services/export_service.dart';

class ExportDialog extends StatefulWidget {
  final DetectionResult result;
  final String imageName;

  const ExportDialog({
    super.key,
    required this.result,
    required this.imageName,
  });

  static Future<void> show(
    BuildContext context, {
    required DetectionResult result,
    required String imageName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ExportDialog(result: result, imageName: imageName),
    );
  }

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isExporting = false;
  String? _statusMessage;

  Future<void> _handleExport(ExportFormat format) async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Generating ${format == ExportFormat.csv ? 'CSV' : 'Excel'} file...';
    });

    try {
      final path = await ExportService.export(
        result: widget.result,
        imageName: widget.imageName,
        format: format,
      );

      if (mounted) {
        Navigator.of(context).pop();

        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully exported to: $path'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = 'Export failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.file_download, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Export Pipe Count Results'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export ${widget.result.totalCount} detected pipe measurements (${widget.result.smallCount} Small, ${widget.result.largeCount} Large) with coordinate metadata.',
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          if (_isExporting)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_statusMessage ?? 'Exporting...', style: const TextStyle(fontSize: 13)),
                ],
              ),
            )
          else ...[
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.table_chart, color: Colors.green),
              ),
              title: const Text('Excel Spreadsheet (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Formatted multi-column sheet with styled summary'),
              onTap: () => _handleExport(ExportFormat.excel),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.description, color: Colors.blue),
              ),
              title: const Text('Comma-Separated Values (.csv)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Standard universal data format for databases'),
              onTap: () => _handleExport(ExportFormat.csv),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isExporting)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
