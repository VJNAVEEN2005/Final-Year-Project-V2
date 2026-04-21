import 'dart:async';
import 'package:flutter/material.dart';
import '../algorithms/astar.dart';
import '../models/map_model.dart';
import '../services/mqtt_service.dart';
import '../theme/rover_theme.dart';
import 'live_navigation_screen.dart';

enum _NavState { idle, running, done, error }

class MapNavigatorScreen extends StatefulWidget {
  final GridMap map;
  const MapNavigatorScreen({super.key, required this.map});

  @override
  State<MapNavigatorScreen> createState() => _MapNavigatorScreenState();
}

class _MapNavigatorScreenState extends State<MapNavigatorScreen> {
  late GridMap _map;

  Place? _selectedPlace;

  // Current position (rover location)
  int? _currentRow;
  int? _currentCol;
  bool _currentSet = false;

  // Real-time heading from gyroscope
  double _currentHeading = 0;

  // Destination
  int? _destRow, _destCol;

  // Path state
  List<PathCell>? _path;
  List<String> _commands = [];
  int _currentCommandIdx = 0;
  int _currentPathIdx = 0;

  // Execution state
  _NavState _state = _NavState.idle;
  String _statusText = 'Set current position → Select destination → Navigate';
  Completer<void>? _movementCompleter;
  bool _cancelRequested = false;

  // Settings
  int _turnDurationMs = 700;

  // MQTT
  final MqttService _mqtt = MqttService.instance;
  StreamSubscription<String>? _dataSub;
  bool _isConnected = false;

  static const double _cellPx = 42.0;

  @override
  void initState() {
    super.initState();
    _map = widget.map;
    _currentRow = _map.startRow;
    _currentCol = _map.startCol;
    _currentSet = _map.hasStart;
    _isConnected = _mqtt.isConnected;
    _dataSub = _mqtt.dataStream.listen(_onMqttData);
    _mqtt.connectionStream.listen((v) {
      if (mounted) setState(() => _isConnected = v);
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    if (_state == _NavState.running) _mqtt.publish('stop');
    super.dispose();
  }

  void _onMqttData(String data) {
    if (data == 'done') {
      _movementCompleter?.complete();
      return;
    }
    // Parse telemetry for heading
    for (final part in data.split(',')) {
      if (part.startsWith('yaw:')) {
        final yaw = double.tryParse(part.substring(4));
        if (yaw != null) {
          setState(() => _currentHeading = yaw);
        }
      }
    }
  }

  // Set current position
  void _setCurrentPosition(int row, int col) {
    if (row < 0 || row >= _map.rows || col < 0 || col >= _map.cols) return;
    if (_map.grid[row][col] == 1) return;
    setState(() {
      _currentRow = row;
      _currentCol = col;
      _currentSet = true;
      _path = null;
      _commands = [];
      _statusText = 'Current: ($row, $col) → Set destination';
    });
  }

  // Select destination
  void _setDestination(int row, int col, {Place? place}) {
    if (row < 0 || row >= _map.rows || col < 0 || col >= _map.cols) return;
    if (_map.grid[row][col] == 1) return;
    setState(() {
      _destRow = row;
      _destCol = col;
      _selectedPlace = place;
      _path = null;
      _commands = [];
      if (place != null) {
        _statusText = 'Current: ($_currentRow, $_currentCol) → ${place.name}';
      } else {
        _statusText = 'Current: ($_currentRow, $_currentCol) → ($row, $col)';
      }
    });
  }

  void _clearDestination() {
    setState(() {
      _destRow = null;
      _destCol = null;
      _selectedPlace = null;
      _path = null;
      _commands = [];
      _statusText = _currentSet
          ? 'Current: ($_currentRow, $_currentCol) → Set destination'
          : 'Set current position first';
    });
  }

  // ── Place selection ─────────────────────────────────────────────────────

  void _showPlaceSelector() {
    if (_map.places.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: RoverTheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Destination',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _map.places
                  .map(
                    (p) => ActionChip(
                      avatar: const Icon(Icons.place_rounded, size: 18),
                      label: Text(p.name),
                      backgroundColor: _selectedPlace?.name == p.name
                          ? RoverTheme.primary.withOpacity(0.2)
                          : null,
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedPlace = p;
                          _destRow = p.row;
                          _destCol = p.col;
                          _path = null;
                          _commands = [];
                          _state = _NavState.idle;
                          _statusText =
                              'Destination: ${p.name}. Tap FIND PATH.';
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Position selection ───────────────────────────────────────────────────

  void _onCellTap(int row, int col) {
    if (_state == _NavState.running) return;
    if (row < 0 || row >= _map.rows || col < 0 || col >= _map.cols) return;
    if (_map.grid[row][col] == 1) return;

    if (!_currentSet) {
      _setCurrentPosition(row, col);
      return;
    }

    if (_destRow == null) {
      if (row == _currentRow && col == _currentCol) return;
      _setDestination(row, col);
      return;
    }

    setState(() {
      _destRow = row;
      _destCol = col;
      _selectedPlace = null;
      _path = null;
      _commands = [];
      _statusText = 'Current: ($_currentRow, $_currentCol) → ($row, $col)';
    });
  }

  // ── A* Path Finding ─────────────────────────────────────────────────────────

  void _findPath() {
    if (!_currentSet || _destRow == null) return;
    final path = AStarPathfinder.findPath(
      grid: _map.grid,
      startRow: _currentRow!,
      startCol: _currentCol!,
      goalRow: _destRow!,
      goalCol: _destCol!,
    );
    if (path == null || path.isEmpty) {
      setState(() {
        _path = null;
        _commands = [];
        _statusText = 'No path found! Check for obstacles.';
      });
      return;
    }
    final cmds = AStarPathfinder.pathToCommands(
      path: path,
      startDirection: _map.startDirectionIndex,
      cellSizeCm: _map.cellSizeCm,
    );
    setState(() {
      _path = path;
      _commands = cmds;
      _state = _NavState.idle;
      _statusText = _selectedPlace != null
          ? 'Path: ($_currentRow, $_currentCol) → ${_selectedPlace!.name} (${path.length - 1} steps)'
          : 'Path: ($_currentRow, $_currentCol) → ($_destRow, $_destCol) (${path.length - 1} steps)';
    });
  }

  // ── Command Execution ─────────────────────────────────────────────────────

  Future<void> _runPath() async {
    if (_commands.isEmpty || !_isConnected) return;
    setState(() {
      _state = _NavState.running;
      _currentCommandIdx = 0;
      _currentPathIdx = 0;
      _cancelRequested = false;
      _statusText = 'Running...';
    });

    for (int i = 0; i < _commands.length; i++) {
      if (_cancelRequested) break;
      final cmd = _commands[i];

      setState(() {
        _currentCommandIdx = i;
        _statusText = 'Step ${i + 1}/${_commands.length}: $cmd';
      });

      if (cmd.startsWith('move:') || cmd == 'left90' || cmd == 'right90') {
        _mqtt.publish(cmd);
        // Wait for 'done' signal from encoder feedback
        _movementCompleter = Completer<void>();
        await Future.any([
          _movementCompleter!.future,
          Future.delayed(const Duration(seconds: 15)), // safety timeout
        ]);
        _movementCompleter = null;

        // If it was a move, advance path highlight
        if (cmd.startsWith('move:') && mounted) {
          setState(() => _currentPathIdx++);
        }
      }

      if (_cancelRequested) break;
    }

    _mqtt.publish('stop');
    if (mounted) {
      setState(() {
        _state = _cancelRequested ? _NavState.idle : _NavState.done;
        _statusText = _cancelRequested
            ? '⛔ Navigation stopped.'
            : '🎉 Destination reached!';
        _currentPathIdx = _cancelRequested ? 0 : (_path?.length ?? 0);
      });
    }
  }

  void _stop() {
    _cancelRequested = true;
    _movementCompleter?.complete(); // unblock any waiting
    _mqtt.publish('stop');
  }

  Future<void> _manualTurn(bool isLeft) async {
    if (_state == _NavState.running || !_isConnected) return;
    setState(() => _state = _NavState.running);
    _mqtt.publish(isLeft ? 'left' : 'right');
    await Future.delayed(Duration(milliseconds: _turnDurationMs));
    _mqtt.publish('stop');
    if (mounted) setState(() => _state = _NavState.idle);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _map.name,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
        ),
        actions: [
          if (_map.places.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.place_rounded, color: Colors.teal),
              tooltip: 'Places',
              onPressed: _showPlaceSelector,
            ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: RoverTheme.primary),
            tooltip: 'Settings',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Status bar ───────────────────────────────────────────────────
          _buildStatusBar(),

          // ── Grid ─────────────────────────────────────────────────────────
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.4,
              maxScale: 3.0,
              child: GestureDetector(
                onTapDown: (d) {
                  final row = (d.localPosition.dy / _cellPx).floor();
                  final col = (d.localPosition.dx / _cellPx).floor();
                  _onCellTap(row, col);
                },
                child: CustomPaint(
                  size: Size(_map.cols * _cellPx, _map.rows * _cellPx),
                  painter: _NavGridPainter(
                    map: _map,
                    cellPx: _cellPx,
                    path: _path,
                    currentPathIdx: _currentPathIdx,
                    destRow: _destRow,
                    destCol: _destCol,
                    curRow: _currentRow,
                    curCol: _currentCol,
                    currentSet: _currentSet,
                    currentHeading: _currentHeading,
                  ),
                ),
              ),
            ),
          ),

          // ── Command list preview ─────────────────────────────────────────
          if (_commands.isNotEmpty) _buildCommandPreview(),

          // ── Control buttons ───────────────────────────────────────────────
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final connected = _isConnected;
    Color bg;
    switch (_state) {
      case _NavState.running:
        bg = RoverTheme.primary.withOpacity(0.1);
      case _NavState.done:
        bg = Colors.green.withOpacity(0.1);
      case _NavState.error:
        bg = Colors.red.withOpacity(0.1);
      default:
        bg = RoverTheme.surfaceContainerLow;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (_state == _NavState.running)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: RoverTheme.primary,
              ),
            )
          else
            Icon(
              _state == _NavState.done
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              size: 16,
              color: _state == _NavState.done
                  ? Colors.green
                  : RoverTheme.primary,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusText,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: connected
                  ? Colors.green.withOpacity(0.15)
                  : Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              connected ? 'MQTT ✓' : 'NO MQTT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: connected ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandPreview() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final cmd = _commands[i];
          final isActive =
              i == _currentCommandIdx && _state == _NavState.running;
          final isDone = i < _currentCommandIdx || _state == _NavState.done;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? RoverTheme.primary.withOpacity(0.3)
                  : isDone
                  ? Colors.green.withOpacity(0.2)
                  : RoverTheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? Border.all(color: RoverTheme.primary, width: 1.5)
                  : null,
            ),
            child: Text(
              cmd.startsWith('move:')
                  ? '→ ${cmd.substring(5)}cm'
                  : cmd == 'left90'
                  ? '↺'
                  : '↻',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isActive
                    ? RoverTheme.primary
                    : isDone
                    ? Colors.green
                    : RoverTheme.secondary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: RoverTheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: (_isConnected && _state != _NavState.running)
                  ? () => _manualTurn(true)
                  : null,
              icon: const Icon(Icons.rotate_left_rounded),
              color: RoverTheme.primary,
              tooltip: 'Turn Left 90°',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  (_destRow != null &&
                      _map.hasStart &&
                      _state != _NavState.running)
                  ? _findPath
                  : null,
              icon: const Icon(Icons.route_rounded, size: 18),
              label: const Text('PATH', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: RoverTheme.primary,
                side: const BorderSide(color: RoverTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed:
                  (_destRow != null &&
                      _map.hasStart &&
                      _state != _NavState.running &&
                      _path != null)
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveNavigationScreen(
                            map: _map,
                            destRow: _destRow!,
                            destCol: _destCol!,
                            destinationName: _selectedPlace?.name,
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('GO', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: RoverTheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: (_isConnected && _state != _NavState.running)
                  ? () => _manualTurn(false)
                  : null,
              icon: const Icon(Icons.rotate_right_rounded),
              color: RoverTheme.primary,
              tooltip: 'Turn Right 90°',
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: RoverTheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Navigation Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.rotate_right_rounded,
                    color: RoverTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Turn Duration (90°)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '$_turnDurationMs ms',
                    style: const TextStyle(
                      color: RoverTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _turnDurationMs.toDouble(),
                min: 300,
                max: 1500,
                divisions: 24,
                label: '$_turnDurationMs ms',
                activeColor: RoverTheme.primary,
                onChanged: (v) => setBS(() {
                  _turnDurationMs = v.round();
                  if (mounted) setState(() {});
                }),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠  Adjust turn duration until 90° turns are accurate for your rover.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Navigation Grid Painter ────────────────────────────────────────────────────

class _NavGridPainter extends CustomPainter {
  final GridMap map;
  final double cellPx;
  final List<PathCell>? path;
  final int currentPathIdx;
  final int? destRow;
  final int? destCol;
  final int? curRow;
  final int? curCol;
  final bool currentSet;
  final double currentHeading;

  _NavGridPainter({
    required this.map,
    required this.cellPx,
    this.path,
    required this.currentPathIdx,
    this.destRow,
    this.destCol,
    this.curRow,
    this.curCol,
    required this.currentSet,
    required this.currentHeading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()
      ..color = const Color(0xFF8B4513).withOpacity(0.85);
    final emptyPaint = Paint()..color = RoverTheme.surfaceContainer;
    final gridLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Draw cells
    for (int r = 0; r < map.rows; r++) {
      for (int c = 0; c < map.cols; c++) {
        final rect = Rect.fromLTWH(c * cellPx, r * cellPx, cellPx, cellPx);
        canvas.drawRect(rect, map.grid[r][c] == 1 ? wallPaint : emptyPaint);
        canvas.drawRect(rect, gridLinePaint);
      }
    }

    // Draw path
    if (path != null && path!.isNotEmpty) {
      for (int i = 1; i < path!.length - 1; i++) {
        final cell = path![i];
        final bool visited = i < currentPathIdx;
        final pathPaint = Paint()
          ..color = visited
              ? Colors.green.withOpacity(0.6)
              : RoverTheme.primary.withOpacity(0.35);
        final rect = Rect.fromLTWH(
          cell.col * cellPx + 3,
          cell.row * cellPx + 3,
          cellPx - 6,
          cellPx - 6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          pathPaint,
        );
      }
    }

    // Draw destination
    if (destRow != null && destCol != null) {
      final destPaint = Paint()..color = Colors.greenAccent.shade700;
      final rect = Rect.fromLTWH(
        destCol! * cellPx + 2,
        destRow! * cellPx + 2,
        cellPx - 4,
        cellPx - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        destPaint,
      );
      _drawText(canvas, '🏁', destCol! * cellPx, destRow! * cellPx, cellPx);
    }

    // Draw current position (rover location)
    if (currentSet && curRow != null && curCol != null) {
      final curPaint = Paint()..color = Colors.orange;
      final curRect = Rect.fromLTWH(
        curCol! * cellPx + 2,
        curRow! * cellPx + 2,
        cellPx - 4,
        cellPx - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(curRect, const Radius.circular(6)),
        curPaint,
      );
      _drawText(canvas, '🤖', curCol! * cellPx, curRow! * cellPx, cellPx);
    }

    // Draw map start (as fallback reference)
    if (map.hasStart && !currentSet) {
      final sr = map.startRow!;
      final sc = map.startCol!;
      // If rover has moved, show at current path position
      final roverIdx = currentPathIdx < (path?.length ?? 0)
          ? currentPathIdx
          : 0;
      final roverCell =
          (path != null && path!.isNotEmpty && roverIdx < path!.length)
          ? path![roverIdx]
          : PathCell(sr, sc);

      final roverPaint = Paint()..color = Colors.orange;
      final roverRect = Rect.fromLTWH(
        roverCell.col * cellPx + 2,
        roverCell.row * cellPx + 2,
        cellPx - 4,
        cellPx - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(roverRect, const Radius.circular(6)),
        roverPaint,
      );
      // Draw rover with real heading from gyroscope
      final headingStr = currentHeading.toStringAsFixed(0);
      _drawText(
        canvas,
        headingStr,
        roverCell.col * cellPx,
        roverCell.row * cellPx,
        cellPx,
      );
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(x + (size - tp.width) / 2, y + (size - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _NavGridPainter old) =>
      old.path != path ||
      old.currentPathIdx != currentPathIdx ||
      old.destRow != destRow ||
      old.destCol != destCol ||
      old.currentHeading != currentHeading;
}
