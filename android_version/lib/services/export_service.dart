import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pipe_detection.dart';

enum ExportFormat { csv, excel }

class ExportService {
  /// Generates CSV string from detection results
  static String generateCsv({
    required DetectionResult result,
    required String imageName,
  }) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    final List<List<dynamic>> rows = [
      // Summary section
      ['PIPE COUNTER PRO - DETECTION REPORT'],
      ['Export Date & Time', timestamp],
      ['Source Image', imageName],
      ['Detection Engine', result.engineName],
      ['Image Resolution', '${result.imageWidth} x ${result.imageHeight} px'],
      ['Processing Time', '${result.processingTime.inMilliseconds} ms'],
      ['Size Split Threshold', '${result.currentThreshold.toStringAsFixed(1)} px^2'],
      ['Total Count', result.totalCount],
      ['Small Count (Green)', result.smallCount],
      ['Large Count (Red)', result.largeCount],
      [],
      // Per-pipe table header
      [
        'Pipe ID',
        'Center X (px)',
        'Center Y (px)',
        'Width (px)',
        'Height (px)',
        'Orientation Angle (deg)',
        'Area (px^2)',
        'Category',
        'Solidity',
        'Confidence',
      ],
    ];

    // Per-pipe data rows
    for (final pipe in result.pipes) {
      rows.add([
        pipe.id,
        pipe.cx.toStringAsFixed(2),
        pipe.cy.toStringAsFixed(2),
        pipe.width.toStringAsFixed(2),
        pipe.height.toStringAsFixed(2),
        pipe.angle.toStringAsFixed(1),
        pipe.area.toStringAsFixed(1),
        pipe.category.displayName,
        pipe.solidity.toStringAsFixed(2),
        pipe.confidence.toStringAsFixed(2),
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Generates Excel workbook (.xlsx) bytes
  static List<int> generateExcel({
    required DetectionResult result,
    required String imageName,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Pipe Counts');
    final sheet = excel['Pipe Counts'];

    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    sheet.appendRow([TextCellValue('PIPE COUNTER PRO - SUMMARY REPORT')]);
    sheet.appendRow([TextCellValue('Export Date'), TextCellValue(timestamp)]);
    sheet.appendRow([TextCellValue('Source Image'), TextCellValue(imageName)]);
    sheet.appendRow([TextCellValue('Detection Engine'), TextCellValue(result.engineName)]);
    sheet.appendRow([TextCellValue('Image Size'), TextCellValue('${result.imageWidth} x ${result.imageHeight} px')]);
    sheet.appendRow([TextCellValue('Split Threshold (px^2)'), DoubleCellValue(result.currentThreshold)]);
    sheet.appendRow([TextCellValue('Total Pipes'), IntCellValue(result.totalCount)]);
    sheet.appendRow([TextCellValue('Small Pipes (Green)'), IntCellValue(result.smallCount)]);
    sheet.appendRow([TextCellValue('Large Pipes (Red)'), IntCellValue(result.largeCount)]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('Pipe ID'),
      TextCellValue('Center X (px)'),
      TextCellValue('Center Y (px)'),
      TextCellValue('Width (px)'),
      TextCellValue('Height (px)'),
      TextCellValue('Angle (deg)'),
      TextCellValue('Area (px^2)'),
      TextCellValue('Category'),
      TextCellValue('Solidity'),
      TextCellValue('Confidence'),
    ]);

    for (final pipe in result.pipes) {
      sheet.appendRow([
        IntCellValue(pipe.id),
        DoubleCellValue(double.parse(pipe.cx.toStringAsFixed(2))),
        DoubleCellValue(double.parse(pipe.cy.toStringAsFixed(2))),
        DoubleCellValue(double.parse(pipe.width.toStringAsFixed(2))),
        DoubleCellValue(double.parse(pipe.height.toStringAsFixed(2))),
        DoubleCellValue(double.parse(pipe.angle.toStringAsFixed(1))),
        DoubleCellValue(double.parse(pipe.area.toStringAsFixed(1))),
        TextCellValue(pipe.category.displayName),
        DoubleCellValue(double.parse(pipe.solidity.toStringAsFixed(2))),
        DoubleCellValue(double.parse(pipe.confidence.toStringAsFixed(2))),
      ]);
    }

    final bytes = excel.encode();
    return bytes ?? [];
  }

  /// Exports data, providing platform-adapted save or share experience
  static Future<String?> export({
    required DetectionResult result,
    required String imageName,
    required ExportFormat format,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final ext = format == ExportFormat.csv ? 'csv' : 'xlsx';
    final fileName = 'pipe_count_$timestamp.$ext';

    final Uint8List bytes;
    if (format == ExportFormat.csv) {
      final csvContent = generateCsv(result: result, imageName: imageName);
      bytes = Uint8List.fromList(csvContent.codeUnits);
    } else {
      final excelBytes = generateExcel(result: result, imageName: imageName);
      bytes = Uint8List.fromList(excelBytes);
    }

    if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Pipe Count Report',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: bytes,
      );

      if (!kIsWeb && selectedPath != null) {
        final file = File(selectedPath);
        await file.writeAsBytes(bytes);
        return file.path;
      }
      return selectedPath ?? fileName;
    } else {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'Pipe Counter Pro Report - $imageName',
        text: 'Pipe Count Summary: ${result.totalCount} total (${result.smallCount} Small, ${result.largeCount} Large).',
      );

      return filePath;
    }
  }
}
