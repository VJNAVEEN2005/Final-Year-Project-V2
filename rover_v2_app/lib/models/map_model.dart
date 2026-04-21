import 'dart:convert';

/// 0 = empty cell, 1 = wall cell
typedef RoverGrid = List<List<int>>;

class Place {
  final String name;
  final int row;
  final int col;

  const Place({required this.name, required this.row, required this.col});

  Place copyWith({String? name, int? row, int? col}) => Place(
    name: name ?? this.name,
    row: row ?? this.row,
    col: col ?? this.col,
  );

  Map<String, dynamic> toJson() => {'name': name, 'row': row, 'col': col};

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    name: j['name'] as String? ?? '',
    row: j['row'] as int? ?? 0,
    col: j['col'] as int? ?? 0,
  );
}

/// Cardinal directions: 0=North, 1=East, 2=South, 3=West
enum RoverDirection {
  north,
  east,
  south,
  west;

  String get label {
    switch (this) {
      case north:
        return 'N';
      case east:
        return 'E';
      case south:
        return 'S';
      case west:
        return 'W';
    }
  }

  String get arrow {
    switch (this) {
      case north:
        return '↑';
      case east:
        return '→';
      case south:
        return '↓';
      case west:
        return '←';
    }
  }

  static RoverDirection fromIndex(int i) => RoverDirection.values[i % 4];
}

class GridMap {
  final String id;
  final String name;
  final int rows;
  final int cols;
  final double cellSizeCm; // physical size of each cell in centimeters
  final RoverGrid grid; // grid[row][col]: 0=empty, 1=wall
  final int? startRow;
  final int? startCol;
  final int startDirectionIndex; // RoverDirection index
  final List<Place> places;
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
    this.places = const [],
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
      places: const [],
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
    List<Place>? places,
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
      startDirectionIndex: startDirectionIndex ?? this.startDirectionIndex,
      places: places ?? this.places,
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
    'places': places.map((p) => p.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory GridMap.fromJson(Map<String, dynamic> j) {
    final rows = j['rows'] as int? ?? 0;
    final cols = j['cols'] as int? ?? 0;

    RoverGrid parsedGrid;
    try {
      final rawGrid = j['grid'];
      if (rawGrid is List) {
        parsedGrid = rawGrid.map((r) {
          if (r is List) {
            return r.map((e) => (e is num) ? e.toInt() : 0).toList();
          }
          return List.filled(cols, 0);
        }).toList();
      } else {
        parsedGrid = List.generate(rows, (_) => List.filled(cols, 0));
      }
    } catch (_) {
      parsedGrid = List.generate(rows, (_) => List.filled(cols, 0));
    }

    List<Place> parsedPlaces = [];
    try {
      final rawPlaces = j['places'];
      if (rawPlaces is List) {
        parsedPlaces = rawPlaces
            .map((p) {
              if (p is Map) {
                return Place.fromJson(Map<String, dynamic>.from(p));
              }
              return Place(name: '', row: 0, col: 0);
            })
            .where((p) => p.name.isNotEmpty)
            .toList();
      }
    } catch (_) {
      parsedPlaces = [];
    }

    return GridMap(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? 'Unnamed Map',
      rows: rows,
      cols: cols,
      cellSizeCm: (j['cellSizeCm'] as num? ?? 30.0).toDouble(),
      grid: parsedGrid,
      startRow: j['startRow'] as int?,
      startCol: j['startCol'] as int?,
      startDirectionIndex: j['startDirectionIndex'] as int? ?? 0,
      places: parsedPlaces,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory GridMap.fromJsonString(String s) =>
      GridMap.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
