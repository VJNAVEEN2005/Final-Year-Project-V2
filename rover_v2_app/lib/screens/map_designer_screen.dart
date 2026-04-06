import 'package:flutter/material.dart';
import '../models/map_model.dart';
import '../services/map_service.dart';
import '../theme/rover_theme.dart';

enum _Tool { wall, erase, start }

class MapDesignerScreen extends StatefulWidget {
  final GridMap map;
  final bool isNew;

  const MapDesignerScreen({super.key, required this.map, required this.isNew});

  @override
  State<MapDesignerScreen> createState() => _MapDesignerScreenState();
}

class _MapDesignerScreenState extends State<MapDesignerScreen> {
  late GridMap _map;
  _Tool _tool = _Tool.wall;

  // Cell pixel size for display
  static const double _cellPx = 38.0;

  @override
  void initState() {
    super.initState();
    _map = widget.map;
  }

  // ── Grid interaction ──────────────────────────────────────────────────────

  void _handleTap(int row, int col) {
    if (row < 0 || row >= _map.rows || col < 0 || col >= _map.cols) return;
    setState(() {
      switch (_tool) {
        case _Tool.wall:
          // toggle
          final grid = _deepCopyGrid();
          grid[row][col] = grid[row][col] == 1 ? 0 : 1;
          _map = _map.copyWith(grid: grid);
        case _Tool.erase:
          final grid = _deepCopyGrid();
          grid[row][col] = 0;
          _map = _map.copyWith(grid: grid);
        case _Tool.start:
          _showDirectionPicker(row, col);
      }
    });
  }

  void _handleDrag(int row, int col) {
    if (row < 0 || row >= _map.rows || col < 0 || col >= _map.cols) return;
    if (_tool == _Tool.start) return; // start is tap-only
    setState(() {
      final grid = _deepCopyGrid();
      grid[row][col] = _tool == _Tool.wall ? 1 : 0;
      _map = _map.copyWith(grid: grid);
    });
  }

  RoverGrid _deepCopyGrid() =>
      _map.grid.map((r) => List<int>.from(r)).toList();

  void _showDirectionPicker(int row, int col) {
    showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Rover Facing Direction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: RoverDirection.values.map((d) {
            return ListTile(
              leading: Text(d.arrow, style: const TextStyle(fontSize: 24)),
              title: Text(d.name.toUpperCase()),
              onTap: () => Navigator.pop(context, d.index),
            );
          }).toList(),
        ),
      ),
    ).then((dirIdx) {
      if (dirIdx == null) return;
      setState(() {
        final grid = _deepCopyGrid();
        // Clear wall at start cell
        grid[row][col] = 0;
        _map = _map.copyWith(
          grid: grid,
          startRow: row,
          startCol: col,
          startDirectionIndex: dirIdx,
        );
      });
    });
  }

  Future<void> _save() async {
    if (widget.isNew) {
      await MapService.save(_map);
    } else {
      await MapService.update(_map);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Map "${_map.name}" saved!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, _map);
    }
  }

  void _clearAll() {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Clear Map'),
        content: const Text('Remove all walls and reset start point?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        setState(() {
          _map = GridMap.blank(
            id: _map.id,
            name: _map.name,
            rows: _map.rows,
            cols: _map.cols,
            cellSizeCm: _map.cellSizeCm,
          );
        });
      }
    });
  }

  // ── Hit testing ───────────────────────────────────────────────────────────

  (int, int) _posToCell(Offset local) {
    final row = (local.dy / _cellPx).floor();
    final col = (local.dx / _cellPx).floor();
    return (row, col);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridW = _map.cols * _cellPx;
    final gridH = _map.rows * _cellPx;
    final totalWm = (_map.cols * _map.cellSizeCm / 100).toStringAsFixed(1);
    final totalHm = (_map.rows * _map.cellSizeCm / 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_map.name, style: theme.textTheme.titleLarge?.copyWith(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.orange),
            tooltip: 'Clear all',
            onPressed: _clearAll,
          ),
          IconButton(
            icon: const Icon(Icons.save_rounded, color: RoverTheme.primary),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Measurement banner ─────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: RoverTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RoverTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat(Icons.grid_on_rounded, 'Grid', '${_map.rows}×${_map.cols}'),
                _stat(Icons.straighten_rounded, 'Cell', '${_map.cellSizeCm.toInt()} cm'),
                _stat(Icons.aspect_ratio_rounded, 'Area', '${totalWm}m × ${totalHm}m'),
                if (_map.hasStart)
                  _stat(Icons.navigation_rounded, 'Start', '${_map.startDirection.arrow} (${_map.startRow},${_map.startCol})'),
              ],
            ),
          ),

          // ── Grid canvas ───────────────────────────────────────────────────
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.5,
              maxScale: 3.0,
              child: GestureDetector(
                onTapDown: (d) {
                  final (r, c) = _posToCell(d.localPosition);
                  _handleTap(r, c);
                },
                onPanUpdate: (d) {
                  final (r, c) = _posToCell(d.localPosition);
                  _handleDrag(r, c);
                },
                child: CustomPaint(
                  size: Size(gridW, gridH),
                  painter: _GridPainter(
                    map: _map,
                    cellPx: _cellPx,
                  ),
                ),
              ),
            ),
          ),

          // ── Tool palette ──────────────────────────────────────────────────
          _buildToolbar(theme),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: RoverTheme.primary),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 9, letterSpacing: 1, color: RoverTheme.secondary)),
      ]),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: RoverTheme.primary)),
    ]);
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RoverTheme.surfaceContainerLow,
        border: const Border(top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _toolBtn(_Tool.wall, Icons.grid_4x4_rounded, 'WALL', Colors.red.shade700),
          _toolBtn(_Tool.erase, Icons.auto_fix_high_rounded, 'ERASE', Colors.grey),
          _toolBtn(_Tool.start, Icons.navigation_rounded, 'START', Colors.orange),
        ],
      ),
    );
  }

  Widget _toolBtn(_Tool tool, IconData icon, String label, Color color) {
    final active = _tool == tool;
    return GestureDetector(
      onTap: () => setState(() => _tool = tool),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Colors.transparent, width: 1.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? color : RoverTheme.secondary, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? color : RoverTheme.secondary)),
        ]),
      ),
    );
  }
}

// ── Grid Painter ───────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final GridMap map;
  final double cellPx;

  _GridPainter({required this.map, required this.cellPx});

  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()..color = const Color(0xFF8B4513).withOpacity(0.85);
    final emptyPaint = Paint()..color = const Color(0xFF1E1E2E);
    final gridLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    final startPaint = Paint()..color = Colors.orange;
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw cells
    for (int r = 0; r < map.rows; r++) {
      for (int c = 0; c < map.cols; c++) {
        final rect = Rect.fromLTWH(c * cellPx, r * cellPx, cellPx, cellPx);
        canvas.drawRect(rect, map.grid[r][c] == 1 ? wallPaint : emptyPaint);
        canvas.drawRect(rect, gridLinePaint);
      }
    }

    // Draw start cell
    if (map.hasStart) {
      final sr = map.startRow!;
      final sc = map.startCol!;
      final rect = Rect.fromLTWH(sc * cellPx + 2, sr * cellPx + 2, cellPx - 4, cellPx - 4);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), startPaint);

      // Draw direction arrow text
      final textPainter = TextPainter(
        text: TextSpan(
          text: map.startDirection.arrow,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(sc * cellPx + (cellPx - textPainter.width) / 2, sr * cellPx + (cellPx - textPainter.height) / 2),
      );
    }

    // Draw outer border
    canvas.drawRect(Rect.fromLTWH(0, 0, map.cols * cellPx, map.rows * cellPx), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.map != map || old.cellPx != cellPx;
}
