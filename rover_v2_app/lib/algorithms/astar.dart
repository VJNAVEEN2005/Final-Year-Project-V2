/// A* pathfinding algorithm for the rover grid map.
///
/// Grid coordinates: grid[row][col]
/// Directions:  0=North (row-1), 1=East (col+1), 2=South (row+1), 3=West (col-1)
library;

import '../models/map_model.dart';

class PathCell {
  final int row;
  final int col;
  const PathCell(this.row, this.col);

  @override
  String toString() => '($row,$col)';

  @override
  bool operator ==(Object other) =>
      other is PathCell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}

class _ANode {
  final int row, col;
  final double g, h;
  final _ANode? parent;

  _ANode({
    required this.row,
    required this.col,
    required this.g,
    required this.h,
    this.parent,
  });

  double get f => g + h;
}

class AStarPathfinder {
  /// Returns the shortest path as a list of PathCell (start→goal inclusive),
  /// or null if no path exists.
  static List<PathCell>? findPath({
    required RoverGrid grid,
    required int startRow,
    required int startCol,
    required int goalRow,
    required int goalCol,
  }) {
    final rows = grid.length;
    final cols = grid[0].length;

    if (grid[goalRow][goalCol] == 1) return null; // goal is a wall
    if (startRow == goalRow && startCol == goalCol) return [PathCell(startRow, startCol)];

    final openSet = <_ANode>[];
    final closedKeys = <String>{};

    openSet.add(_ANode(
      row: startRow,
      col: startCol,
      g: 0,
      h: _manhattan(startRow, startCol, goalRow, goalCol),
    ));

    while (openSet.isNotEmpty) {
      // sort by f = g + h
      openSet.sort((a, b) => a.f.compareTo(b.f));
      final current = openSet.removeAt(0);

      final key = '${current.row},${current.col}';
      if (closedKeys.contains(key)) continue;
      closedKeys.add(key);

      if (current.row == goalRow && current.col == goalCol) {
        return _buildPath(current);
      }

      // 4-directional neighbors: N, E, S, W
      const dRows = [-1, 0, 1, 0];
      const dCols = [0, 1, 0, -1];

      for (int d = 0; d < 4; d++) {
        final nr = current.row + dRows[d];
        final nc = current.col + dCols[d];

        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        if (grid[nr][nc] == 1) continue;
        if (closedKeys.contains('$nr,$nc')) continue;

        openSet.add(_ANode(
          row: nr,
          col: nc,
          g: current.g + 1,
          h: _manhattan(nr, nc, goalRow, goalCol),
          parent: current,
        ));
      }
    }

    return null; // no path
  }

  static double _manhattan(int r1, int c1, int r2, int c2) =>
      ((r1 - r2).abs() + (c1 - c2).abs()).toDouble();

  static List<PathCell> _buildPath(_ANode node) {
    final path = <PathCell>[];
    _ANode? n = node;
    while (n != null) {
      path.insert(0, PathCell(n.row, n.col));
      n = n.parent;
    }
    return path;
  }

  /// Converts a path to executable MQTT commands.
  ///
  /// Returns a list like: ['turn_right', 'move:30.0', 'move:30.0', 'turn_left', 'move:30.0']
  ///
  /// Turn directions are:
  ///   - 'turn_left'  → rover turns 90° counter-clockwise
  ///   - 'turn_right' → rover turns 90° clockwise
  ///   - 'move:Xcm'   → rover moves forward X centimetres
  ///
  /// [startDirection] is the RoverDirection index (0=N,1=E,2=S,3=W)
  static List<String> pathToCommands({
    required List<PathCell> path,
    required int startDirection,
    required double cellSizeCm,
  }) {
    if (path.length < 2) return [];

    final commands = <String>[];
    int currentDir = startDirection; // 0=N,1=E,2=S,3=W

    for (int i = 1; i < path.length; i++) {
      final dRow = path[i].row - path[i - 1].row;
      final dCol = path[i].col - path[i - 1].col;

      // Determine required direction from cell delta
      int requiredDir;
      if (dRow == -1 && dCol == 0) requiredDir = 0;      // North
      else if (dRow == 0 && dCol == 1) requiredDir = 1;  // East
      else if (dRow == 1 && dCol == 0) requiredDir = 2;  // South
      else requiredDir = 3;                               // West

      // Compute minimum turns needed
      // Use 90 degree turn commands for precise turning
      final diff = (requiredDir - currentDir + 4) % 4;
      if (diff == 1) {
        commands.add('right90');
      } else if (diff == 3) {
        commands.add('left90');
      } else if (diff == 2) {
        commands.add('right90');
        commands.add('right90');
      }
      currentDir = requiredDir;

      // Move one cell forward
      commands.add('move:${cellSizeCm.toStringAsFixed(1)}');
    }

    return commands;
  }
}
