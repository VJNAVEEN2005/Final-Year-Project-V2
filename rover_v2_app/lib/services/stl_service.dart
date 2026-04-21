import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import '../models/map_model.dart';

class Triangle {
  final double x1, y1, z1;
  final double x2, y2, z2;
  final double x3, y3, z3;

  const Triangle({
    required this.x1,
    required this.y1,
    required this.z1,
    required this.x2,
    required this.y2,
    required this.z2,
    required this.x3,
    required this.y3,
    required this.z3,
  });
}

class StlParseResult {
  final List<Triangle> triangles;
  final double minX, maxX, minY, maxY, minZ, maxZ;

  const StlParseResult({
    required this.triangles,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
  });
}

class StlService {
  /// Parse an STL file (binary or ASCII) and extract triangles
  StlParseResult parseStlFile(File file) {
    final bytes = file.readAsBytesSync();
    final fileName = path.basename(file.path).toLowerCase();

    if (fileName.endsWith('.stl')) {
      // Try binary first, fallback to ASCII
      if (_isBinarySTL(bytes)) {
        return _parseBinarySTL(bytes);
      } else {
        final content = file.readAsStringSync();
        return _parseAsciiSTL(content);
      }
    }

    throw Exception('Unsupported file format. Only STL files are supported.');
  }

  bool _isBinarySTL(Uint8List bytes) {
    // Binary STL has an 80-byte header, then 4-byte triangle count
    // ASCII STL starts with "solid" or "endsolid"
    if (bytes.length < 84) return false;

    // Check if bytes 0-79 contain non-ASCII characters (binary indicator)
    for (int i = 0; i < 80; i++) {
      if (bytes[i] > 127) return true;
    }

    // Check triangle count vs file size
    final triangleCount = ByteData.sublistView(bytes, 80, 84).getUint32(0, Endian.little);
    final expectedSize = 84 + (triangleCount * 50);
    return bytes.length == expectedSize;
  }

  StlParseResult _parseBinarySTL(Uint8List bytes) {
    final triangles = <Triangle>[];
    final byteData = ByteData.sublistView(bytes);

    if (bytes.length < 84) {
      throw Exception('Invalid binary STL file: file too small');
    }

    final triangleCount = byteData.getUint32(80, Endian.little);

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;

    int offset = 84;
    for (int i = 0; i < triangleCount; i++) {
      if (offset + 50 > bytes.length) {
        throw Exception('Invalid binary STL file: unexpected end of data at triangle $i');
      }

      // Skip normal vector (3 floats = 12 bytes)
      offset += 12;

      // Read 3 vertices (each vertex = 3 floats = 12 bytes)
      final x1 = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final y1 = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final z1 = byteData.getFloat32(offset, Endian.little);
      offset += 4;

      final x2 = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final y2 = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final z2 = byteData.getFloat32(offset, Endian.little);
      offset += 4;

      final x3 = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final y3 = byteData.getFloat32(offset, Endian.little);
      offset += 4;
      final z3 = byteData.getFloat32(offset, Endian.little);
      offset += 4;

      // Skip attribute byte count (2 bytes)
      offset += 2;

      triangles.add(Triangle(
        x1: x1, y1: y1, z1: z1,
        x2: x2, y2: y2, z2: z2,
        x3: x3, y3: y3, z3: z3,
      ));

      // Update bounds (using X and Z for floor plan, Y for height)
      minX = min(minX, min(x1, min(x2, x3)));
      maxX = max(maxX, max(x1, max(x2, x3)));
      minZ = min(minZ, min(z1, min(z2, z3)));
      maxZ = max(maxZ, max(z1, max(z2, z3)));
      minY = min(minY, min(y1, min(y2, y3)));
      maxY = max(maxY, max(y1, max(y2, y3)));
    }

    return StlParseResult(
      triangles: triangles,
      minX: minX, maxX: maxX,
      minY: minY, maxY: maxY,
      minZ: minZ, maxZ: maxZ,
    );
  }

  StlParseResult _parseAsciiSTL(String content) {
    final triangles = <Triangle>[];
    final lines = content.split('\n');

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.startsWith('facet') || line.startsWith('outer loop')) {
        // Find the 3 vertex lines
        final vertices = <List<double>>[];
        i++;
        while (i < lines.length && vertices.length < 3) {
          final vLine = lines[i].trim();
          if (vLine.startsWith('vertex')) {
            final parts = vLine.split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final x = double.tryParse(parts[1]) ?? 0.0;
              final y = double.tryParse(parts[2]) ?? 0.0;
              final z = double.tryParse(parts[3]) ?? 0.0;
              vertices.add([x, y, z]);
            }
          }
          i++;
        }

        if (vertices.length == 3) {
          triangles.add(Triangle(
            x1: vertices[0][0], y1: vertices[0][1], z1: vertices[0][2],
            x2: vertices[1][0], y2: vertices[1][1], z2: vertices[1][2],
            x3: vertices[2][0], y3: vertices[2][1], z3: vertices[2][2],
          ));

          // Update bounds
          for (final v in vertices) {
            minX = min(minX, v[0]);
            maxX = max(maxX, v[0]);
            minZ = min(minZ, v[2]);
            maxZ = max(maxZ, v[2]);
            minY = min(minY, v[1]);
            maxY = max(maxY, v[1]);
          }
        }
      }
      i++;
    }

    return StlParseResult(
      triangles: triangles,
      minX: minX, maxX: maxX,
      minY: minY, maxY: maxY,
      minZ: minZ, maxZ: maxZ,
    );
  }

  /// Convert STL parse result to a GridMap
  /// Projects 3D mesh onto XZ plane (floor plan)
  /// [heightThreshold] - Y value threshold to consider as obstacle (default: 0)
  /// [cellSizeCm] - physical size of each grid cell in centimeters
  /// [padding] - additional padding around the model in cells
  GridMap convertToGridMap({
    required StlParseResult stlResult,
    required String mapName,
    required double cellSizeCm,
    double heightThreshold = 0.0,
    int padding = 1,
  }) {
    if (stlResult.triangles.isEmpty) {
      throw Exception('No triangles found in STL file');
    }

    // Calculate dimensions based on XZ bounding box
    final widthX = stlResult.maxX - stlResult.minX;
    final depthZ = stlResult.maxZ - stlResult.minZ;

    // Calculate grid dimensions
    final cols = ((widthX / cellSizeCm) + (padding * 2)).ceil();
    final rows = ((depthZ / cellSizeCm) + (padding * 2)).ceil();

    // Ensure minimum size
    final finalCols = max(5, min(cols, 100));
    final finalRows = max(5, min(rows, 100));

    // Create empty grid
    final grid = List.generate(finalRows, (_) => List.filled(finalCols, 0));

    // Rasterize triangles onto grid
    for (final triangle in stlResult.triangles) {
      _rasterizeTriangle(
        grid: grid,
        rows: finalRows,
        cols: finalCols,
        x1: triangle.x1, z1: triangle.z1, y1: triangle.y1,
        x2: triangle.x2, z2: triangle.z2, y2: triangle.y2,
        x3: triangle.x3, z3: triangle.z3, y3: triangle.y3,
        minX: stlResult.minX,
        minZ: stlResult.minZ,
        cellSizeCm: cellSizeCm,
        padding: padding,
        heightThreshold: heightThreshold,
      );
    }

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

  void _rasterizeTriangle({
    required List<List<int>> grid,
    required int rows,
    required int cols,
    required double x1, z1, y1,
    required double x2, z2, y2,
    required double x3, z3, y3,
    required double minX,
    required double minZ,
    required double cellSizeCm,
    required int padding,
    required double heightThreshold,
  }) {
    // Check if any vertex is above height threshold
    final avgHeight = (y1 + y2 + y3) / 3.0;
    if (avgHeight < heightThreshold) return;

    // Convert world coordinates to grid coordinates
    final r1 = ((z1 - minZ) / cellSizeCm + padding).round().toInt();
    final c1 = ((x1 - minX) / cellSizeCm + padding).round().toInt();
    final r2 = ((z2 - minZ) / cellSizeCm + padding).round().toInt();
    final c2 = ((x2 - minX) / cellSizeCm + padding).round().toInt();
    final r3 = ((z3 - minZ) / cellSizeCm + padding).round().toInt();
    final c3 = ((x3 - minX) / cellSizeCm + padding).round().toInt();

    // Fill triangle using bounding box approach
    final minR = max(0, min(r1, min(r2, r3))).toInt();
    final maxR = min(rows - 1, max(r1, max(r2, r3))).toInt();
    final minC = max(0, min(c1, min(c2, c3))).toInt();
    final maxC = min(cols - 1, max(c1, max(c2, c3))).toInt();

    for (int r = minR; r <= maxR; r++) {
      for (int c = minC; c <= maxC; c++) {
        if (_pointInTriangle(c.toDouble(), r.toDouble(), c1.toDouble(), r1.toDouble(), c2.toDouble(), r2.toDouble(), c3.toDouble(), r3.toDouble())) {
          grid[r][c] = 1;
        }
      }
    }
  }

  bool _pointInTriangle(double px, double py, double x1, double y1, double x2, double y2, double x3, double y3) {
    final d1 = _sign(px, py, x1, y1, x2, y2);
    final d2 = _sign(px, py, x2, y2, x3, y3);
    final d3 = _sign(px, py, x3, y3, x1, y1);

    final hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
    final hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);

    return !(hasNeg && hasPos);
  }

  double _sign(double px, double py, double x1, double y1, double x2, double y2) {
    return (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2);
  }
}
