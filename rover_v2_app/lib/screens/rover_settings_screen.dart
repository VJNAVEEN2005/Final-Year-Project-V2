import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';

class RoverSettingsScreen extends StatelessWidget {
  const RoverSettingsScreen({super.key});

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
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: RoverTheme.secondary),
            onPressed: () {},
          ),
        ],
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
                label: 'IP address',
                subLabel: 'Primary rover control host',
                trailing: const Text('192.168.1.42', style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: RoverTheme.onSurface)),
              ),
              _buildSettingItem(
                label: 'Port',
                subLabel: 'WebSocket communication port',
                trailing: const Text('8080', style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: RoverTheme.onSurface)),
              ),
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
            ]),
            const SizedBox(height: 32),
            _buildSectionHeader('ROVER CONFIGURATION'),
            _buildSettingsGroup([
              _buildSettingItem(
                label: 'Speed Limit',
                subLabel: 'Maximum operational velocity (m/s)',
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('1.5', style: TextStyle(fontWeight: FontWeight.bold, color: RoverTheme.primary)),
                    SizedBox(width: 8),
                    Icon(Icons.speed, size: 16, color: RoverTheme.secondary),
                  ],
                ),
              ),
              _buildSettingItem(
                label: 'Camera Resolution',
                subLabel: 'Live feed visual quality',
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('1080p (60fps)', style: TextStyle(fontSize: 13, color: RoverTheme.onSurface)),
                    SizedBox(width: 4),
                    Icon(Icons.expand_more, size: 16, color: RoverTheme.secondary),
                  ],
                ),
              ),
              _buildSettingItem(
                label: 'Auto-Night Vision',
                subLabel: 'Engage IR filter in low light',
                trailing: Switch(
                  value: false,
                  onChanged: (v) {},
                ),
              ),
            ]),
            const SizedBox(height: 32),
            // Hardware Visual Card
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: const DecorationImage(
                  image: NetworkImage(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuCEakGS-ih6KmAo0GBJbr9Ljc7ieOShrv3QrIQTBzNUpDerNkNgDXAb9pt3dSBwkQBhcDUBLNXz9Am12yCwTrUcXJzdUScMwZfE6J6khVmDnujeubqtHKvoNRCd6l4X-7tFtJC5ZnHBNMPMsFWbotlhKDD7x4H8ek6wGIr-0BUywZcIvfhkGAxAxK3yz25hbm80Ei-0ZRXE4U2olW4MAHmZg9W1cAKOSnlmyPGSCIHXJG7MKzKeHhYoQdEJ9WZPkxe8PqHDFXjRBhQ',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hardware Diagnostics',
                      style: TextStyle(color: Colors.white, fontFamily: 'EB Garamond', fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'SYSTEM HEALTH: OPTIMAL',
                      style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
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

  Widget _buildSettingItem({required String label, String? subLabel, required Widget trailing}) {
    return Container(
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
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, {required String route, bool active = false}) {
    return InkWell(
      onTap: active ? null : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? RoverTheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? RoverTheme.primary : RoverTheme.secondary, size: 24),
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
