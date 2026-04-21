import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/map_model.dart';
import '../services/svg_service.dart';
import '../services/map_service.dart';
import '../services/mqtt_service.dart';
import '../theme/rover_theme.dart';
import 'map_designer_screen.dart';
import 'map_navigator_screen.dart';

enum SvgTool {
  select,
  rectangle,
  circle,
  line,
  polygon,
  eraser,
  startPoint,
  endPoint,
}

class SvgShape {
  String id;
  SvgTool type;
  Offset p1;
  Offset p2;
  List<Offset> points;
  bool isFilled;

  SvgShape({
    required this.id,
    required this.type,
    required this.p1,
    required this.p2,
    this.points = const [],
    this.isFilled = true,
  });

  SvgShape copy() {
    return SvgShape(
      id: id,
      type: type,
      p1: p1,
      p2: p2,
      points: List.from(points),
      isFilled: isFilled,
    );
  }

  bool containsPoint(Offset point, {double tolerance = 5.0}) {
    switch (type) {
      case SvgTool.rectangle:
        final rect = Rect.fromPoints(p1, p2);
        return rect.contains(point);
      case SvgTool.circle:
        final center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final radius = (p2 - p1).distance / 2;
        return (point - center).distance <= radius + tolerance;
      case SvgTool.line:
        return _distanceToLine(p1, p2, point) <= tolerance;
      case SvgTool.polygon:
        if (points.length < 3) return false;
        return _isPointInPolygon(point);
      case SvgTool.select:
      case SvgTool.eraser:
      case SvgTool.startPoint:
      case SvgTool.endPoint:
        return false;
    }
  }

  double _distanceToLine(Offset start, Offset end, Offset point) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) return (point - start).distance;
    var t =
        ((point.dx - start.dx) * dx + (point.dy - start.dy) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    final projection = Offset(start.dx + t * dx, start.dy + t * dy);
    return (point - projection).distance;
  }

  bool _isPointInPolygon(Offset point) {
    var inside = false;
    for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
      if ((points[i].dy > point.dy) != (points[j].dy > point.dy) &&
          point.dx <
              (points[j].dx - points[i].dx) *
                      (point.dy - points[i].dy) /
                      (points[j].dy - points[i].dy) +
                  points[i].dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class SvgEditorScreen extends StatefulWidget {
  final String? initialName;

  const SvgEditorScreen({super.key, this.initialName});

  @override
  State<SvgEditorScreen> createState() => _SvgEditorScreenState();
}

class _SvgEditorScreenState extends State<SvgEditorScreen> {
  late TextEditingController _nameController;
  final List<SvgShape> _shapes = [];
  SvgTool _activeTool = SvgTool.select;
  SvgShape? _selectedShape;
  int _shapeCounter = 0;

  // Drawing state
  bool _isDrawing = false;
  Offset? _drawStart;
  Offset? _drawCurrent;
  final List<Offset> _polygonPoints = [];

  // Canvas settings
  double _canvasWidth = 800;
  double _canvasHeight = 600;
  double _cellSizeCm = 30.0;
  double _physicalWidthCm = 1000;
  double _physicalHeightCm = 800;
  int _padding = 1;

  // Start and End points
  Offset? _startPoint;
  Offset? _endPoint;
  RoverDirection? _startDirection = RoverDirection.east;

  // Undo/Redo
  final List<List<SvgShape>> _undoStack = [];
  final List<List<SvgShape>> _redoStack = [];

  // View
  final TransformationController _transformController =
      TransformationController();
  bool _showGrid = true;
  bool _snapToGrid = true;
  final double _gridSize = 20;

  // MQTT Navigation
  final MqttService _mqtt = MqttService.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialName ?? 'Factory Layout',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  // ─── Undo/Redo ──────────────────────────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(_shapes.map((s) => s.copy()).toList());
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_shapes.map((s) => s.copy()).toList());
    _shapes.clear();
    _shapes.addAll(_undoStack.removeLast());
    _selectedShape = null;
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_shapes.map((s) => s.copy()).toList());
    _shapes.clear();
    _shapes.addAll(_redoStack.removeLast());
    _selectedShape = null;
    setState(() {});
  }

  // ─── Grid Snapping ─────────────────────────────────────────────────────────

  Offset _snap(Offset point) {
    if (!_snapToGrid) return point;
    return Offset(
      (point.dx / _gridSize).round() * _gridSize,
      (point.dy / _gridSize).round() * _gridSize,
    );
  }

  // ─── Shape Management ──────────────────────────────────────────────────────

  void _addShape(SvgShape shape) {
    _pushUndo();
    setState(() => _shapes.add(shape));
  }

  void _deleteSelected() {
    if (_selectedShape == null) return;
    _pushUndo();
    setState(() {
      _shapes.removeWhere((s) => s.id == _selectedShape!.id);
      _selectedShape = null;
    });
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Clear Canvas'),
        content: const Text('Remove all shapes? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _pushUndo();
              setState(() {
                _shapes.clear();
                _selectedShape = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── Canvas Interaction ────────────────────────────────────────────────────

  void _onTapDown(TapDownDetails details) {
    final pos = _snap(details.localPosition);

    setState(() {
      switch (_activeTool) {
        case SvgTool.select:
          _selectShapeAt(pos);
          break;
        case SvgTool.rectangle:
        case SvgTool.circle:
        case SvgTool.line:
          _isDrawing = true;
          _drawStart = pos;
          _drawCurrent = pos;
          break;
        case SvgTool.polygon:
          _polygonPoints.add(pos);
          break;
        case SvgTool.eraser:
          _eraseAt(pos);
          break;
        case SvgTool.startPoint:
          _startPoint = pos;
          _showStartDirectionPicker(pos);
          break;
        case SvgTool.endPoint:
          _endPoint = pos;
          break;
      }
    });
  }

  void _showStartDirectionPicker(Offset pos) {
    showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Rover Starting Direction'),
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
      if (dirIdx != null && mounted) {
        setState(() {
          _startDirection = RoverDirection.values[dirIdx];
        });
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDrawing) return;
    setState(() => _drawCurrent = _snap(details.localPosition));
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDrawing || _drawStart == null || _drawCurrent == null) {
      _isDrawing = false;
      return;
    }

    final dist = (_drawCurrent! - _drawStart!).distance;
    if (dist > 5) {
      _addShape(
        SvgShape(
          id: 'shape_${_shapeCounter++}',
          type: _activeTool,
          p1: _drawStart!,
          p2: _drawCurrent!,
        ),
      );
    }

    setState(() {
      _isDrawing = false;
      _drawStart = null;
      _drawCurrent = null;
    });
  }

  void _onDoubleTap() {
    if (_activeTool == SvgTool.polygon && _polygonPoints.length >= 3) {
      // Find bounds
      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;
      for (final p in _polygonPoints) {
        minX = min(minX, p.dx);
        maxX = max(maxX, p.dx);
        minY = min(minY, p.dy);
        maxY = max(maxY, p.dy);
      }

      _addShape(
        SvgShape(
          id: 'shape_${_shapeCounter++}',
          type: SvgTool.polygon,
          p1: Offset(minX, minY),
          p2: Offset(maxX, maxY),
          points: List.from(_polygonPoints),
        ),
      );

      setState(() => _polygonPoints.clear());
    }
  }

  void _selectShapeAt(Offset pos) {
    _selectedShape = null;
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_shapes[i].containsPoint(pos)) {
        _selectedShape = _shapes[i];
        break;
      }
    }
  }

  void _eraseAt(Offset pos) {
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_shapes[i].containsPoint(pos, tolerance: 10)) {
        _pushUndo();
        setState(() => _shapes.removeAt(i));
        break;
      }
    }
  }

  // ─── Navigation ────────────────────────────────────────────────────────────

  Future<void> _navigateToDestination() async {
    if (_startPoint == null || _endPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set both start and end points first!'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_mqtt.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MQTT not connected! Please check connection.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Convert to GridMap first
      final tempDir = await getTemporaryDirectory();
      final svgFile = File(
        '${tempDir.path}/layout_nav_${DateTime.now().millisecondsSinceEpoch}.svg',
      );
      final svgContent = _generateSvg();
      await svgFile.writeAsString(svgContent);

      if (!mounted) return;

      final svgService = SvgService();
      final map = svgService.convertSvgToGridMap(
        file: svgFile,
        mapName: _nameController.text.trim(),
        cellSizeCm: _cellSizeCm,
        physicalWidthCm: _physicalWidthCm,
        physicalHeightCm: _physicalHeightCm,
        padding: _padding,
      );

      await svgFile.delete();

      // Convert start/end points to grid coordinates
      final startCol = ((_startPoint!.dx / _canvasWidth) * map.cols)
          .round()
          .clamp(0, map.cols - 1);
      final startRow = ((_startPoint!.dy / _canvasHeight) * map.rows)
          .round()
          .clamp(0, map.rows - 1);
      final endCol = ((_endPoint!.dx / _canvasWidth) * map.cols).round().clamp(
        0,
        map.cols - 1,
      );
      final endRow = ((_endPoint!.dy / _canvasHeight) * map.rows).round().clamp(
        0,
        map.rows - 1,
      );

      // Update map with start/end
      final grid = map.grid.map((r) => List<int>.from(r)).toList();
      grid[startRow][startCol] = 0; // Ensure start is walkable
      grid[endRow][endCol] = 0; // Ensure end is walkable

      final updatedMap = map.copyWith(
        grid: grid,
        startRow: startRow,
        startCol: startCol,
        startDirectionIndex: _startDirection?.index ?? 0,
      );

      if (!mounted) return;

      // Navigate to MapNavigatorScreen
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MapNavigatorScreen(map: updatedMap)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigation error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveAndConvert() async {
    if (_shapes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Canvas is empty! Draw some shapes first.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Create temporary SVG file
      final tempDir = await getTemporaryDirectory();
      final svgFile = File(
        '${tempDir.path}/layout_${DateTime.now().millisecondsSinceEpoch}.svg',
      );

      final svgContent = _generateSvg();
      await svgFile.writeAsString(svgContent);

      if (!mounted) return;

      // Convert to GridMap
      final svgService = SvgService();
      final map = svgService.convertSvgToGridMap(
        file: svgFile,
        mapName: _nameController.text.trim(),
        cellSizeCm: _cellSizeCm,
        physicalWidthCm: _physicalWidthCm,
        physicalHeightCm: _physicalHeightCm,
        padding: _padding,
      );

      // Delete temp file
      await svgFile.delete();

      if (!mounted) return;

      // Open in Map Designer for final adjustments
      final saved = await Navigator.push<GridMap>(
        context,
        MaterialPageRoute(
          builder: (_) => MapDesignerScreen(map: map, isNew: true),
        ),
      );

      if (saved != null && mounted) {
        await MapService.save(saved);
        Navigator.pop(context, saved);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _generateSvg() {
    final buffer = StringBuffer();
    buffer.writeln(
      '<svg width="${_canvasWidth.toInt()}" height="${_canvasHeight.toInt()}" xmlns="http://www.w3.org/2000/svg">',
    );

    for (final shape in _shapes) {
      switch (shape.type) {
        case SvgTool.rectangle:
          final x = min(shape.p1.dx, shape.p2.dx);
          final y = min(shape.p1.dy, shape.p2.dy);
          final w = (shape.p2.dx - shape.p1.dx).abs();
          final h = (shape.p2.dy - shape.p1.dy).abs();
          buffer.writeln(
            '<rect x="${x.toInt()}" y="${y.toInt()}" width="${w.toInt()}" height="${h.toInt()}" fill="black"/>',
          );
          break;
        case SvgTool.circle:
          final cx = (shape.p1.dx + shape.p2.dx) / 2;
          final cy = (shape.p1.dy + shape.p2.dy) / 2;
          final r = (shape.p2 - shape.p1).distance / 2;
          buffer.writeln(
            '<circle cx="${cx.toInt()}" cy="${cy.toInt()}" r="${r.toInt()}" fill="black"/>',
          );
          break;
        case SvgTool.line:
          buffer.writeln(
            '<line x1="${shape.p1.dx.toInt()}" y1="${shape.p1.dy.toInt()}" x2="${shape.p2.dx.toInt()}" y2="${shape.p2.dy.toInt()}" stroke="black" stroke-width="3"/>',
          );
          break;
        case SvgTool.polygon:
          if (shape.points.isNotEmpty) {
            final points = shape.points
                .map((p) => '${p.dx.toInt()},${p.dy.toInt()}')
                .join(' ');
            buffer.writeln('<polygon points="$points" fill="black"/>');
          }
          break;
        default:
          break;
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  // ─── Settings Dialog ──────────────────────────────────────────────────────

  void _showSettings() {
    final widthCtrl = TextEditingController(text: _physicalWidthCm.toString());
    final heightCtrl = TextEditingController(
      text: _physicalHeightCm.toString(),
    );
    final cellCtrl = TextEditingController(text: _cellSizeCm.toString());
    bool snap = _snapToGrid;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: RoverTheme.surfaceContainerHigh,
          title: const Text('Canvas Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Physical Width (cm)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: heightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Physical Height (cm)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cellCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cell Size (cm)',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Snap to Grid'),
                    const Spacer(),
                    Switch(value: snap, onChanged: (v) => set(() => snap = v)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final w = double.tryParse(widthCtrl.text);
                final h = double.tryParse(heightCtrl.text);
                final c = double.tryParse(cellCtrl.text);
                if (w != null && h != null && c != null) {
                  setState(() {
                    _physicalWidthCm = w;
                    _physicalHeightCm = h;
                    _cellSizeCm = c;
                    _snapToGrid = snap;
                  });
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: RoverTheme.primary,
              ),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoverTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.draw_rounded, color: RoverTheme.primary, size: 20),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _nameController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Layout Name',
                ),
              ),
            ),
          ],
        ),
        actions: [
          // MQTT Status Indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _mqtt.isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _mqtt.isConnected
                      ? Icons.wifi_rounded
                      : Icons.wifi_off_rounded,
                  size: 14,
                  color: _mqtt.isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _mqtt.isConnected ? 'MQTT' : 'Offline',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _mqtt.isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          // Action buttons
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            onPressed: _undoStack.isEmpty ? null : _undo,
            tooltip: 'Undo',
            color: _undoStack.isEmpty ? Colors.grey : Colors.white70,
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded),
            onPressed: _redoStack.isEmpty ? null : _redo,
            tooltip: 'Redo',
            color: _redoStack.isEmpty ? Colors.grey : Colors.white70,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: _clearAll,
            tooltip: 'Clear All',
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          // Navigate button
          ElevatedButton.icon(
            onPressed:
                (_startPoint != null && _endPoint != null && _mqtt.isConnected)
                ? _navigateToDestination
                : null,
            icon: const Icon(Icons.navigation_rounded, size: 18),
            label: const Text('Navigate', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          // Save button
          ElevatedButton.icon(
            onPressed: _shapes.isNotEmpty ? _saveAndConvert : null,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: RoverTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          _buildToolbar(),

          // Canvas
          Expanded(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.1,
              maxScale: 10.0,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(100),
              panEnabled: true,
              scaleEnabled: true,
              child: Center(
                child: GestureDetector(
                  onTapDown: _onTapDown,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onDoubleTap: _onDoubleTap,
                  child: Container(
                    width: _canvasWidth,
                    height: _canvasHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      border: Border.all(
                        color: RoverTheme.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: CustomPaint(
                      painter: _SvgCanvasPainter(
                        shapes: _shapes,
                        selectedShape: _selectedShape,
                        startPoint: _startPoint,
                        endPoint: _endPoint,
                        startDirection: _startDirection,
                        drawStart: _drawStart,
                        drawCurrent: _drawCurrent,
                        polygonPoints: _polygonPoints,
                        activeTool: _activeTool,
                        showGrid: _showGrid,
                        gridSize: _gridSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // Bottom status bar
      bottomNavigationBar: _buildStatusBar(),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: RoverTheme.surfaceContainerLow,
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolButton(SvgTool.select, Icons.touch_app_rounded, 'Select'),
            const SizedBox(width: 6),
            _toolButton(SvgTool.rectangle, Icons.crop_free_rounded, 'Rect'),
            const SizedBox(width: 6),
            _toolButton(SvgTool.circle, Icons.circle_outlined, 'Circle'),
            const SizedBox(width: 6),
            _toolButton(SvgTool.line, Icons.show_chart_rounded, 'Line'),
            const SizedBox(width: 6),
            _toolButton(
              SvgTool.polygon,
              Icons.change_history_rounded,
              'Polygon',
            ),
            const SizedBox(width: 6),
            _toolButton(SvgTool.eraser, Icons.auto_fix_high_rounded, 'Eraser'),
            const SizedBox(width: 12),
            Container(width: 1, height: 36, color: Colors.white24),
            const SizedBox(width: 12),
            _toolButton(
              SvgTool.startPoint,
              Icons.play_arrow_rounded,
              'Start',
              color: Colors.orange,
            ),
            const SizedBox(width: 6),
            _toolButton(
              SvgTool.endPoint,
              Icons.flag_rounded,
              'End',
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Icon(Icons.grid_on_rounded, size: 14, color: RoverTheme.primary),
          const SizedBox(width: 6),
          Text(
            '${_canvasWidth.toInt()}×${_canvasHeight.toInt()} | ',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Icon(Icons.widgets_rounded, size: 14, color: RoverTheme.primary),
          const SizedBox(width: 6),
          Text(
            '${_shapes.length} shapes | ',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const Spacer(),
          Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            'Pinch to zoom • Drag to pan',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(
    SvgTool tool,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final isActive = _activeTool == tool;
    final toolColor = color ?? (isActive ? RoverTheme.primary : Colors.white70);
    return GestureDetector(
      onTap: () => setState(() => _activeTool = tool),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? toolColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? toolColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: toolColor, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: toolColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Canvas Painter ─────────────────────────────────────────────────────────

class _SvgCanvasPainter extends CustomPainter {
  final List<SvgShape> shapes;
  final SvgShape? selectedShape;
  final Offset? startPoint;
  final Offset? endPoint;
  final RoverDirection? startDirection;
  final Offset? drawStart;
  final Offset? drawCurrent;
  final List<Offset> polygonPoints;
  final SvgTool activeTool;
  final bool showGrid;
  final double gridSize;

  _SvgCanvasPainter({
    required this.shapes,
    this.selectedShape,
    this.startPoint,
    this.endPoint,
    this.startDirection,
    this.drawStart,
    this.drawCurrent,
    this.polygonPoints = const [],
    required this.activeTool,
    this.showGrid = true,
    this.gridSize = 20,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.05)
        ..strokeWidth = 0.5;

      for (double x = 0; x <= size.width; x += gridSize) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y <= size.height; y += gridSize) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Draw shapes
    for (final shape in shapes) {
      final isSelected = shape.id == selectedShape?.id;
      _drawShape(canvas, shape, isSelected);
    }

    // Draw current drawing
    if (drawStart != null && drawCurrent != null) {
      final previewShape = SvgShape(
        id: 'preview',
        type: activeTool,
        p1: drawStart!,
        p2: drawCurrent!,
        points: activeTool == SvgTool.polygon ? polygonPoints : [],
      );
      _drawShape(canvas, previewShape, false, isPreview: true);
    }

    // Draw polygon points in progress
    if (activeTool == SvgTool.polygon && polygonPoints.isNotEmpty) {
      _drawPolygonInProgress(canvas);
    }

    // Draw start point
    if (startPoint != null) {
      _drawStartPoint(canvas, startPoint!, startDirection);
    }

    // Draw end point
    if (endPoint != null) {
      _drawEndPoint(canvas, endPoint!);
    }
  }

  void _drawStartPoint(Canvas canvas, Offset pos, RoverDirection? direction) {
    // Outer glow
    final glowPaint = Paint()
      ..color = Colors.orange.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 20, glowPaint);

    // Outer circle
    final outerPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 14, outerPaint);

    // Inner circle
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 9, innerPaint);

    // Direction arrow
    if (direction != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: direction.arrow,
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
      );
    }

    // Label
    _drawLabel(canvas, 'START', pos, Colors.orange);
  }

  void _drawEndPoint(Canvas canvas, Offset pos) {
    // Outer glow
    final glowPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 20, glowPaint);

    // Outer circle
    final outerPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 14, outerPaint);

    // Inner circle
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 9, innerPaint);

    // Flag icon
    final textPainter = TextPainter(
      text: const TextSpan(text: '🏁', style: TextStyle(fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );

    // Label
    _drawLabel(canvas, 'END', pos, Colors.green);
  }

  void _drawLabel(Canvas canvas, String label, Offset pos, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - 22),
    );
  }

  void _drawShape(
    Canvas canvas,
    SvgShape shape,
    bool isSelected, {
    bool isPreview = false,
  }) {
    final paint = Paint()
      ..color = isPreview ? Colors.blue.withOpacity(0.5) : Colors.black
      ..style = shape.isFilled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = isSelected ? 3 : 2;

    final borderPaint = Paint()
      ..color = isSelected ? Colors.blue : Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 3 : 2;

    switch (shape.type) {
      case SvgTool.rectangle:
        final rect = Rect.fromPoints(shape.p1, shape.p2);
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, borderPaint);
        break;

      case SvgTool.circle:
        final center = Offset(
          (shape.p1.dx + shape.p2.dx) / 2,
          (shape.p1.dy + shape.p2.dy) / 2,
        );
        final radius = (shape.p2 - shape.p1).distance / 2;
        canvas.drawCircle(center, radius, paint);
        canvas.drawCircle(center, radius, borderPaint);
        break;

      case SvgTool.line:
        canvas.drawLine(shape.p1, shape.p2, borderPaint);
        break;

      case SvgTool.polygon:
        if (shape.points.length >= 3) {
          final path = Path()..moveTo(shape.points[0].dx, shape.points[0].dy);
          for (int i = 1; i < shape.points.length; i++) {
            path.lineTo(shape.points[i].dx, shape.points[i].dy);
          }
          path.close();
          canvas.drawPath(path, paint);
          canvas.drawPath(path, borderPaint);
        }
        break;

      default:
        break;
    }

    // Draw selection handles
    if (isSelected && !isPreview) {
      _drawHandles(canvas, shape);
    }
  }

  void _drawHandles(Canvas canvas, SvgShape shape) {
    final handlePaint = Paint()..color = Colors.blue;
    final handleSize = 8.0;

    List<Offset> handlePositions = [];
    switch (shape.type) {
      case SvgTool.rectangle:
      case SvgTool.circle:
        handlePositions = [shape.p1, shape.p2];
        break;
      case SvgTool.line:
        handlePositions = [shape.p1, shape.p2];
        break;
      case SvgTool.polygon:
        handlePositions = shape.points;
        break;
      default:
        break;
    }

    for (final pos in handlePositions) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: handleSize, height: handleSize),
          const Radius.circular(2),
        ),
        handlePaint,
      );
    }
  }

  void _drawPolygonInProgress(Canvas canvas) {
    if (polygonPoints.isEmpty) return;

    final pointPaint = Paint()..color = Colors.orange;
    final linePaint = Paint()
      ..color = Colors.orange.withOpacity(0.7)
      ..strokeWidth = 2;

    // Draw points
    for (final point in polygonPoints) {
      canvas.drawCircle(point, 4, pointPaint);
    }

    // Draw lines
    if (polygonPoints.length > 1) {
      for (int i = 0; i < polygonPoints.length - 1; i++) {
        canvas.drawLine(polygonPoints[i], polygonPoints[i + 1], linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SvgCanvasPainter old) {
    return old.shapes != shapes ||
        old.selectedShape != selectedShape ||
        old.startPoint != startPoint ||
        old.endPoint != endPoint ||
        old.startDirection != startDirection ||
        old.drawStart != drawStart ||
        old.drawCurrent != drawCurrent ||
        old.polygonPoints != polygonPoints ||
        old.activeTool != activeTool;
  }
}
