import 'dart:math' as math;
import 'dart:typed_data';

class Contour {
  final List<math.Point<int>> points;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final double perimeter;

  const Contour({
    required this.points,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.perimeter,
  });

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
}

class ContourTracer {
  /// 8-connectivity neighborhood offsets: E, SE, S, SW, W, NW, N, NE
  static const List<int> _dx = [1, 1, 0, -1, -1, -1, 0, 1];
  static const List<int> _dy = [0, 1, 1, 1, 0, -1, -1, -1];

  /// Extracts contours from a binary edge map (edges == 255).
  static List<Contour> extractContours(
    Uint8List edges,
    int width,
    int height, {
    int minPoints = 12,
    int maxPoints = 5000,
  }) {
    final visited = Uint8List(width * height);
    final contours = <Contour>[];

    for (int y = 2; y < height - 2; y++) {
      final row = y * width;
      for (int x = 2; x < width - 2; x++) {
        final idx = row + x;
        if (edges[idx] == 255 && visited[idx] == 0) {
          // Trace connected edge segment
          final points = <math.Point<int>>[];
          int minX = x, maxX = x, minY = y, maxY = y;

          // Breadth-First / Depth-First search along the edge path
          final queue = <int>[idx];
          visited[idx] = 1;

          while (queue.isNotEmpty && points.length < maxPoints) {
            final curr = queue.removeLast();
            final cx = curr % width;
            final cy = curr ~/ width;
            points.add(math.Point(cx, cy));

            if (cx < minX) minX = cx;
            if (cx > maxX) maxX = cx;
            if (cy < minY) minY = cy;
            if (cy > maxY) maxY = cy;

            for (int i = 0; i < 8; i++) {
              final nx = cx + _dx[i];
              final ny = cy + _dy[i];

              if (nx >= 1 && nx < width - 1 && ny >= 1 && ny < height - 1) {
                final nIdx = ny * width + nx;
                if (edges[nIdx] == 255 && visited[nIdx] == 0) {
                  visited[nIdx] = 1;
                  queue.add(nIdx);
                }
              }
            }
          }

          if (points.length >= minPoints) {
            // Calculate approximate perimeter
            double perimeter = 0;
            for (int i = 0; i < points.length - 1; i++) {
              final p1 = points[i];
              final p2 = points[i + 1];
              final d = math.sqrt((p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y));
              perimeter += d;
            }

            contours.add(Contour(
              points: points,
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              perimeter: perimeter,
            ));
          }
        }
      }
    }

    return contours;
  }
}
