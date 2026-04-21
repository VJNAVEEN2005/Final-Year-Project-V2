import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';
import '../services/mqtt_service.dart';

class RoverControlScreen extends StatefulWidget {
  const RoverControlScreen({super.key});

  @override
  State<RoverControlScreen> createState() => _RoverControlScreenState();
}

class _RoverControlScreenState extends State<RoverControlScreen>
    with TickerProviderStateMixin {
  // ─── MQTT ─────────────────────────────────────────────────────────────────
  final MqttService _mqtt = MqttService.instance;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<String>? _dataSub;
  bool _isConnected = false;

  // ─── Telemetry ────────────────────────────────────────────────────────────
  double _obstacleDistCm = 0;
  bool _obstacleDetected = false;
  double _currentYaw = 0;

  // ─── Joystick ─────────────────────────────────────────────────────────────
  static const double _joystickRadius = 120.0; // outer circle radius
  static const double _handleRadius = 56.0;    // handle half-size
  static const double _deadZone = 22.0;        // min drag to trigger command

  Offset _handleOffset = Offset.zero; // relative to center
  String _currentCmd = 'stop';
  String _bearing = '--';
  double _speed = 0.0;
  double _actualSpeed = 0.0;
  double _wheelRpm = 0.0;

  // ─── Motor Speed ──────────────────────────────────────────────────────────
  double _motorSpeed = 50; // User-requested default speed (50-255 range)

  // ─── Animation ────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ─── Obstacle blink ───────────────────────────────────────────────────────
  late AnimationController _blinkController;
  late Animation<double> _blinkAnim;

  // ─── Distance Control ─────────────────────────────────────────────────────
  final TextEditingController _distController = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();

    // Pulse animation for connected indicator
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Blink animation for obstacle warning
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _blinkAnim = Tween<double>(begin: 0.3, end: 1.0).animate(_blinkController);

    // Subscribe to MQTT state
    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });
    _dataSub = _mqtt.dataStream.listen(_parseTelemetry);

    // Connect
    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    await _mqtt.connect();
    if (mounted) setState(() => _isConnected = _mqtt.isConnected);
  }

  void _parseTelemetry(String data) {
    if (!mounted) return;
    if (data == 'obstacle_detected') {
      setState(() {
        _obstacleDetected = true;
        _obstacleDistCm = 0;
      });
      return;
    }
    final parts = data.split(',');
    double? obs;
    double? spd;
    double? rpm;

    for (final part in parts) {
      if (part.startsWith('obs:')) {
        obs = double.tryParse(part.substring(4));
      } else if (part.startsWith('spd:')) {
        spd = double.tryParse(part.substring(4));
      } else if (part.startsWith('rpm:')) {
        rpm = double.tryParse(part.substring(4));
      } else if (part.startsWith('yaw:')) {
        final yaw = double.tryParse(part.substring(4));
        if (yaw != null) _currentYaw = yaw;
      }
    }
    setState(() {
      if (obs != null) {
        _obstacleDistCm = obs;
        _obstacleDetected = obs > 0 && obs < 15;
      }
      if (spd != null) _actualSpeed = spd;
      if (rpm != null) _wheelRpm = rpm;
    });
  }

  // ─── Joystick Handlers ────────────────────────────────────────────────────

  Offset _clampToJoystick(Offset delta) {
    final dist = delta.distance;
    if (dist > _joystickRadius - _handleRadius) {
      return delta / dist * (_joystickRadius - _handleRadius);
    }
    return delta;
  }

  String _directionFromOffset(Offset offset) {
    if (offset.distance < _deadZone) return 'stop';
    final angle = atan2(offset.dy, offset.dx) * 180 / pi;
    // Joystick: up=forward, down=backward, left=turn left, right=turn right
    if (angle > -135 && angle < -45) return 'forward';
    if (angle >= -45 && angle <= 45) return 'right';
    if (angle > 45 && angle < 135) return 'backward';
    if (angle >= 135 || angle <= -135) return 'left';
    return 'stop';
  }

  String _bearingFromOffset(Offset offset) {
    if (offset.distance < _deadZone) return '--';
    final angle = atan2(-offset.dy, offset.dx) * 180 / pi;
    final deg = (angle + 360) % 360;
    final dirs = ['E', 'NE', 'N', 'NW', 'W', 'SW', 'S', 'SE'];
    final idx = ((deg + 22.5) / 45).floor() % 8;
    return '${deg.round()}° ${dirs[idx]}';
  }

  double _speedFromOffset(Offset offset) {
    final ratio = (offset.distance / (_joystickRadius - _handleRadius)).clamp(0.0, 1.0);
    return ratio * 1.4;
  }

  void _onPanEnd() {
    setState(() {
      _handleOffset = Offset.zero;
      _bearing = '--';
      _speed = 0.0;
      _currentCmd = 'stop';
    });
    _mqtt.publish('stop');
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _dataSub?.cancel();
    _pulseController.dispose();
    _blinkController.dispose();
    _distController.dispose();
    _mqtt.publish('stop');
    super.dispose();
  }

  void _moveDistance() {
    final t = _distController.text.trim();
    if (t.isNotEmpty) {
      _mqtt.publish('move:$t');
    }
  }

  Future<void> _turn90(bool isLeft) async {
    if (!_isConnected) return;
    
    final cmd = isLeft ? 'left90' : 'right90';
    _mqtt.publish(cmd);
    
    final completer = Completer<void>();
    StreamSubscription? doneSub = _mqtt.doneStream.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    
    await Future.any([
      completer.future,
      Future.delayed(const Duration(milliseconds: 3500)),
    ]);
    doneSub?.cancel();
    
    _mqtt.publish('stop');
  }


  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.settings_remote, color: RoverTheme.primary),
            const SizedBox(width: 12),
            Text(
              'Rover Control',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => _MqttStatusChip(
                isConnected: _isConnected,
                pulseValue: _pulseAnim.value,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: _buildObstacleBanner(theme),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              decoration: BoxDecoration(
                color: RoverTheme.surfaceContainerHigh.withOpacity(0.5),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: RoverTheme.outlineVariant.withOpacity(0.4)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('JOYSTICK', style: TextStyle(fontSize: 9, letterSpacing: 2)),
                      SizedBox(width: 40),
                      Text('SPEED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2, color: RoverTheme.secondary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildJoystick(),
                      const SizedBox(width: 12),
                      _buildVerticalSpeedSlider(),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _buildMetric('TARGET', '${_speed.toStringAsFixed(1)} m/s', Icons.track_changes_rounded),
                      _buildMetric('ACTUAL', '${_actualSpeed.toStringAsFixed(1)} cm/s', Icons.speed_rounded),
                      _buildMetric('WHEEL', '${_wheelRpm.toStringAsFixed(0)} RPM', Icons.settings_input_component_rounded),
                      _buildMetric('BEARING', _bearing, Icons.explore_rounded),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildDistanceControl(theme),
            const SizedBox(height: 16),
            _buildTurnControl(theme),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ... rest of the build helpers ...
  Widget _buildObstacleBanner(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _obstacleDetected ? Colors.red.withOpacity(0.1) : RoverTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _obstacleDetected ? Colors.red.withOpacity(0.5) : RoverTheme.outlineVariant.withOpacity(0.3), width: _obstacleDetected ? 1.5 : 1),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _blinkAnim,
            builder: (_, __) => Icon(
              _obstacleDetected ? Icons.warning_amber_rounded : Icons.sensors_rounded,
              color: _obstacleDetected ? Colors.red.withOpacity(_blinkAnim.value) : RoverTheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OBSTACLE DETECTION', style: theme.textTheme.labelSmall?.copyWith(fontSize: 8, color: _obstacleDetected ? Colors.red.withOpacity(0.8) : RoverTheme.secondary.withOpacity(0.7))),
                const SizedBox(height: 2),
                Text(_obstacleDetected ? '⚠  Obstacle detected!' : 'Path is clear', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: _obstacleDetected ? Colors.red : null)),
              ],
            ),
          ),
          if (_obstacleDistCm > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: _obstacleDetected ? Colors.red.withOpacity(0.15) : RoverTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${_obstacleDistCm.toStringAsFixed(1)} cm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _obstacleDetected ? Colors.red : RoverTheme.primary)),
            ),
        ],
      ),
    );
  }

  Widget _buildJoystick() {
    const outerSize = _joystickRadius * 2;
    const center = Offset(_joystickRadius, _joystickRadius);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final local = d.localPosition - center;
        final clamped = _clampToJoystick(local);
        final cmd = _directionFromOffset(clamped);
        setState(() {
          _handleOffset = clamped;
          _bearing = _bearingFromOffset(clamped);
          _speed = _speedFromOffset(clamped);
        });
        if (cmd != _currentCmd) {
          _currentCmd = cmd;
          _mqtt.publish(cmd);
        }
      },
      onPanEnd: (_) => _onPanEnd(),
      onPanCancel: () => _onPanEnd(),
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: outerSize, height: outerSize, decoration: BoxDecoration(shape: BoxShape.circle, color: RoverTheme.surfaceContainerHighest.withOpacity(0.6), border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.35), width: 1.5))),
            Positioned(top: 8, child: Icon(Icons.keyboard_arrow_up_rounded, color: _currentCmd == 'forward' ? RoverTheme.primary : RoverTheme.secondary.withOpacity(0.35))),
            Positioned(bottom: 8, child: Icon(Icons.keyboard_arrow_down_rounded, color: _currentCmd == 'backward' ? RoverTheme.primary : RoverTheme.secondary.withOpacity(0.35))),
            Positioned(left: 8, child: Icon(Icons.keyboard_arrow_left_rounded, color: _currentCmd == 'left' ? RoverTheme.primary : RoverTheme.secondary.withOpacity(0.35))),
            Positioned(right: 8, child: Icon(Icons.keyboard_arrow_right_rounded, color: _currentCmd == 'right' ? RoverTheme.primary : RoverTheme.secondary.withOpacity(0.35))),
            AnimatedContainer(
              duration: _handleOffset == Offset.zero ? const Duration(milliseconds: 200) : Duration.zero,
              curve: Curves.elasticOut,
              transform: Matrix4.translationValues(_handleOffset.dx, _handleOffset.dy, 0),
              width: _handleRadius * 2,
              height: _handleRadius * 2,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: _currentCmd == 'stop' ? [RoverTheme.primary, const Color(0xFF8A4518)] : [RoverTheme.primary.withOpacity(0.9), const Color(0xFF5A2508)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: const Center(child: Icon(Icons.videogame_asset_rounded, color: Colors.white, size: 40)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSpeedSlider() {
    const sliderHeight = _joystickRadius * 2;
    final pct = ((_motorSpeed - 50) / (255 - 50)).clamp(0.0, 1.0);
    return SizedBox(
      width: 60,
      height: sliderHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: RoverTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text('${_motorSpeed.round()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: RoverTheme.primary))),
          Expanded(child: Center(child: RotatedBox(quarterTurns: 3, child: SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: RoverTheme.primary, trackHeight: 5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)), child: Slider(value: _motorSpeed, min: 50, max: 255, divisions: 41, onChanged: (val) => setState(() => _motorSpeed = val), onChangeEnd: (val) => _mqtt.publish('speed:${val.round()}')))))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: RoverTheme.surfaceContainerHighest.withOpacity(0.6), borderRadius: BorderRadius.circular(8)), child: Text(pct < 0.35 ? 'SLOW' : pct < 0.70 ? 'MED' : 'FAST', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: pct < 0.35 ? Colors.green : pct < 0.70 ? Colors.orange : Colors.red))),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, IconData icon) {
    return Column(children: [Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: RoverTheme.secondary), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.4, color: RoverTheme.secondary))]), const SizedBox(height: 6), Text(value, style: const TextStyle(fontFamily: 'EB Garamond', fontSize: 20, color: RoverTheme.primary, fontWeight: FontWeight.bold))]);
  }

  Widget _buildDistanceControl(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: RoverTheme.surfaceContainerLow.withOpacity(0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.3))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('CUSTOM DISTANCE', style: theme.textTheme.labelSmall?.copyWith(fontSize: 8, letterSpacing: 1.5, color: RoverTheme.secondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      height: 40,
                      child: TextField(
                        controller: _distController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: RoverTheme.primary),
                        decoration: InputDecoration(hintText: '0', contentPadding: EdgeInsets.zero, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: RoverTheme.outlineVariant)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: RoverTheme.primary, width: 2))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('cm', style: TextStyle(fontWeight: FontWeight.bold, color: RoverTheme.secondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isConnected ? _moveDistance : null,
              style: ElevatedButton.styleFrom(backgroundColor: RoverTheme.primary, foregroundColor: Colors.white, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 24)),
              child: Row(children: [const Icon(Icons.navigation_rounded, size: 18), const SizedBox(width: 8), Text('MOVE', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white))]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnControl(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: RoverTheme.surfaceContainerLow.withOpacity(0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('90° QUICK TURNS', style: theme.textTheme.labelSmall?.copyWith(fontSize: 8, letterSpacing: 1.5, color: RoverTheme.secondary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnected ? () => _turn90(true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: RoverTheme.surfaceContainerHigh, foregroundColor: RoverTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                  icon: const Icon(Icons.rotate_left_rounded),
                  label: const Text('LEFT 90°'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnected ? () => _turn90(false) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: RoverTheme.surfaceContainerHigh, foregroundColor: RoverTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                  icon: const Icon(Icons.rotate_right_rounded),
                  label: const Text('RIGHT 90°'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(color: RoverTheme.background.withOpacity(0.95), border: const Border(top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildNavItem(context, Icons.sensors, 'STATUS', route: '/status'), _buildNavItem(context, Icons.videogame_asset, 'CONTROL', route: '/control', active: true), _buildNavItem(context, Icons.map_rounded, 'MAPS', route: '/maps'), _buildNavItem(context, Icons.auto_awesome, 'AI', route: '/ai'), _buildNavItem(context, Icons.settings, 'SETTINGS', route: '/settings')]),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, {required String route, bool active = false}) {
    return InkWell(
      onTap: active ? null : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: active ? RoverTheme.primary.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: active ? RoverTheme.primary : RoverTheme.secondary, size: 22), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: active ? RoverTheme.primary : RoverTheme.secondary))]),
      ),
    );
  }
}

class _MqttStatusChip extends StatelessWidget {
  final bool isConnected;
  final double pulseValue;
  const _MqttStatusChip({required this.isConnected, required this.pulseValue});
  @override
  Widget build(BuildContext context) {
    final color = isConnected ? Colors.green : Colors.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(isConnected ? pulseValue : 0.7), boxShadow: isConnected ? [BoxShadow(color: color.withOpacity(pulseValue * 0.5), blurRadius: 6, spreadRadius: 1)] : null)), const SizedBox(width: 5), Text(isConnected ? 'MQTT OK' : 'NO MQTT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: color))]),
    );
  }
}
