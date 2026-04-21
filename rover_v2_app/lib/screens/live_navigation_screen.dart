import 'dart:async';
import 'package:flutter/material.dart';
import '../algorithms/astar.dart';
import '../models/map_model.dart';
import '../services/mqtt_service.dart';
import '../theme/rover_theme.dart';

enum _NavState { idle, running, done, error }

class LiveNavigationScreen extends StatefulWidget {
  final GridMap map;
  final int destRow;
  final int destCol;
  final String? destinationName;

  const LiveNavigationScreen({
    super.key,
    required this.map,
    required this.destRow,
    required this.destCol,
    this.destinationName,
  });

  @override
  State<LiveNavigationScreen> createState() => _LiveNavigationScreenState();
}

class _LiveNavigationScreenState extends State<LiveNavigationScreen>
    with TickerProviderStateMixin {
  late GridMap _map;

  _NavState _state = _NavState.idle;
  String _statusText = 'Starting navigation...';
  Completer<void>? _movementCompleter;
  bool _cancelRequested = false;
  int _currentPathIdx = 0;

  List<PathCell>? _path;
  List<String> _commands = [];
  int _currentCommandIdx = 0;

  double _motorSpeed = 100;

  final MqttService _mqtt = MqttService.instance;
  StreamSubscription<String>? _dataSub;
  StreamSubscription<String>? _doneSub;
  bool _isConnected = false;

  late int _currentRow;
  late int _currentCol;
  int _currentDirectionIndex = 0;
  
  double _currentYaw = 0;
  bool _obstacleDetected = false;
  // ignore: unused_field
  double _obstacleDistCm = 0;

  static const double _cellPx = 40.0;

  late AnimationController _pathAnimationController;
  // ignore: unused_field
  late Animation<double> _pathAnimation;
  late AnimationController _pulseController;
  // ignore: unused_field
  late Animation<double> _pulseAnimation;
  late AnimationController _roverMoveController;
  late Animation<double> _roverMoveAnimation;
  
  // ignore: unused_field
  double _roverAnimRow = 0;
  // ignore: unused_field
  double _roverAnimCol = 0;

  @override
  void initState() {
    super.initState();
    _map = widget.map;
    _currentRow = _map.startRow ?? 0;
    _currentCol = _map.startCol ?? 0;
    _currentDirectionIndex = _map.startDirectionIndex;
    _isConnected = _mqtt.isConnected;
    _dataSub = _mqtt.dataStream.listen(_onMqttData);
    _mqtt.connectionStream.listen((v) {
      if (mounted) setState(() => _isConnected = v);
    });

    _pathAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pathAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pathAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _roverMoveController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _roverMoveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _roverMoveController, curve: Curves.easeInOut),
    );
    _roverMoveAnimation.addListener(_updateRoverPosition);

    _roverAnimRow = _currentRow.toDouble();
    _roverAnimCol = _currentCol.toDouble();

    _calculatePath();
  }

  void _updateRoverPosition() {
    if (_path != null && _currentPathIdx > 0 && _currentPathIdx < _path!.length) {
      final prev = _path![_currentPathIdx - 1];
      final curr = _path![_currentPathIdx];
      setState(() {
        _roverAnimRow = prev.row + (curr.row - prev.row) * _roverMoveAnimation.value;
        _roverAnimCol = prev.col + (curr.col - prev.col) * _roverMoveAnimation.value;
      });
    }
  }

  void _onMqttData(String data) {
    if (data == 'done') {
      _movementCompleter?.complete();
      return;
    }
    
    if (data == 'obstacle_detected') {
      _obstacleDetected = true;
      _movementCompleter?.complete();
      return;
    }
    
    if (data.startsWith('obs:')) {
      final obs = double.tryParse(data.substring(4));
      if (obs != null) {
        _obstacleDistCm = obs;
        _obstacleDetected = obs > 0 && obs < 20;
        
        if (_obstacleDetected && _state == _NavState.running) {
          _handleObstacle();
        }
      }
      return;
    }
    
    if (data.startsWith('yaw:')) {
      final yaw = double.tryParse(data.substring(4));
      if (yaw != null) {
        setState(() {
          _currentYaw = yaw;
          _currentDirectionIndex = _yawToDirection(yaw);
        });
      }
    }
  }
  
  int _yawToDirection(double yaw) {
    final normalized = ((yaw + 180) % 360 + 360) % 360;
    if (normalized >= 315 || normalized < 45) return 0;
    if (normalized >= 45 && normalized < 135) return 1;
    if (normalized >= 135 && normalized < 225) return 2;
    return 3;
  }
  
  void _handleObstacle() {
    _movementCompleter?.complete();
    _mqtt.publish('stop');
    
    setState(() {
      _statusText = 'Obstacle detected! Remapping...';
    });
    
    Future.delayed(const Duration(milliseconds: 500), () {
      _recalculatePath();
    });
  }
  
  void _recalculatePath() {
    if (_currentRow >= 0 && _currentRow < _map.rows && 
        _currentCol >= 0 && _currentCol < _map.cols) {
      _map.grid[_currentRow][_currentCol] = 1;
    }
    
    final newPath = AStarPathfinder.findPath(
      grid: _map.grid,
      startRow: _currentRow,
      startCol: _currentCol,
      goalRow: widget.destRow,
      goalCol: widget.destCol,
    );
    
    if (newPath == null || newPath.isEmpty) {
      setState(() {
        _state = _NavState.error;
        _statusText = 'No path found! Obstacle blocking way.';
      });
      return;
    }
    
    setState(() {
      _path = newPath;
      _commands = AStarPathfinder.pathToCommands(
        path: _path!,
        startDirection: _currentDirectionIndex,
        cellSizeCm: _map.cellSizeCm,
      );
      _currentPathIdx = 0;
      _currentCommandIdx = 0;
      _statusText = 'Path recalculated! Resuming...';
    });
    
    _resumeNavigation();
  }
  
  void _resumeNavigation() async {
    if (_commands.isEmpty) {
      setState(() {
        _state = _NavState.done;
        _statusText = widget.destinationName != null
            ? 'Arrived at ${widget.destinationName}!'
            : 'Arrived at destination!';
      });
      return;
    }
    
    setState(() {
      _state = _NavState.running;
    });
    
    for (int i = 0; i < _commands.length; i++) {
      if (_cancelRequested) break;
      if (_obstacleDetected) {
        _handleObstacle();
        return;
      }
      
      final cmd = _commands[i];
      
      setState(() {
        _currentCommandIdx = i;
        _statusText = 'Step ${i + 1}/${_commands.length}: $cmd';
      });
      
      if (cmd.startsWith('move:') || cmd == 'left90' || cmd == 'right90') {
        _mqtt.publish(cmd);
        
        _movementCompleter = Completer<void>();
        await Future.any([
          _movementCompleter!.future,
          Future.delayed(const Duration(seconds: 20)),
        ]);
        _movementCompleter = null;
        
        if (cmd.startsWith('move:') && mounted) {
          setState(() => _currentPathIdx++);
          if (_path != null && _currentPathIdx < _path!.length) {
            _currentRow = _path![_currentPathIdx].row;
            _currentCol = _path![_currentPathIdx].col;
          }
        }
      }
      
      if (_cancelRequested) break;
    }
    
    _mqtt.publish('stop');
    if (mounted) {
      setState(() {
        _state = _cancelRequested ? _NavState.idle : _NavState.done;
        _statusText = _cancelRequested
            ? 'Navigation stopped.'
            : widget.destinationName != null
            ? 'Arrived at ${widget.destinationName}!'
            : 'Arrived at destination!';
      });
    }
  }

  void _calculatePath() {
    if (!_map.hasStart) {
      setState(() => _statusText = 'No start position set');
      return;
    }
    _path = AStarPathfinder.findPath(
      grid: _map.grid,
      startRow: _map.startRow!,
      startCol: _map.startCol!,
      goalRow: widget.destRow,
      goalCol: widget.destCol,
    );
    if (_path == null || _path!.isEmpty) {
      setState(() => _statusText = 'No path found!');
      return;
    }
    _commands = AStarPathfinder.pathToCommands(
      path: _path!,
      startDirection: _map.startDirectionIndex,
      cellSizeCm: _map.cellSizeCm,
    );
    setState(() {
      _statusText = widget.destinationName != null
          ? 'To: ${widget.destinationName}'
          : 'To: (${widget.destRow}, ${widget.destCol})';
    });
  }

  Future<void> _startNavigation() async {
    if (_commands.isEmpty || !_isConnected) return;
    
    _mqtt.publish('speed:${_motorSpeed.round()}');
    await Future.delayed(const Duration(milliseconds: 100));
    
    _pathAnimationController.forward(from: 0.0);
    setState(() {
      _state = _NavState.running;
      _currentCommandIdx = 0;
      _currentPathIdx = 0;
      _cancelRequested = false;
      _obstacleDetected = false;
      _statusText = 'Starting...';
    });

    for (int i = 0; i < _commands.length; i++) {
      if (_cancelRequested) break;
      if (_obstacleDetected) {
        _handleObstacle();
        return;
      }
      
      final cmd = _commands[i];

      setState(() {
        _currentCommandIdx = i;
        _statusText = 'Step ${i + 1}/${_commands.length}: $cmd';
      });

      if (cmd.startsWith('move:') || cmd == 'left90' || cmd == 'right90') {
        _mqtt.publish(cmd);
        
        _movementCompleter = Completer<void>();
        await Future.any([
          _movementCompleter!.future,
          Future.delayed(const Duration(seconds: 20)),
        ]);
        _movementCompleter = null;

        if (cmd.startsWith('move:') && mounted) {
          setState(() => _currentPathIdx++);
          if (_path != null && _currentPathIdx < _path!.length) {
            _currentRow = _path![_currentPathIdx].row;
            _currentCol = _path![_currentPathIdx].col;
          }
        }
      }

      if (_cancelRequested) break;
    }

    _mqtt.publish('stop');
    if (mounted) {
      setState(() {
        _state = _cancelRequested ? _NavState.idle : _NavState.done;
        _statusText = _cancelRequested
            ? 'Navigation stopped.'
            : widget.destinationName != null
            ? 'Arrived at ${widget.destinationName}!'
            : 'Arrived at destination!';
      });
    }
  }

  void _stop() {
    _cancelRequested = true;
    _movementCompleter?.complete();
    _mqtt.publish('stop');
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _doneSub?.cancel();
    _pathAnimationController.dispose();
    _pulseController.dispose();
    _roverMoveController.dispose();
    if (_state == _NavState.running) _mqtt.publish('stop');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: RoverTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Live Navigation',
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _isConnected ? 'CONNECTED' : 'DISCONNECTED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(),

          // Grid with path line
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.4,
              maxScale: 3.0,
              child: CustomPaint(
                size: Size(_map.cols * _cellPx, _map.rows * _cellPx),
                painter: _LiveNavPainter(
                  map: _map,
                  cellPx: _cellPx,
                  path: _path,
                  currentPathIdx: _currentPathIdx,
                  destRow: widget.destRow,
                  destCol: widget.destCol,
                  currentRow: _currentRow,
                  currentCol: _currentCol,
                  currentDirection: _currentDirectionIndex,
                  destinationName: widget.destinationName,
                ),
              ),
            ),
          ),

          // Bottom info and controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    Color bg;
    switch (_state) {
      case _NavState.running:
        bg = RoverTheme.primary.withOpacity(0.15);
      case _NavState.done:
        bg = Colors.green.withOpacity(0.15);
      case _NavState.error:
        bg = Colors.red.withOpacity(0.15);
      default:
        bg = RoverTheme.surfaceContainer;
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _state == _NavState.running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: RoverTheme.primary,
                    ),
                  )
                : Icon(
                    _state == _NavState.done
                        ? Icons.check_circle_rounded
                        : Icons.navigation_rounded,
                    size: 16,
                    color: _state == _NavState.done
                        ? Colors.green
                        : RoverTheme.primary,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _statusText,
                key: ValueKey(_statusText),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_path != null)
            Text(
              '${_currentPathIdx + 1}/${_path!.length}',
              style: TextStyle(fontSize: 12, color: RoverTheme.primary),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: RoverTheme.surfaceContainer,
        border: Border(top: BorderSide(color: Color(0xFF2A2A3A), width: 0.5)),
      ),
      child: Row(
        children: [
          // Position info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.my_location_rounded,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Current: (${_currentRow}, ${_currentCol})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (widget.destinationName != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 14,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Destination: ${widget.destinationName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Speed slider
          SizedBox(
            width: 140,
            height: 40,
            child: Row(
              children: [
                const Icon(Icons.speed_rounded, size: 16, color: RoverTheme.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: _motorSpeed,
                      min: 50,
                      max: 255,
                      divisions: 41,
                      onChanged: (v) => setState(() => _motorSpeed = v),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: RoverTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_motorSpeed.round()}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: RoverTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Start/Stop button with animation
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: _state == _NavState.running
                ? ElevatedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('STOP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _commands.isNotEmpty && _isConnected
                        ? _startNavigation
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('START'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RoverTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LiveNavPainter extends CustomPainter {
  final GridMap map;
  final double cellPx;
  final List<PathCell>? path;
  final int currentPathIdx;
  final int? destRow;
  final int? destCol;
  final int currentRow;
  final int currentCol;
  final int currentDirection;
  final String? destinationName;

  _LiveNavPainter({
    required this.map,
    required this.cellPx,
    this.path,
    required this.currentPathIdx,
    this.destRow,
    this.destCol,
    required this.currentRow,
    required this.currentCol,
    required this.currentDirection,
    this.destinationName,
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

    // Draw full path line
    if (path != null && path!.isNotEmpty) {
      final pathPaint = Paint()
        ..color = RoverTheme.primary.withOpacity(0.8)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < path!.length - 1; i++) {
        final start = path![i];
        final end = path![i + 1];
        canvas.drawLine(
          Offset(
            start.col * cellPx + cellPx / 2,
            start.row * cellPx + cellPx / 2,
          ),
          Offset(end.col * cellPx + cellPx / 2, end.row * cellPx + cellPx / 2),
          pathPaint,
        );
      }
    }

    // Draw destination
    if (destRow != null && destCol != null) {
      final destPaint = Paint()..color = Colors.teal;
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

      if (destinationName != null) {
        _drawText(canvas, '📍', destCol! * cellPx, destRow! * cellPx, cellPx);
      } else {
        _drawText(canvas, '🏁', destCol! * cellPx, destRow! * cellPx, cellPx);
      }
    }

    // Draw current position
    final roverPaint = Paint()..color = Colors.orange;
    final roverRect = Rect.fromLTWH(
      currentCol * cellPx + 2,
      currentRow * cellPx + 2,
      cellPx - 4,
      cellPx - 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(roverRect, const Radius.circular(6)),
      roverPaint,
    );

    final directions = ['↑', '→', '↓', '←'];
    _drawText(
      canvas,
      directions[currentDirection % 4],
      currentCol * cellPx,
      currentRow * cellPx,
      cellPx,
    );
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
  bool shouldRepaint(covariant _LiveNavPainter old) =>
      old.currentRow != currentRow ||
      old.currentCol != currentCol ||
      old.currentPathIdx != currentPathIdx ||
      old.path != path;
}
