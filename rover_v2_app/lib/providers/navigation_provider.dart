import 'dart:async';
import 'package:flutter/foundation.dart';
import '../algorithms/astar.dart';
import '../models/map_model.dart';
import '../services/mqtt_service.dart';

enum NavigationStatus { idle, running, done, error }

class NavigationProvider extends ChangeNotifier {
  NavigationProvider._internal();
  static final NavigationProvider instance = NavigationProvider._internal();

  final MqttService _mqtt = MqttService.instance;
  StreamSubscription<String>? _dataSub;
  Completer<void>? _movementCompleter;

  GridMap? _map;
  int? _destRow;
  int? _destCol;
  Place? _selectedPlace;
  List<PathCell>? _path;
  List<String> _commands = [];
  int _currentPathIdx = 0;
  int _currentCommandIdx = 0;
  int _currentDirectionIndex = 0;
  int? _currentRow;
  int? _currentCol;
  int _turnDurationMs = 700;

  NavigationStatus _status = NavigationStatus.idle;
  String _statusText = 'Select a destination.';
  bool _isConnected = false;
  bool _showPath = false;

  int get currentRow {
    if (_map?.startRow != null) return _map!.startRow!;
    return _currentRow ?? 0;
  }
  int get currentCol {
    if (_map?.startCol != null) return _map!.startCol!;
    return _currentCol ?? 0;
  }
  int get currentDirectionIndex => _currentDirectionIndex;
  NavigationStatus get status => _status;
  String get statusText => _statusText;
  bool get isConnected => _isConnected;
  bool get showPath => _showPath;
  List<PathCell>? get path => _path;
  int get currentPathIdx => _currentPathIdx;
  int? get destRow => _destRow;
  int? get destCol => _destCol;
  Place? get selectedPlace => _selectedPlace;
  GridMap? get map => _map;

  void initialize(GridMap map) {
    _map = map;
    _currentDirectionIndex = map.startDirectionIndex;
    _isConnected = _mqtt.isConnected;
    _dataSub = _mqtt.dataStream.listen(_onMqttData);
    _mqtt.connectionStream.listen((v) {
      _isConnected = v;
      notifyListeners();
    });
    _statusText = map.hasStart
        ? 'Select a destination.'
        : 'Set start position first.';
    notifyListeners();
  }

  void _onMqttData(String data) {
    if (data == 'done') {
      _movementCompleter?.complete();
    }
  }

  void setDestination(int row, int col, {Place? place}) {
    if (_map == null) return;
    if (row < 0 || row >= _map!.rows || col < 0 || col >= _map!.cols) return;
    if (_map!.grid[row][col] == 1) return;

    _destRow = row;
    _destCol = col;
    _selectedPlace = place;
    _path = null;
    _commands = [];
    _showPath = false;
    _status = NavigationStatus.idle;
    _statusText = place != null
        ? 'Destination: ${place.name}. Tap FIND PATH.'
        : 'Destination set. Tap FIND PATH.';
    notifyListeners();
  }

  void findPath() {
    if (_map == null || !_map!.hasStart || _destRow == null) return;

    _path = AStarPathfinder.findPath(
      grid: _map!.grid,
      startRow: _map!.startRow!,
      startCol: _map!.startCol!,
      goalRow: _destRow!,
      goalCol: _destCol!,
    );

    if (_path == null || _path!.isEmpty) {
      _path = null;
      _commands = [];
      _status = NavigationStatus.error;
      _statusText = 'No path found!';
      notifyListeners();
      return;
    }

    _commands = AStarPathfinder.pathToCommands(
      path: _path!,
      startDirection: _map!.startDirectionIndex,
      cellSizeCm: _map!.cellSizeCm,
    );

    _showPath = true;
    _status = NavigationStatus.idle;
    _statusText = 'Path found! ${_path!.length - 1} steps. Tap GO.';
    notifyListeners();
  }

  Future<void> startNavigation() async {
    if (_commands.isEmpty || !_isConnected || _path == null) return;

    _status = NavigationStatus.running;
    _currentCommandIdx = 0;
    _currentPathIdx = 0;
    _statusText = 'Starting...';
    notifyListeners();

    for (int i = 0; i < _commands.length; i++) {
      final cmd = _commands[i];
      _currentCommandIdx = i;
      _statusText = 'Step ${i + 1}/${_commands.length}: $cmd';
      notifyListeners();

      if (cmd.startsWith('move:') || cmd == 'left90' || cmd == 'right90') {
        _mqtt.publish(cmd);
        _movementCompleter = Completer<void>();
        await Future.any([
          _movementCompleter!.future,
          Future.delayed(const Duration(seconds: 15)),
        ]);
        _movementCompleter = null;

        if (cmd.startsWith('move:')) {
          _currentPathIdx++;
        }
      }
    }

    _mqtt.publish('stop');
    _status = NavigationStatus.done;
    _statusText = _selectedPlace != null
        ? 'Arrived at ${_selectedPlace!.name}!'
        : 'Destination reached!';
    notifyListeners();
  }

  void stopNavigation() {
    _movementCompleter?.complete();
    _mqtt.publish('stop');
    _status = NavigationStatus.idle;
    _statusText = 'Navigation stopped.';
    notifyListeners();
  }

  Future<void> manualTurn(bool isLeft) async {
    if (_status == NavigationStatus.running || !_isConnected) return;
    _mqtt.publish(isLeft ? 'left' : 'right');
    await Future.delayed(Duration(milliseconds: _turnDurationMs));
    _mqtt.publish('stop');
    _currentDirectionIndex = isLeft
        ? (_currentDirectionIndex - 1) % 4
        : (_currentDirectionIndex + 1) % 4;
    notifyListeners();
  }

  void setTurnDuration(int ms) {
    _turnDurationMs = ms;
    notifyListeners();
  }

  void updatePosition(int row, int col, int directionIndex) {
    _currentRow = row;
    _currentCol = col;
    _currentDirectionIndex = directionIndex;
    notifyListeners();
  }

  void setPosition(int row, int col) {
    _currentRow = row;
    _currentCol = col;
    notifyListeners();
  }

  void clearDestination() {
    _destRow = null;
    _destCol = null;
    _selectedPlace = null;
    _path = null;
    _commands = [];
    _showPath = false;
    _status = NavigationStatus.idle;
    _statusText = 'Select a destination.';
    notifyListeners();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _movementCompleter?.complete();
    if (_status == NavigationStatus.running) {
      _mqtt.publish('stop');
    }
    super.dispose();
  }
}
