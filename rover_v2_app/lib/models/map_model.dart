import 'dart:convert';

/// 0 = empty cell, 1 = wall cell
typedef RoverGrid = List<List<int>>;

/// Cardinal directions: 0=North, 1=East, 2=South, 3=West
enum RoverDirection {
  north,
  east,
  south,
  west;

  String get label {
    switch (this) {
      case north: return 'N';
      case east:  return 'E';
      case south: return 'S';
      case west:  return 'W';
    }
  }

  String get arrow {
    switch (this) {
      case north: return '↑';
      case east:  return '→';
      case south: return '↓';
      case west:  return '←';
    }
  }

  static RoverDirection fromIndex(int i) => RoverDirection.values[i % 4];
}

class GridMap {
  final String id;
  final String name;
  final int rows;
  final int cols;
  final double cellSizeCm;     // physical size of each cell in centimeters
  final RoverGrid grid;        // grid[row][col]: 0=empty, 1=wall
  final int? startRow;
  final int? startCol;
  final int startDirectionIndex; // RoverDirection index
  final DateTime createdAt;

  const GridMap({
    required this.id,
    required this.name,
    required this.rows,
    required this.cols,
    required this.cellSizeCm,
    required this.grid,
    this.startRow,
    this.startCol,
    this.startDirectionIndex = 0, // North by default
    required this.createdAt,
  });

  RoverDirection get startDirection =>
      RoverDirection.fromIndex(startDirectionIndex);

  bool get hasStart => startRow != null && startCol != null;

  /// Creates a blank empty grid
  factory GridMap.blank({
    required String id,
    required String name,
    required int rows,
    required int cols,
    required double cellSizeCm,
  }) {
    return GridMap(
      id: id,
      name: name,
      rows: rows,
      cols: cols,
      cellSizeCm: cellSizeCm,
      grid: List.generate(rows, (_) => List.filled(cols, 0)),
      createdAt: DateTime.now(),
    );
  }

  GridMap copyWith({
    String? name,
    double? cellSizeCm,
    RoverGrid? grid,
    int? startRow,
    int? startCol,
    int? startDirectionIndex,
    bool clearStart = false,
  }) {
    return GridMap(
      id: id,
      name: name ?? this.name,
      rows: rows,
      cols: cols,
      cellSizeCm: cellSizeCm ?? this.cellSizeCm,
      grid: grid ?? this.grid,
      startRow: clearStart ? null : (startRow ?? this.startRow),
      startCol: clearStart ? null : (startCol ?? this.startCol),
      startDirectionIndex:
          startDirectionIndex ?? this.startDirectionIndex,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rows': rows,
        'cols': cols,
        'cellSizeCm': cellSizeCm,
        'grid': grid,
        'startRow': startRow,
        'startCol': startCol,
        'startDirectionIndex': startDirectionIndex,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GridMap.fromJson(Map<String, dynamic> j) => GridMap(
        id: j['id'] as String,
        name: j['name'] as String,
        rows: j['rows'] as int,
        cols: j['cols'] as int,
        cellSizeCm: (j['cellSizeCm'] as num).toDouble(),
        grid: (j['grid'] as List)
            .map((r) => (r as List).map((e) => e as int).toList())
            .toList(),
        startRow: j['startRow'] as int?,
        startCol: j['startCol'] as int?,
        startDirectionIndex: j['startDirectionIndex'] as int? ?? 0,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  String toJsonString() => jsonEncode(toJson());
  factory GridMap.fromJsonString(String s) =>
      GridMap.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
