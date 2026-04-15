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
    if (mounted) setState(() { _maps = maps; _loading = false; });
  }

  void _createNew() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _NewMapDialog(),
    );
    if (result == null) return;

    final map = GridMap.blank(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: result['name'] as String,
      rows: result['rows'] as int,
      cols: result['cols'] as int,
      cellSizeCm: result['cellSizeCm'] as double,
    );

    if (!mounted) return;
    final saved = await Navigator.push<GridMap>(
      context,
      MaterialPageRoute(builder: (_) => MapDesignerScreen(map: map, isNew: true)),
    );
    if (saved != null) _reload();
  }

  void _openDesigner(GridMap map) async {
    final saved = await Navigator.push<GridMap>(
      context,
      MaterialPageRoute(builder: (_) => MapDesignerScreen(map: map, isNew: false)),
    );
    if (saved != null) _reload();
  }

  void _openNavigator(GridMap map) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MapNavigatorScreen(map: map)),
    );
    _reload();
  }

  void _openScanner() async {
    final success = await Navigator.pushNamed(context, '/scan');
    if (success == true) _reload();
  }

  void _delete(GridMap map) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: RoverTheme.surfaceContainerHigh,
        title: const Text('Delete Map'),
        content: Text('Delete "${map.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await MapService.delete(map.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.map_rounded, color: RoverTheme.primary),
          const SizedBox(width: 12),
          Text('Map Gallery', style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: RoverTheme.primary),
            onPressed: _reload,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scan_btn',
            onPressed: _openScanner,
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan Room', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new_btn',
            onPressed: _createNew,
            backgroundColor: RoverTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Map', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: RoverTheme.primary))
          : _maps.isEmpty
              ? _buildEmpty(theme)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: _maps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _MapCard(
                    map: _maps[i],
                    onEdit: () => _openDesigner(_maps[i]),
                    onNavigate: () => _openNavigator(_maps[i]),
                    onDelete: () => _delete(_maps[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 80, color: RoverTheme.secondary.withOpacity(0.3)),
          const SizedBox(height: 20),
          Text('No maps yet', style: theme.textTheme.titleLarge?.copyWith(color: RoverTheme.secondary)),
          const SizedBox(height: 8),
          Text('Tap + to create your first map', style: theme.textTheme.bodyMedium?.copyWith(color: RoverTheme.secondary.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: RoverTheme.background.withOpacity(0.95),
        border: const Border(top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(context, Icons.sensors, 'STATUS', route: '/status'),
          _navItem(context, Icons.videogame_asset, 'CONTROL', route: '/control'),
          _navItem(context, Icons.map_rounded, 'MAPS', route: '/maps', active: true),
          _navItem(context, Icons.auto_awesome, 'AI', route: '/ai'),
          _navItem(context, Icons.settings, 'SETTINGS', route: '/settings'),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label,
      {required String route, bool active = false}) {
    return InkWell(
      onTap: active ? null : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? RoverTheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? RoverTheme.primary : RoverTheme.secondary, size: 22),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1, color: active ? RoverTheme.primary : RoverTheme.secondary)),
        ]),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  final GridMap map;
  final VoidCallback onEdit;
  final VoidCallback onNavigate;
  final VoidCallback onDelete;

  const _MapCard({required this.map, required this.onEdit, required this.onNavigate, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalW = (map.cols * map.cellSizeCm / 100).toStringAsFixed(1);
    final totalH = (map.rows * map.cellSizeCm / 100).toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: RoverTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini grid preview
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: CustomPaint(painter: _MiniGridPainter(map)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(map.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(spacing: 8, children: [
                  _chip(Icons.grid_on_rounded, '${map.rows}×${map.cols}'),
                  _chip(Icons.straighten_rounded, '${map.cellSizeCm.toInt()}cm/cell'),
                  _chip(Icons.aspect_ratio_rounded, '${totalW}m × ${totalH}m'),
                  if (map.hasStart)
                    _chip(Icons.navigation_rounded, 'Start: ${map.startDirection.arrow}'),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(foregroundColor: RoverTheme.primary, side: const BorderSide(color: RoverTheme.primary)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: map.hasStart ? onNavigate : null,
                      icon: const Icon(Icons.navigation_rounded, size: 16),
                      label: const Text('Navigate'),
                      style: ElevatedButton.styleFrom(backgroundColor: RoverTheme.primary, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: RoverTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: RoverTheme.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: RoverTheme.primary, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MiniGridPainter extends CustomPainter {
  final GridMap map;
  _MiniGridPainter(this.map);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / map.cols;
    final cellH = size.height / map.rows;

    final wallPaint = Paint()..color = RoverTheme.primary.withOpacity(0.7);
    final emptyPaint = Paint()..color = RoverTheme.surfaceContainerHighest.withOpacity(0.5);

    for (int r = 0; r < map.rows; r++) {
      for (int c = 0; c < map.cols; c++) {
        final rect = Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH);
        canvas.drawRect(rect, map.grid[r][c] == 1 ? wallPaint : emptyPaint);
      }
    }

    // Draw start
    if (map.hasStart) {
      final startPaint = Paint()..color = Colors.orange;
      final sr = map.startRow!;
      final sc = map.startCol!;
      final rect = Rect.fromLTWH(sc * cellW, sr * cellH, cellW, cellH);
      canvas.drawRect(rect, startPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _NewMapDialog extends StatefulWidget {
  const _NewMapDialog();

  @override
  State<_NewMapDialog> createState() => _NewMapDialogState();
}

class _NewMapDialogState extends State<_NewMapDialog> {
  final _nameCtrl = TextEditingController(text: 'My Map');
  int _rows = 10;
  int _cols = 10;
  double _cellSize = 30.0;

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: RoverTheme.surfaceContainerHigh,
      title: const Text('Create New Map'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Map Name', prefixIcon: Icon(Icons.label_rounded)),
          ),
          const SizedBox(height: 16),
          _counter('Rows', _rows, 3, 30, (v) => _rows = v),
          _counter('Columns', _cols, 3, 30, (v) => _cols = v),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Cell Size (cm): ', style: TextStyle(fontWeight: FontWeight.w600)),
            Expanded(
              child: Slider(
                value: _cellSize,
                min: 10,
                max: 100,
                divisions: 18,
                label: '${_cellSize.toInt()} cm',
                activeColor: RoverTheme.primary,
                onChanged: (v) => setState(() => _cellSize = v),
              ),
            ),
            Text('${_cellSize.toInt()} cm', style: const TextStyle(fontWeight: FontWeight.bold, color: RoverTheme.primary)),
          ]),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: RoverTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Grid: $_rows × $_cols cells\nPhysical: ${(_rows * _cellSize / 100).toStringAsFixed(1)}m × ${(_cols * _cellSize / 100).toStringAsFixed(1)}m',
              style: const TextStyle(fontSize: 12, color: RoverTheme.primary),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name': _nameCtrl.text.trim(),
              'rows': _rows,
              'cols': _cols,
              'cellSizeCm': _cellSize,
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: RoverTheme.primary, foregroundColor: Colors.white),
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _counter(String label, int value, int min, int max, void Function(int) onChanged) {
    return Row(children: [
      Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        color: RoverTheme.primary,
        onPressed: value > min ? () => setState(() => onChanged(value - 1)) : null,
      ),
      Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      IconButton(
        icon: const Icon(Icons.add_circle_outline),
        color: RoverTheme.primary,
        onPressed: value < max ? () => setState(() => onChanged(value + 1)) : null,
      ),
    ]);
  }
}
