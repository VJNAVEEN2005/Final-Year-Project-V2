import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';
import '../services/mqtt_service.dart';

class RoverSettingsScreen extends StatefulWidget {
  const RoverSettingsScreen({super.key});

  @override
  State<RoverSettingsScreen> createState() => _RoverSettingsScreenState();
}

class _RoverSettingsScreenState extends State<RoverSettingsScreen> {
  double _speedLimit = 1.5;

  void _showSpeedLimiterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Speed Limiter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_speedLimit.toStringAsFixed(1)} m/s', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Slider(
              value: _speedLimit,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              onChanged: (value) => setState(() => _speedLimit = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _speedLimit = 1.5);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Speed limit reset to 1.5 m/s')),
              );
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Speed limit set to ${_speedLimit.toStringAsFixed(1)} m/s')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _testConnection(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing connection...')),
    );
    final mqtt = MqttService.instance;
    if (mqtt.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection successful!'), backgroundColor: Colors.green),
      );
    } else {
      await mqtt.connect();
      await Future.delayed(const Duration(seconds: 2));
      if (mqtt.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection successful!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection failed'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetToDefault(BuildContext context) {
    setState(() => _speedLimit = 1.5);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Services reset to default')),
    );
  }

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
            Text('Rover App', style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
          ],
        ),
        actions: const [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.headlineLarge?.copyWith(fontSize: 32)),
            const SizedBox(height: 8),
            const Text(
              'Configure your rover\'s system parameters and hardware links.',
              style: TextStyle(color: RoverTheme.secondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('CONNECTION SETTINGS'),
            _buildSettingsGroup([
              _buildSettingItem(
                label: 'SSL Encryption',
                subLabel: 'Secure the telemetry stream',
                trailing: Switch(
                  value: true,
                  onChanged: (v) {},
                  activeColor: Colors.white,
                  activeTrackColor: RoverTheme.primaryContainer,
                ),
              ),
              _buildSettingItem(
                label: 'Connection Test',
                subLabel: 'Test MQTT broker connection',
                trailing: const Icon(Icons.chevron_right, color: RoverTheme.secondary),
                onTap: () => _testConnection(context),
              ),
              _buildSettingItem(
                label: 'Reset to Default',
                subLabel: 'Reset services to default',
                trailing: const Icon(Icons.restart_alt, color: RoverTheme.secondary),
                onTap: () => _resetToDefault(context),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSectionHeader('ROVER CONFIGURATION'),
            _buildSettingsGroup([
              _buildSettingItem(
                label: 'Speed Limiter',
                subLabel: 'Maximum operational velocity',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_speedLimit.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: RoverTheme.primary)),
                    const SizedBox(width: 8),
                    const Icon(Icons.speed, size: 16, color: RoverTheme.secondary),
                  ],
                ),
                onTap: () => _showSpeedLimiterDialog(context),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSectionHeader('ABOUT'),
            _buildSettingsGroup([
              _buildSettingItem(
                label: 'Version',
                trailing: const Text('2.4.0-build.82', style: TextStyle(color: RoverTheme.secondary, fontSize: 13)),
              ),
              _buildSettingItem(label: 'Developer Credits', trailing: const Icon(Icons.arrow_forward, size: 16, color: RoverTheme.secondary)),
              _buildSettingItem(label: 'Open Source Licenses', trailing: const Icon(Icons.list_alt, size: 16, color: RoverTheme.secondary)),
            ]),
            const SizedBox(height: 48),
            const Center(
              child: Text(
                '© 2024 ROVER DYNAMICS CORP.',
                style: TextStyle(color: RoverTheme.secondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 80,
        decoration: BoxDecoration(
          color: RoverTheme.background.withOpacity(0.95),
          border: const Border(top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(context, Icons.sensors, 'STATUS', route: '/status'),
            _buildNavItem(context, Icons.videogame_asset, 'CONTROL', route: '/control'),
            _buildNavItem(context, Icons.map_rounded, 'MAPS', route: '/maps'),
            _buildNavItem(context, Icons.auto_awesome, 'AI', route: '/ai'),
            _buildNavItem(context, Icons.settings, 'SETTINGS', route: '/settings', active: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(color: RoverTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: RoverTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingItem({required String label, String? subLabel, required Widget trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: RoverTheme.outlineVariant.withOpacity(0.3), width: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: RoverTheme.onSurface)),
                  if (subLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(subLabel, style: const TextStyle(fontSize: 12, color: RoverTheme.secondary)),
                  ],
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, {required String route, bool active = false}) {
    return InkWell(
      onTap: active ? null : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? RoverTheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? RoverTheme.primary : RoverTheme.secondary, size: 22),
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
