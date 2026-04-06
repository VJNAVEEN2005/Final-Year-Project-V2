import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_model.dart';

class MapService {
  static const String _key = 'rover_grid_maps_v1';

  /// Load all saved maps, newest first.
  static Future<List<GridMap>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? [];
    final maps = <GridMap>[];
    for (final s in jsonList) {
      try {
        maps.add(GridMap.fromJsonString(s));
      } catch (_) {
        // skip corrupt entries
      }
    }
    maps.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return maps;
  }

  /// Save a new map (does not overwrite existing maps with same id).
  static Future<void> save(GridMap map) async {
    final prefs = await SharedPreferences.getInstance();
    final maps = await loadAll();
    maps.removeWhere((m) => m.id == map.id); // prevent duplicates
    maps.insert(0, map);
    await _persist(prefs, maps);
  }

  /// Update an existing map by id.
  static Future<void> update(GridMap map) async {
    final prefs = await SharedPreferences.getInstance();
    final maps = await loadAll();
    final idx = maps.indexWhere((m) => m.id == map.id);
    if (idx >= 0) {
      maps[idx] = map;
    } else {
      maps.insert(0, map);
    }
    await _persist(prefs, maps);
  }

  /// Delete a map by id.
  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final maps = await loadAll();
    maps.removeWhere((m) => m.id == id);
    await _persist(prefs, maps);
  }

  static Future<void> _persist(
      SharedPreferences prefs, List<GridMap> maps) async {
    await prefs.setStringList(
        _key, maps.map((m) => m.toJsonString()).toList());
  }
}
