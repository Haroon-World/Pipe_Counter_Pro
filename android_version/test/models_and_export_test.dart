import 'package:flutter_test/flutter_test.dart';
import 'package:pipe_counter_pro/models/pipe_detection.dart';
import 'package:pipe_counter_pro/services/export_service.dart';

void main() {
  group('Models & Dynamic Thresholding Tests', () {
    test('instant reclassification with threshold updates categories and counts', () {
      final pipes = [
        const PipeDetection(id: 1, cx: 10, cy: 10, width: 20, height: 20, angle: 0, area: 314.0, solidity: 0.96),
        const PipeDetection(id: 2, cx: 50, cy: 50, width: 40, height: 40, angle: 0, area: 1256.0, solidity: 0.95),
        const PipeDetection(id: 3, cx: 90, cy: 90, width: 60, height: 60, angle: 0, area: 2827.0, solidity: 0.97),
      ];

      final initialResult = DetectionResult(
        pipes: pipes,
        imageWidth: 640,
        imageHeight: 480,
        processingTime: const Duration(milliseconds: 50),
        engineName: 'Engine A',
        currentThreshold: 1000.0,
      );

      final result1 = initialResult.reclassifiedWithThreshold(1000.0);
      expect(result1.smallCount, 1);
      expect(result1.largeCount, 2);
      expect(result1.pipes[0].category, PipeCategory.small);
      expect(result1.pipes[1].category, PipeCategory.large);

      final result2 = initialResult.reclassifiedWithThreshold(2000.0);
      expect(result2.smallCount, 2);
      expect(result2.largeCount, 1);
      expect(result2.pipes[1].category, PipeCategory.small);
      expect(result2.pipes[2].category, PipeCategory.large);
    });

    test('scaling detection preserves relative coordinates and recalculates area', () {
      const pipe = PipeDetection(
        id: 1,
        cx: 100,
        cy: 150,
        width: 40,
        height: 30,
        angle: 15,
        area: 942.47,
        solidity: 0.95,
      );

      final scaled = pipe.scaled(2.0);
      expect(scaled.cx, 200.0);
      expect(scaled.cy, 300.0);
      expect(scaled.width, 80.0);
      expect(scaled.height, 60.0);
      expect(scaled.solidity, 0.95);
      expect(scaled.area, closeTo(942.47 * 4.0, 1.0));
    });
  });

  group('Export Service Tests', () {
    test('generateCsv contains summary section and pipe table rows with solidity', () {
      final pipes = [
        const PipeDetection(
          id: 1,
          cx: 100.5,
          cy: 200.5,
          width: 30.0,
          height: 25.0,
          angle: 10.0,
          area: 589.0,
          category: PipeCategory.small,
          solidity: 0.96,
        ),
      ];

      final result = DetectionResult(
        pipes: pipes,
        imageWidth: 1920,
        imageHeight: 1080,
        processingTime: const Duration(milliseconds: 120),
        engineName: 'Engine A (Classical CV)',
        currentThreshold: 600.0,
      );

      final csv = ExportService.generateCsv(result: result, imageName: 'test_pipes.jpg');

      expect(csv, contains('PIPE COUNTER PRO - DETECTION REPORT'));
      expect(csv, contains('test_pipes.jpg'));
      expect(csv, contains('Total Count,1'));
      expect(csv, contains('Small Count (Green),1'));
      expect(csv, contains('Large Count (Red),0'));
      expect(csv, contains('Solidity'));
      expect(csv, contains('1,100.50,200.50,30.00,25.00,10.0,589.0,Small,0.96,1.00'));
    });

    test('generateExcel produces non-empty byte buffer', () {
      const result = DetectionResult(
        pipes: [
          PipeDetection(id: 1, cx: 50, cy: 50, width: 20, height: 20, angle: 0, area: 314.0, solidity: 0.94),
        ],
        imageWidth: 640,
        imageHeight: 480,
        processingTime: Duration(milliseconds: 40),
        engineName: 'Engine A',
        currentThreshold: 500.0,
      );

      final bytes = ExportService.generateExcel(result: result, imageName: 'pipes.png');
      expect(bytes, isNotEmpty);
    });
  });
}

