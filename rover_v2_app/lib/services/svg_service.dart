import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/map_model.dart';

class SvgParseResult {
  final int width;
  final int height;
  final String? viewBox;
  final double? viewBoxWidth;
  final double? viewBoxHeight;

  const SvgParseResult({
    required this.width,
    required this.height,
    this.viewBox,
    this.viewBoxWidth,
    this.viewBoxHeight,
  });
}

class SvgService {
  /// Parse SVG file and extract dimensions
  SvgParseResult parseSvgFile(File file) {
    final content = file.readAsStringSync();
    
    int width = 800; // default
    int height = 600; // default
    String? viewBox;
    double? viewBoxWidth;
    double? viewBoxHeight;

    // Extract width
    final widthMatch = RegExp(r'width="([^"]+)"').firstMatch(content);
    if (widthMatch != null) {
      final wStr = widthMatch.group(1)!;
      width = int.tryParse(wStr.replaceAll('px', '').replaceAll('mm', '').replaceAll('cm', '').replaceAll('in', '')) ?? 800;
    }

    // Extract height
    final heightMatch = RegExp(r'height="([^"]+)"').firstMatch(content);
    if (heightMatch != null) {
      final hStr = heightMatch.group(1)!;
      height = int.tryParse(hStr.replaceAll('px', '').replaceAll('mm', '').replaceAll('cm', '').replaceAll('in', '')) ?? 600;
    }

    // Extract viewBox
    final viewBoxMatch = RegExp(r'viewBox="([^"]+)"').firstMatch(content);
    if (viewBoxMatch != null) {
      viewBox = viewBoxMatch.group(1);
      final parts = viewBox!.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        viewBoxWidth = double.tryParse(parts[2]);
        viewBoxHeight = double.tryParse(parts[3]);
      }
    }

    return SvgParseResult(
      width: width,
      height: height,
      viewBox: viewBox,
      viewBoxWidth: viewBoxWidth,
      viewBoxHeight: viewBoxHeight,
    );
  }

  /// Convert SVG to GridMap by rasterizing SVG to image, then converting to grid
  /// This approach renders the SVG to a bitmap, then samples pixels to create the grid
  GridMap convertSvgToGridMap({
    required File file,
    required String mapName,
    required double cellSizeCm,
    required double physicalWidthCm,
    required double physicalHeightCm,
    int padding = 1,
    Color obstacleColor = Colors.black,
    int threshold = 128, // Pixels darker than this become obstacles
  }) {
    // Read SVG content
    final svgContent = file.readAsStringSync();
    
    // Parse SVG dimensions
    final parseResult = parseSvgFile(file);
    
    // Calculate grid dimensions
    final cols = ((physicalWidthCm / cellSizeCm) + (padding * 2)).ceil();
    final rows = ((physicalHeightCm / cellSizeCm) + (padding * 2)).ceil();

    // Ensure minimum size
    final finalCols = max(5, min(cols, 100));
    final finalRows = max(5, min(rows, 100));

    // Create empty grid
    final grid = List.generate(finalRows, (_) => List.filled(finalCols, 0));

    // For a proper implementation, we'd need to render the SVG to a bitmap
    // Since Flutter doesn't have built-in SVG rendering to bitmap without a widget tree,
    // we'll use a simpler approach: parse basic SVG elements directly
    
    _parseSvgElements(
      content: svgContent,
      grid: grid,
      rows: finalRows,
      cols: finalCols,
      svgWidth: parseResult.width.toDouble(),
      svgHeight: parseResult.height.toDouble(),
      threshold: threshold,
    );

    return GridMap(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: mapName,
      rows: finalRows,
      cols: finalCols,
      cellSizeCm: cellSizeCm,
      grid: grid,
      createdAt: DateTime.now(),
    );
  }

  /// Parse basic SVG elements (rect, circle, line, polygon, path) and rasterize to grid
  void _parseSvgElements({
    required String content,
    required List<List<int>> grid,
    required int rows,
    required int cols,
    required double svgWidth,
    required double svgHeight,
    required int threshold,
  }) {
    // Parse rectangles
    _parseRectangles(content, grid, rows, cols, svgWidth, svgHeight);
    
    // Parse circles
    _parseCircles(content, grid, rows, cols, svgWidth, svgHeight);
    
    // Parse lines
    _parseLines(content, grid, rows, cols, svgWidth, svgHeight);
    
    // Parse polygons/polylines
    _parsePolygons(content, grid, rows, cols, svgWidth, svgHeight);
    
    // Parse paths (basic support)
    _parsePaths(content, grid, rows, cols, svgWidth, svgHeight);
  }

  void _parseRectangles(
    String content,
    List<List<int>> grid,
    int rows,
    int cols,
    double svgWidth,
    double svgHeight,
  ) {
    final rectRegex = RegExp(r'<rect[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*width="([^"]*)"[^>]*height="([^"]*)"[^>]*\/?>');
    final matches = rectRegex.allMatches(content);

    for (final match in matches) {
      final x = double.tryParse(match.group(1)!) ?? 0.0;
      final y = double.tryParse(match.group(2)!) ?? 0.0;
      final w = double.tryParse(match.group(3)!) ?? 0.0;
      final h = double.tryParse(match.group(4)!) ?? 0.0;

      _fillRectangle(grid, rows, cols, x, y, w, h, svgWidth, svgHeight);
    }
  }

  void _fillRectangle(
    List<List<int>> grid,
    int rows,
    int cols,
    double x,
    double y,
    double w,
    double h,
    double svgWidth,
    double svgHeight,
  ) {
    final r1 = ((y / svgHeight) * (rows - 1)).round().clamp(0, rows - 1);
    final c1 = ((x / svgWidth) * (cols - 1)).round().clamp(0, cols - 1);
    final r2 = (((y + h) / svgHeight) * (rows - 1)).round().clamp(0, rows - 1);
    final c2 = (((x + w) / svgWidth) * (cols - 1)).round().clamp(0, cols - 1);

    for (int r = r1; r <= r2; r++) {
      for (int c = c1; c <= c2; c++) {
        grid[r][c] = 1;
      }
    }
  }

  void _parseCircles(
    String content,
    List<List<int>> grid,
    int rows,
    int cols,
    double svgWidth,
    double svgHeight,
  ) {
    final circleRegex = RegExp(r'<circle[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*r="([^"]*)"[^>]*\/?>');
    final matches = circleRegex.allMatches(content);

    for (final match in matches) {
      final cx = double.tryParse(match.group(1)!) ?? 0.0;
      final cy = double.tryParse(match.group(2)!) ?? 0.0;
      final r = double.tryParse(match.group(3)!) ?? 0.0;

      _fillCircle(grid, rows, cols, cx, cy, r, svgWidth, svgHeight);
    }
  }

  void _fillCircle(
    List<List<int>> grid,
    int rows,
    int cols,
    double cx,
    double cy,
    double radius,
    double svgWidth,
    double svgHeight,
  ) {
    final centerX = (cx / svgWidth) * (cols - 1);
    final centerY = (cy / svgHeight) * (rows - 1);
    final r = (radius / svgWidth) * (cols - 1);

    final minR = (centerY - r).round().clamp(0, rows - 1);
    final maxR = (centerY + r).round().clamp(0, rows - 1);
    final minC = (centerX - r).round().clamp(0, cols - 1);
    final maxC = (centerX + r).round().clamp(0, cols - 1);

    for (int row = minR; row <= maxR; row++) {
      for (int col = minC; col <= maxC; col++) {
        final dx = col - centerX;
        final dy = row - centerY;
        if (dx * dx + dy * dy <= r * r) {
          grid[row][col] = 1;
        }
      }
    }
  }

  void _parseLines(
    String content,
    List<List<int>> grid,
    int rows,
    int cols,
    double svgWidth,
    double svgHeight,
  ) {
    final lineRegex = RegExp(r'<line[^>]*x1="([^"]*)"[^>]*y1="([^"]*)"[^>]*x2="([^"]*)"[^>]*y2="([^"]*)"[^>]*\/?>');
    final matches = lineRegex.allMatches(content);

    for (final match in matches) {
      final x1 = double.tryParse(match.group(1)!) ?? 0.0;
      final y1 = double.tryParse(match.group(2)!) ?? 0.0;
      final x2 = double.tryParse(match.group(3)!) ?? 0.0;
      final y2 = double.tryParse(match.group(4)!) ?? 0.0;

      _drawLine(grid, rows, cols, x1, y1, x2, y2, svgWidth, svgHeight);
    }
  }

  void _drawLine(
    List<List<int>> grid,
    int rows,
    int cols,
    double x1,
    double y1,
    double x2,
    double y2,
    double svgWidth,
    double svgHeight,
  ) {
    final col1 = ((x1 / svgWidth) * (cols - 1)).round().clamp(0, cols - 1);
    final row1 = ((y1 / svgHeight) * (rows - 1)).round().clamp(0, rows - 1);
    final col2 = ((x2 / svgWidth) * (cols - 1)).round().clamp(0, cols - 1);
    final row2 = ((y2 / svgHeight) * (rows - 1)).round().clamp(0, rows - 1);

    _bresenhamLine(grid, row1, col1, row2, col2);
  }

  void _bresenhamLine(List<List<int>> grid, int y0, int x0, int y1, int x1) {
    final dx = (x1 - x0).abs();
    final dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;

    var x = x0;
    var y = y0;

    while (true) {
      if (y >= 0 && y < grid.length && x >= 0 && x < grid[0].length) {
        grid[y][x] = 1;
      }

      if (x == x1 && y == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }

  void _parsePolygons(
    String content,
    List<List<int>> grid,
    int rows,
    int cols,
    double svgWidth,
    double svgHeight,
  ) {
    final polygonRegex = RegExp(r'<(polygon|polyline)[^>]*points="([^"]*)"[^>]*\/?>');
    final matches = polygonRegex.allMatches(content);

    for (final match in matches) {
      final pointsStr = match.group(2)!;
      final points = <List<double>>[];

      for (final pointStr in pointsStr.trim().split(RegExp(r'\s+'))) {
        if (pointStr.isEmpty) continue;
        final coords = pointStr.split(',');
        if (coords.length == 2) {
          final x = double.tryParse(coords[0]) ?? 0.0;
          final y = double.tryParse(coords[1]) ?? 0.0;
          points.add([x, y]);
        }
      }

      if (points.length >= 3) {
        _fillPolygon(grid, rows, cols, points, svgWidth, svgHeight);
      }
    }
  }

  void _fillPolygon(
    List<List<int>> grid,
    int rows,
    int cols,
    List<List<double>> points,
    double svgWidth,
    double svgHeight,
  ) {
    // Convert to grid coordinates
    final gridPoints = points.map((p) {
      return [
        ((p[0] / svgWidth) * (cols - 1)).round().clamp(0, cols - 1),
        ((p[1] / svgHeight) * (rows - 1)).round().clamp(0, rows - 1),
      ];
    }).toList();

    // Fill using scanline algorithm
    final minY = gridPoints.map((p) => p[1]).reduce(min);
    final maxY = gridPoints.map((p) => p[1]).reduce(max);

    for (int y = minY; y <= maxY; y++) {
      final intersections = <int>[];
      for (int i = 0; i < gridPoints.length; i++) {
        final j = (i + 1) % gridPoints.length;
        final y1 = gridPoints[i][1];
        final y2 = gridPoints[j][1];
        final x1 = gridPoints[i][0];
        final x2 = gridPoints[j][0];

        if ((y1 <= y && y2 > y) || (y2 <= y && y1 > y)) {
          final x = x1 + ((y - y1) * (x2 - x1) / (y2 - y1)).round();
          intersections.add(x);
        }
      }

      intersections.sort();
      for (int i = 0; i < intersections.length; i += 2) {
        if (i + 1 < intersections.length) {
          for (int x = intersections[i]; x <= intersections[i + 1]; x++) {
            if (y >= 0 && y < rows && x >= 0 && x < cols) {
              grid[y][x] = 1;
            }
          }
        }
      }
    }
  }

  void _parsePaths(
    String content,
    List<List<int>> grid,
    int rows,
    int cols,
    double svgWidth,
    double svgHeight,
  ) {
    // Basic path parsing - handles simple M (move) and L (line) commands
    final pathRegex = RegExp(r'<path[^>]*d="([^"]*)"[^>]*\/?>');
    final matches = pathRegex.allMatches(content);

    for (final match in matches) {
      final d = match.group(1)!;
      _parsePathData(grid, rows, cols, d, svgWidth, svgHeight);
    }
  }

  void _parsePathData(
    List<List<int>> grid,
    int rows,
    int cols,
    String d,
    double svgWidth,
    double svgHeight,
  ) {
    final commands = RegExp(r'([MLHVZCSPA])\s*([^MLHVZCSPA]*)');
    final matches = commands.allMatches(d);

    double currentX = 0;
    double currentY = 0;
    double startX = 0;
    double startY = 0;

    for (final match in matches) {
      final cmd = match.group(1);
      final args = match.group(2)!.trim();
      final values = args.split(RegExp(r'[,\s]+')).map((e) => double.tryParse(e) ?? 0.0).toList();

      switch (cmd) {
        case 'M':
          currentX = values[0];
          currentY = values[1];
          startX = currentX;
          startY = currentY;
          break;
        case 'L':
          final newX = values[0];
          final newY = values[1];
          _drawLine(grid, rows, cols, currentX, currentY, newX, newY, svgWidth, svgHeight);
          currentX = newX;
          currentY = newY;
          break;
        case 'H':
          final newX = values[0];
          _drawLine(grid, rows, cols, currentX, currentY, newX, currentY, svgWidth, svgHeight);
          currentX = newX;
          break;
        case 'V':
          final newY = values[0];
          _drawLine(grid, rows, cols, currentX, currentY, currentX, newY, svgWidth, svgHeight);
          currentY = newY;
          break;
        case 'Z':
          _drawLine(grid, rows, cols, currentX, currentY, startX, startY, svgWidth, svgHeight);
          currentX = startX;
          currentY = startY;
          break;
        // C, S, Q, T, A commands are more complex - skip for basic implementation
      }
    }
  }

  /// Get information about SVG file for display in UI
  Map<String, String> getSvgInfo(File file) {
    try {
      final result = parseSvgFile(file);
      return {
        'dimensions': '${result.width} × ${result.height} px',
        'viewBox': result.viewBox ?? 'Not specified',
        'triangles': 'N/A (2D vector)',
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }
}
