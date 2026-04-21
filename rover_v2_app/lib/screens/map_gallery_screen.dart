import 'package:flutter/material.dart';
import '../models/map_model.dart';
import '../services/map_service.dart';
import '../theme/rover_theme.dart';
import 'map_designer_screen.dart';
import 'map_navigator_screen.dart';

class MapGalleryScreen extends StatefulWidget {
  const MapGalleryScreen({super.key});

  @override
  State<MapGalleryScreen> createState() => _MapGalleryScreenState();
}

class _MapGalleryScreenState extends State<MapGalleryScreen> {
  List<GridMap> _maps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final maps = await MapService.loadAll();
    if (mounted) {
      setState(() {
        _maps = maps;
        _loading = false;
      });
    }
  }

  GridMap? get _map => _maps.isNotEmpty ? _maps.first : null;

  void _showCreateDialog() {
    final nameCtrl = TextEditingController(text: 'My Map');
    int rows = 10;
    int cols = 10;
    double cellSize = 30.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: RoverTheme.surfaceContainerHigh,
          title: const Text('Create New Map'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Map Name',
                    prefixIcon: Icon(Icons.label_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Rows', style: TextStyle(fontSize: 12)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: rows > 3
                                    ? () => setState(() => rows--)
                                    : null,
                              ),
                              Text(
                                '$rows',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: rows < 30
                                    ? () => setState(() => rows++)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Columns', style: TextStyle(fontSize: 12)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: cols > 3
                                    ? () => setState(() => cols--)
                                    : null,
                              ),
                              Text(
                                '$cols',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: cols < 30
                                    ? () => setState(() => cols++)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Cell Size: '),
                    Expanded(
                      child: Slider(
                        value: cellSize,
                        min: 10,
                        max: 100,
                        divisions: 18,
                        activeColor: RoverTheme.primary,
                        onChanged: (v) => setState(() => cellSize = v),
                      ),
                    ),
                    Text('${cellSize.toInt()}cm'),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: RoverTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Grid: $rows×$cols\nSize: ${(rows * cellSize / 100).toStringAsFixed(1)}m × ${(cols * cellSize / 100).toStringAsFixed(1)}m',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: RoverTheme.primary,
                    ),
                  ),
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
                if (nameCtrl.text.trim().isEmpty) return;
                final newMap = GridMap.blank(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text.trim(),
                  rows: rows,
                  cols: cols,
                  cellSizeCm: cellSize,
                );
                Navigator.pop(ctx);
                _openDesigner(newMap, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: RoverTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create & Edit'),
            ),
          ],
        ),
      ),
    );
  }

  void _openDesigner(GridMap map, bool isNew) async {
    final saved = await Navigator.push<GridMap>(
      context,
      MaterialPageRoute(
        builder: (_) => MapDesignerScreen(map: map, isNew: isNew),
      ),
    );
    if (saved != null) _reload();
  }

  void _openNavigator() async {
    if (_map == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MapNavigatorScreen(map: _map!)),
    );
    _reload();
  }

  void _recreateMap() async {
    if (_map == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Recreate Map'),
        content: const Text('This will delete all walls and places. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recreate', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final newMap = GridMap.blank(
      id: _map!.id,
      name: _map!.name,
      rows: _map!.rows,
      cols: _map!.cols,
      cellSizeCm: _map!.cellSizeCm,
    );
    await MapService.update(newMap);
    _reload();
  }

  void _deleteMap() async {
    if (_map == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Delete Map'),
        content: const Text('Delete this map? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await MapService.delete(_map!.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoverTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.map_rounded, color: RoverTheme.primary),
            SizedBox(width: 12),
            Text('Map', style: TextStyle(fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: RoverTheme.primary),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: RoverTheme.primary),
            )
          : _map == null
          ? _buildEmpty()
          : _buildMapCard(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_circle_outline_rounded,
            size: 80,
            color: RoverTheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Map Created',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a map to navigate the rover',
            style: TextStyle(color: RoverTheme.secondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create New Map'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RoverTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    final map = _map!;
    final totalW = (map.cols * map.cellSizeCm / 100).toStringAsFixed(1);
    final totalH = (map.rows * map.cellSizeCm / 100).toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: RoverTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  map.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(Icons.grid_on_rounded, '${map.rows}×${map.cols}'),
                    _chip(
                      Icons.straighten_rounded,
                      '${map.cellSizeCm.toInt()}cm',
                    ),
                    _chip(Icons.aspect_ratio_rounded, '${totalW}m×${totalH}m'),
                  ],
                ),
                if (map.places.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Places:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: map.places
                        .map((p) => _placeChip(p.name))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  color: RoverTheme.primary,
                  onTap: () => _openDesigner(map, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.refresh_rounded,
                  label: 'Recreate',
                  color: Colors.orange,
                  onTap: _recreateMap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _actionButton(
              icon: Icons.navigation_rounded,
              label: 'Navigate',
              color: Colors.teal,
              onTap: map.hasStart ? _openNavigator : null,
              large: true,
            ),
          ),
          if (!map.hasStart)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set start position in Edit mode first to enable navigation',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          // Delete button
          Center(
            child: TextButton.icon(
              onPressed: _deleteMap,
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 18,
              ),
              label: const Text(
                'Delete Map',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: RoverTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: RoverTheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: RoverTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _placeChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_rounded, size: 14, color: Colors.teal),
          const SizedBox(width: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.teal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool large = false,
  }) {
    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 20 : 16,
        vertical: large ? 16 : 12,
      ),
      decoration: BoxDecoration(
        color: onTap != null
            ? color.withOpacity(0.15)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTap != null ? color : Colors.grey,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: onTap != null ? color : Colors.grey),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: onTap != null ? color : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: large ? 16 : 14,
            ),
          ),
        ],
      ),
    );

    return onTap != null
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: content,
          )
        : content;
  }

  Widget _buildBottomNav() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: RoverTheme.backgroundLight,
        border: Border(
          top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.sensors, 'STATUS', '/status'),
          _navItem(Icons.videogame_asset, 'CONTROL', '/control'),
          _navItem(Icons.map_rounded, 'MAPS', '/maps', active: true),
          _navItem(Icons.auto_awesome, 'AI', '/ai'),
          _navItem(Icons.settings, 'SETTINGS', '/settings'),
        ],
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    String route, {
    bool active = false,
  }) {
    return InkWell(
      onTap: active
          ? null
          : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? RoverTheme.primary : RoverTheme.secondary,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: active ? RoverTheme.primary : RoverTheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
