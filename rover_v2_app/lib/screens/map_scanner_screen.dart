import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import '../theme/rover_theme.dart';
import '../models/map_model.dart';
import '../services/map_service.dart';

class MapScannerScreen extends StatefulWidget {
  const MapScannerScreen({super.key});

  @override
  State<MapScannerScreen> createState() => _MapScannerScreenState();
}

class _MapScannerScreenState extends State<MapScannerScreen> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;

  // Only X and Z are stored for floor mapping (Y = camera height, irrelevant for 2D grid)
  // We store full Vector3 but only use x and z for grid math
  final List<v.Vector3> _scannedPoints = [];
  bool _isScanning = false;
  bool _calculating = false;
  double _cellSizeCm = 20.0;
  String _status = "Initializing AR session...";
  bool _isTrackingFailure = false;
  bool _isWarmingUp = true;
  Timer? _scanTimer;

  // Mutex: prevents concurrent getCameraPose() calls that overflow the camera buffer.
  bool _isPosePending = false;

  // Y reference captured from first successful pose — used for relative drift guard.
  double? _floorYRef;

  @override
  void dispose() {
    _scanTimer?.cancel();
    _arSessionManager?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;

    _arSessionManager!.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      customPlaneTexturePath: "assets/scanned_floor.png",
      // Disable world-origin axes and free-pan gestures:
      // these force extra render passes that steal CPU from ARCore's VIO pipeline,
      // which is the root cause of RESOURCE_EXHAUSTED and buffer-overflow errors.
      showWorldOrigin: false,
      handlePans: false,
      handleRotation: false,
    );
    _arObjectManager!.onInitialize();

    // Extended warm-up: ARCore's IMU/VIO pipeline needs ~5s to accumulate
    // enough inertial data before getCameraPose() returns valid poses.
    // Querying too early causes the 'FAILED_PRECONDITION: No data available' flood.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isWarmingUp = false;
          _status = "Point camera at the floor and walk slowly...";
        });
      }
    });
  }

  void _toggleScanning() {
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        _status = "Scanning floor... Walk around the room.";
        _startTracking();
      } else {
        _status = "Scanning paused. ${_scannedPoints.length} points collected.";
        _scanTimer?.cancel();
      }
    });
  }

  void _startTracking() {
    _scanTimer?.cancel();
    _isTrackingFailure = false;
    _isPosePending = false;

    _scanTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (!mounted || !_isScanning) return;

      if (_isPosePending) return;
      _isPosePending = true;

      try {
        // Use the patched getCameraPose() from the library
        final pose = await _arSessionManager?.getCameraPose();

        if (pose == null) {
          if (mounted && !_isTrackingFailure) {
            setState(() {
              _isTrackingFailure = true;
              _status = "Tracking lost! Slow down and improve lighting.";
            });
          }
          return;
        }

        final translation = pose.getTranslation();
        final double camX = translation.x;
        final double camY = translation.y;
        final double camZ = translation.z;

        // ── Relative Y-drift guard ────────────────────────────────────────────
        if (_floorYRef == null) {
          _floorYRef = camY;
        } else if ((camY - _floorYRef!).abs() > 1.5) {
          debugPrint('[AR] Large Y drift (${(camY - _floorYRef!).abs().toStringAsFixed(2)}m) — skipping');
          return;
        }

        // ── XZ-only distance check ────────────────────────────────────────────
        final double minDistM = (_cellSizeCm / 100.0) * 0.5;
        bool isNewArea = true;
        if (_scannedPoints.isNotEmpty) {
          final last = _scannedPoints.last;
          final dx = camX - last.x;
          final dz = camZ - last.z;
          if ((dx * dx + dz * dz) < (minDistM * minDistM)) {
            isNewArea = false;
          }
        }

        if (isNewArea && mounted) {
          setState(() {
            _isTrackingFailure = false;
            _scannedPoints.add(v.Vector3(camX, 0.0, camZ));
            _status = "Scanning... (${_scannedPoints.length} pts) — keep walking!";
          });
        }
      } catch (e) {
        debugPrint('[AR] Tracking error: $e');
      } finally {
        _isPosePending = false;
      }
    });
  }

  Future<void> _addCurrentPoint() async {
    if (_isPosePending) return;
    _isPosePending = true;
    try {
      final pose = await _arSessionManager?.getCameraPose();
      if (pose == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not localize! Move slowly and try again.")),
          );
        }
        return;
      }
      final translation = pose.getTranslation();
      setState(() {
        _isTrackingFailure = false;
        _scannedPoints.add(v.Vector3(translation.x, 0.0, translation.z));
        _status = "Point pinned! (${_scannedPoints.length} total)";
      });
    } catch (e) {
      debugPrint('[AR] Manual pin error: $e');
    } finally {
      _isPosePending = false;
    }
  }

  void _generateMap() async {
    if (_scannedPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Walk around to scan the floor first!")),
      );
      return;
    }

    setState(() {
      _calculating = true;
      _isScanning = false;
      _scanTimer?.cancel();
    });

    try {
      // ── 1. Bounding Box in XZ plane (floor coordinates) ─────────────────────
      // All stored points already have Y=0 (projected onto floor plane during scan).
      double minX = _scannedPoints[0].x;
      double maxX = _scannedPoints[0].x;
      double minZ = _scannedPoints[0].z;
      double maxZ = _scannedPoints[0].z;

      for (final p in _scannedPoints) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.z < minZ) minZ = p.z;
        if (p.z > maxZ) maxZ = p.z;
      }

      // ── 2. Padding: exactly 1 cell on each side (not a fixed 1m!) ────────────
      final double cellSizeM = _cellSizeCm / 100.0;
      final double pad = cellSizeM; // 1-cell padding
      minX -= pad; maxX += pad;
      minZ -= pad; maxZ += pad;

      // ── 3. Grid dimensions ────────────────────────────────────────────────────
      int cols = ((maxX - minX) / cellSizeM).ceil().clamp(2, 150);
      int rows = ((maxZ - minZ) / cellSizeM).ceil().clamp(2, 150);

      // ── 4. Initialize grid as all-walls (1) ───────────────────────────────────
      final grid = List.generate(rows, (_) => List.filled(cols, 1));

      // ── 5. Carve walkable floor cells (0) around each scanned point ───────────
      // Dilation radius: larger cells = smaller radius, smaller cells = larger radius.
      // Target: cover roughly a 40cm radius around each point.
      final int dilationRadius = (_cellSizeCm <= 10) ? 2 : (_cellSizeCm <= 20) ? 1 : 1;

      for (final p in _scannedPoints) {
        // Grid cell for this XZ floor point
        int c = ((p.x - minX) / cellSizeM).floor();
        int r = ((p.z - minZ) / cellSizeM).floor();

        // Carve a square neighbourhood
        for (int dr = -dilationRadius; dr <= dilationRadius; dr++) {
          for (int dc = -dilationRadius; dc <= dilationRadius; dc++) {
            final nr = r + dr;
            final nc = c + dc;
            if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
              grid[nr][nc] = 0;
            }
          }
        }
      }

      // ── 6. Compute start position from the first scanned point ────────────────
      final firstPoint = _scannedPoints.first;
      int startC = ((firstPoint.x - minX) / cellSizeM).floor().clamp(0, cols - 1);
      int startR = ((firstPoint.z - minZ) / cellSizeM).floor().clamp(0, rows - 1);

      // Ensure start cell is actually walkable (it should be after dilation)
      if (grid[startR][startC] == 1) {
        // Search nearby for a walkable cell
        outer:
        for (int radius = 1; radius <= 3; radius++) {
          for (int dr = -radius; dr <= radius; dr++) {
            for (int dc = -radius; dc <= radius; dc++) {
              final nr = (startR + dr).clamp(0, rows - 1);
              final nc = (startC + dc).clamp(0, cols - 1);
              if (grid[nr][nc] == 0) {
                startR = nr;
                startC = nc;
                break outer;
              }
            }
          }
        }
      }

      // ── 7. Build and save the GridMap ────────────────────────────────────────
      final now = DateTime.now();
      final mapName = "Scan ${now.day}/${now.month} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
      final gridMap = GridMap(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: mapName,
        rows: rows,
        cols: cols,
        cellSizeCm: _cellSizeCm,
        grid: grid,
        startRow: startR,
        startCol: startC,
        startDirectionIndex: 0, // North — user can adjust in navigator
        createdAt: DateTime.now(),
      );

      await MapService.save(gridMap);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Generation error: $e");
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AR Room Scanner"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          
          // HUD overlay
          SafeArea(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isTrackingFailure ? Colors.red.withAlpha(200) : Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: _isTrackingFailure ? Border.all(color: Colors.red, width: 2) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isTrackingFailure ? Icons.warning_amber_rounded : Icons.info_outline, 
                        color: Colors.white, 
                        size: 20
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Real-time Path Minimap & Manual Control
                if (_scannedPoints.isNotEmpty || !_isWarmingUp)
                  Column(
                    children: [
                      if (_scannedPoints.isNotEmpty)
                        Container(
                          width: 140,
                          height: 140,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(70),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ClipOval(
                            child: CustomPaint(
                              painter: PathPainter(_scannedPoints),
                            ),
                          ),
                        ),
                      if (!_isWarmingUp)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: OutlinedButton.icon(
                            onPressed: _addCurrentPoint,
                            icon: const Icon(Icons.add_location_alt_rounded),
                            label: const Text("PIN CURRENT POSITION"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                const Spacer(),
                
                // Point counters & Stats
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _pointBadge("POINTS", _scannedPoints.length, RoverTheme.secondary),
                      _pointBadge("AREA", _areaText, Colors.blue),
                      _pointBadge("RES", "${_cellSizeCm.toInt()}cm", Colors.orange),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Action Buttons
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withAlpha(178)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isScanning && _scannedPoints.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _buildResolutionSelector(),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: (_isWarmingUp) ? null : _toggleScanning,
                          icon: Icon(_isScanning ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                          label: Text(_isWarmingUp ? "WARMING UP..." : (_isScanning ? "PAUSE AUTO-SCAN" : "START AUTO-SCANNING")),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isScanning ? Colors.orange : Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: (_scannedPoints.isNotEmpty && !_calculating) ? _generateMap : null,
                          icon: _calculating 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.map_rounded),
                          label: Text(_calculating ? "GENERATING..." : "GENERATE GRID MAP"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: RoverTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionSelector() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "SCAN RESOLUTION",
          style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 10.0, label: Text('10cm'), icon: Icon(Icons.grid_view_rounded)),
            ButtonSegment(value: 20.0, label: Text('20cm'), icon: Icon(Icons.grid_4x4_rounded)),
            ButtonSegment(value: 30.0, label: Text('30cm'), icon: Icon(Icons.grid_on_rounded)),
          ],
          selected: {_cellSizeCm},
          onSelectionChanged: (Set<double> newSelection) {
            setState(() {
              _cellSizeCm = newSelection.first;
            });
          },
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.black38,
            selectedBackgroundColor: RoverTheme.primary,
            selectedForegroundColor: Colors.white,
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
          ),
        ),
      ],
    );
  }

  Widget _pointBadge(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(51),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(128)),
      ),
      child: Text(
        "$label: $value",
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  String get _areaText {
    if (_scannedPoints.isEmpty) return "0.0m x 0.0m";
    double minX = _scannedPoints[0].x, maxX = _scannedPoints[0].x;
    double minZ = _scannedPoints[0].z, maxZ = _scannedPoints[0].z;
    for (var p in _scannedPoints) {
      if (p.x < minX) minX = p.x; if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z; if (p.z > maxZ) maxZ = p.z;
    }
    // Update: If area is still 0.0, show "Scanning..."
    final w = maxX - minX;
    final h = maxZ - minZ;
    if (w < 0.1 && h < 0.1) return "Localizing...";
    return "${w.toStringAsFixed(1)}m x ${h.toStringAsFixed(1)}m";
  }

}

class PathPainter extends CustomPainter {
  final List<v.Vector3> points;
  PathPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Normalize points to fit in the 150x150 circle
    double minX = points[0].x, maxX = points[0].x;
    double minZ = points[0].z, maxZ = points[0].z;
    for (var p in points) {
      if (p.x < minX) minX = p.x; if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z; if (p.z > maxZ) maxZ = p.z;
    }

    double rangeX = (maxX - minX).abs();
    double rangeZ = (maxZ - minZ).abs();
    double scale = 1.0;
    
    if (rangeX > 0 || rangeZ > 0) {
      scale = (size.width * 0.7) / (rangeX > rangeZ ? rangeX : rangeZ);
      if (scale > 100) scale = 100; // Limit zoom
    }

    final center = Offset(size.width / 2, size.height / 2);
    final List<Offset> offsets = [];

    for (var p in points) {
      final dx = (p.x - (minX + maxX) / 2) * scale;
      final dy = (p.z - (minZ + maxZ) / 2) * scale;
      offsets.add(center + Offset(dx, dy));
    }

    canvas.drawPoints(ui.PointMode.points, offsets, paint);
    
    if (offsets.length > 1) {
      paint.color = Colors.greenAccent.withAlpha(100);
      paint.strokeWidth = 1.0;
      final path = Path()..moveTo(offsets[0].dx, offsets[0].dy);
      for (var i = 1; i < offsets.length; i++) {
        path.lineTo(offsets[i].dx, offsets[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    
    // Draw current position (last point)
    if (offsets.isNotEmpty) {
      canvas.drawCircle(offsets.last, 5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant PathPainter oldDelegate) => 
      oldDelegate.points.length != points.length;
}
