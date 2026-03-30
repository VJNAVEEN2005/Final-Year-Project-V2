import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';
import '../services/mqtt_service.dart';

class RoverStatusScreen extends StatefulWidget {
  const RoverStatusScreen({super.key});

  @override
  State<RoverStatusScreen> createState() => _RoverStatusScreenState();
}

class _RoverStatusScreenState extends State<RoverStatusScreen>
    with TickerProviderStateMixin {
  // ─── MQTT ─────────────────────────────────────────────────────────────────
  final MqttService _mqtt = MqttService.instance;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<bool>? _roverSub;
  StreamSubscription<String>? _dataSub;
  bool _isConnected = false;
  bool _isRoverOnline = false;
  bool _isRetrying = false;

  // ─── Telemetry ────────────────────────────────────────────────────────────
  double _obstacleDistCm = 0;
  bool _obstacleDetected = false;

  // ─── Animations ───────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  late AnimationController _spinController;
  late Animation<double> _spinAnim;

  late AnimationController _roverPulseController;
  late Animation<double> _roverPulseAnim;

  @override
  void initState() {
    super.initState();

    // Broker dot pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Retry spin
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _spinAnim = Tween<double>(begin: 0, end: 1).animate(_spinController);

    // Rover dot pulse
    _roverPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _roverPulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _roverPulseController, curve: Curves.easeInOut),
    );

    _isConnected = _mqtt.isConnected;
    _isRoverOnline = _mqtt.isRoverOnline;

    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _roverSub = _mqtt.roverStatusStream.listen((online) {
      if (mounted) setState(() => _isRoverOnline = online);
    });

    _dataSub = _mqtt.dataStream.listen(_parseTelemetry);

    if (!_mqtt.isConnected) _mqtt.connect();
  }

  void _parseTelemetry(String data) {
    if (!mounted) return;
    if (data == 'obstacle_detected') {
      setState(() { _obstacleDetected = true; _obstacleDistCm = 0; });
      return;
    }
    for (final part in data.split(',')) {
      if (part.startsWith('obs:')) {
        final obs = double.tryParse(part.substring(4));
        if (obs != null && mounted) {
          setState(() {
            _obstacleDistCm = obs;
            _obstacleDetected = obs > 0 && obs < 15;
          });
        }
      }
    }
  }

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    _spinController.repeat();
    await _mqtt.connect();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      _spinController.stop();
      _spinController.reset();
      setState(() => _isRetrying = false);
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _roverSub?.cancel();
    _dataSub?.cancel();
    _pulseController.dispose();
    _spinController.dispose();
    _roverPulseController.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
            Text('Rover App',
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: RoverTheme.secondary),
            onPressed: () {},
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuBT69SI3ea5NW8VsHLYie1GK4Hq6ksHxC7XinuF2Hgj7Gq_R7Qu867IADCyeNSo3nbzWdEdoe5VBwfmpie6zpWo7o5iNjyhwBRbIzGWTAP_xsELCLcPmEYz27zo6Zfir1KHaD8aOhTfSTR1_m0TlnuNLnwAHDHDF7MbZ2QhieW-2zxhLFyhmh6KuczX1hY7gtYwYwJoVwxWIq3I-G3zFHrGQJ5yWwINCld0i_WnuKCLdQOKoqRxtj-3_v4mJazfRWxW971W8jtOq_k',
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Text('Mission Dashboard',
                style: theme.textTheme.headlineLarge?.copyWith(fontSize: 32)),
            const SizedBox(height: 4),
            Text('ROVER UNIT: R-01 "DEFAULT"',
                style: theme.textTheme.labelSmall),
            const SizedBox(height: 32),

            // ── Obstacle Alert (live) ────────────────────────────────────────
            if (_obstacleDetected || _obstacleDistCm > 0) ...[
              _buildObstacleCard(),
              const SizedBox(height: 24),
            ],

            // ── Battery Card ─────────────────────────────────────────────────
            _buildBatteryCard(theme),
            const SizedBox(height: 24),

            // ── Signal + Rover Status Cards ──────────────────────────────────
            Row(
              children: [
                Expanded(child: _buildBrokerLinkCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildRoverStatusCard()),
              ],
            ),
            const SizedBox(height: 32),

            Text('System Telemetry',
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 24)),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.2,
              children: [
                _buildTelemetryItem(
                    Icons.satellite_alt, 'MQTT BROKER',
                    _isConnected ? 'Connected' : 'Offline',
                    valueColor: _isConnected ? Colors.green[700] : Colors.red[700]),
                _buildTelemetryItem(
                    Icons.settings_remote, 'ROVER',
                    _isRoverOnline ? 'Online' : 'Offline',
                    valueColor: _isRoverOnline ? Colors.green[700] : Colors.red[700]),
                _buildTelemetryItem(
                    Icons.radar, 'OBS DISTANCE',
                    _obstacleDistCm > 0
                        ? '${_obstacleDistCm.toStringAsFixed(1)} cm'
                        : '--'),
                _buildTelemetryItem(Icons.storage, 'CMD TOPIC', 'rover/cmd'),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ─── Broker Link Card (animated + retry) ──────────────────────────────────

  Widget _buildBrokerLinkCard() {
    final isOnline = _isConnected;
    final dotColor = isOnline ? Colors.green : Colors.orange;
    final bgColor = isOnline
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFF3E0);
    final borderColor = isOnline
        ? Colors.green.withOpacity(0.35)
        : Colors.orange.withOpacity(0.35);
    final labelColor = isOnline
        ? const Color(0xFF2E7D32)
        : const Color(0xFFE65100);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: dotColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Animated pulsing dot
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withOpacity(
                        isOnline ? _pulseAnim.value : 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withOpacity(
                            isOnline ? _pulseAnim.value * 0.5 : 0.2),
                        blurRadius: isOnline ? 8 : 4,
                        spreadRadius: isOnline ? 2 : 0,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'BROKER LINK',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: labelColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontFamily: 'EB Garamond',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isOnline ? 'EMQX Cloud' : 'Not connected',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: labelColor.withOpacity(0.7),
            ),
          ),
          // Retry button (only when offline)
          if (!isOnline) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _retry,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.orange.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _spinAnim,
                      builder: (_, child) => Transform.rotate(
                        angle: _spinAnim.value * 2 * 3.14159,
                        child: child,
                      ),
                      child: const Icon(Icons.refresh_rounded,
                          size: 14, color: Color(0xFFE65100)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isRetrying ? 'Retrying…' : 'Retry',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Rover Status Card (animated) ─────────────────────────────────────────

  Widget _buildRoverStatusCard() {
    final isOnline = _isRoverOnline;
    final dotColor = isOnline ? Colors.green : Colors.red;
    final bgColor = isOnline
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFCE4EC);
    final borderColor = isOnline
        ? Colors.green.withOpacity(0.35)
        : Colors.red.withOpacity(0.3);
    final labelColor = isOnline
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: dotColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _roverPulseAnim,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withOpacity(
                        isOnline ? _roverPulseAnim.value : 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withOpacity(
                            isOnline ? _roverPulseAnim.value * 0.5 : 0.15),
                        blurRadius: isOnline ? 8 : 3,
                        spreadRadius: isOnline ? 2 : 0,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ROVER STATUS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: labelColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontFamily: 'EB Garamond',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isOnline ? 'ESP32 reachable' : 'Not responding',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: labelColor.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          // Visual "heartbeat" bar — only shown when rover is online
          AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: isOnline ? 1.0 : 0.0,
            child: AnimatedBuilder(
              animation: _roverPulseAnim,
              builder: (_, __) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _roverPulseAnim.value,
                  minHeight: 4,
                  backgroundColor: Colors.green.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.green.withOpacity(0.7)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Obstacle Card ────────────────────────────────────────────────────────

  Widget _buildObstacleCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _obstacleDetected
            ? Colors.red.withOpacity(0.08)
            : RoverTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _obstacleDetected
              ? Colors.red.withOpacity(0.4)
              : RoverTheme.outlineVariant.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _obstacleDetected
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            color: _obstacleDetected ? Colors.red : Colors.green,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _obstacleDetected
                  ? 'Obstacle at ${_obstacleDistCm.toStringAsFixed(1)} cm — motors stopped'
                  : 'Path clear — ${_obstacleDistCm.toStringAsFixed(1)} cm ahead',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _obstacleDetected ? Colors.red[700] : Colors.green[700],
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Battery Card ─────────────────────────────────────────────────────────

  Widget _buildBatteryCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('POWER RESERVE', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('85',
                          style: theme.textTheme.headlineLarge
                              ?.copyWith(fontSize: 72, height: 1)),
                      Text('%',
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontSize: 24)),
                    ],
                  ),
                ],
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ESTIMATED RANGE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: RoverTheme.secondary)),
                  SizedBox(height: 4),
                  Text('14.2 km',
                      style: TextStyle(
                          fontFamily: 'EB Garamond',
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Discharge Rate: 1.2%/hr',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RoverTheme.secondary)),
              Text('Optimal Temperature',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RoverTheme.secondary)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const LinearProgressIndicator(
              value: 0.85,
              minHeight: 12,
              backgroundColor: RoverTheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(RoverTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Telemetry Item ───────────────────────────────────────────────────────

  Widget _buildTelemetryItem(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RoverTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RoverTheme.primary.withOpacity(0.1)),
            child: Icon(icon, color: RoverTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: RoverTheme.secondary)),
                Text(value,
                    style: TextStyle(
                        fontFamily: 'EB Garamond',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: valueColor),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Nav ───────────────────────────────────────────────────────────

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: RoverTheme.background.withOpacity(0.95),
        border: const Border(
            top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(context, Icons.sensors, 'STATUS',
              route: '/status', active: true),
          _buildNavItem(context, Icons.videogame_asset, 'CONTROL',
              route: '/control'),
          _buildNavItem(context, Icons.settings, 'SETTINGS',
              route: '/settings'),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label,
      {required String route, bool active = false}) {
    return InkWell(
      onTap: active ? null : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color:
              active ? RoverTheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active ? RoverTheme.primary : RoverTheme.secondary,
                size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: active ? RoverTheme.primary : RoverTheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
