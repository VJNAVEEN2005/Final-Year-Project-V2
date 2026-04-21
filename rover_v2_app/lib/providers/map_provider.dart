import 'package:flutter/foundation.dart';
import '../models/map_model.dart';
import '../services/map_service.dart';

class MapProvider extends ChangeNotifier {
  GridMap? _currentMap;
  bool _isLoading = false;

  GridMap? get currentMap => _currentMap;
  bool get isLoading => _isLoading;
  bool get hasMap => _currentMap != null;
  bool get hasStart => _currentMap?.hasStart ?? false;
  List<Place> get places => _currentMap?.places ?? [];

  Future<void> loadMap() async {
    _isLoading = true;
    notifyListeners();

    final maps = await MapService.loadAll();
    _currentMap = maps.isNotEmpty ? maps.first : null;

    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveMap(GridMap map) async {
    _isLoading = true;
    notifyListeners();

    await MapService.update(map);
    _currentMap = map;

    _isLoading = false;
    notifyListeners();
  }

  void updateMap(GridMap map) {
    _currentMap = map;
    notifyListeners();
  }

  void setStart(int row, int col, int directionIndex) {
    if (_currentMap == null) return;
    final grid = _currentMap!.grid.map((r) => List<int>.from(r)).toList();
    grid[row][col] = 0;
    _currentMap = _currentMap!.copyWith(
      grid: grid,
      startRow: row,
      startCol: col,
      startDirectionIndex: directionIndex,
    );
    notifyListeners();
  }

  void toggleWall(int row, int col) {
    if (_currentMap == null) return;
    if (row < 0 ||
        row >= _currentMap!.rows ||
        col < 0 ||
        col >= _currentMap!.cols)
      return;
    final grid = _currentMap!.grid.map((r) => List<int>.from(r)).toList();
    grid[row][col] = grid[row][col] == 1 ? 0 : 1;
    _currentMap = _currentMap!.copyWith(grid: grid);
    notifyListeners();
  }

  void addPlace(String name, int row, int col) {
    if (_currentMap == null) return;
    if (name.isEmpty) return;

    final existing = _currentMap!.places.indexWhere((p) => p.name == name);
    if (existing >= 0) return;

    final newPlaces = [
      ..._currentMap!.places,
      Place(name: name.toUpperCase(), row: row, col: col),
    ];
    _currentMap = _currentMap!.copyWith(places: newPlaces);
    notifyListeners();
  }

  void updatePlace(String oldName, String newName, int row, int col) {
    if (_currentMap == null) return;
    final idx = _currentMap!.places.indexWhere((p) => p.name == oldName);
    if (idx < 0) return;

    final newPlaces = _currentMap!.places.map((p) {
      if (p.name == oldName) {
        return Place(name: newName.toUpperCase(), row: row, col: col);
      }
      return p;
    }).toList();

    _currentMap = _currentMap!.copyWith(places: newPlaces);
    notifyListeners();
  }

  void removePlace(String name) {
    if (_currentMap == null) return;
    final newPlaces = _currentMap!.places.where((p) => p.name != name).toList();
    _currentMap = _currentMap!.copyWith(places: newPlaces);
    notifyListeners();
  }

  void clearMap() {
    if (_currentMap == null) return;
    _currentMap = GridMap.blank(
      id: _currentMap!.id,
      name: _currentMap!.name,
      rows: _currentMap!.rows,
      cols: _currentMap!.cols,
      cellSizeCm: _currentMap!.cellSizeCm,
    );
    notifyListeners();
  }
}
