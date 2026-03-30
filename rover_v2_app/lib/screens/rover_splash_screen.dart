import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';
import '../services/mqtt_service.dart';
import 'rover_status_screen.dart';

class RoverSplashScreen extends StatefulWidget {
  const RoverSplashScreen({super.key});

  @override
  State<RoverSplashScreen> createState() => _RoverSplashScreenState();
}

class _RoverSplashScreenState extends State<RoverSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    // Start MQTT connection early so it's ready when Status screen opens
    MqttService.instance.connect();

    // Navigate to status screen after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const RoverStatusScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-1.2, 1.2),
                radius: 1.5,
                colors: [
                  Color(0xFFFBE8D8),
                  RoverTheme.background,
                ],
              ),
            ),
          ),
          // Atmospheric icon
          Positioned(
            top: 40,
            right: -40,
            child: Opacity(
              opacity: 0.05,
              child: Icon(Icons.light_mode, size: 280, color: RoverTheme.onSurface),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: RoverTheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: RoverTheme.outlineVariant.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.settings_remote, color: RoverTheme.primary, size: 40),
                ),
                const SizedBox(height: 48),
                // Headline
                const Text(
                  'Rover App',
                  style: TextStyle(
                    fontFamily: 'EB Garamond',
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: RoverTheme.primary,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'PRECISION EXPLORATION INTERFACE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: RoverTheme.secondary.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 48),
                // Divider
                Container(
                  width: 200,
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        RoverTheme.outlineVariant.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                // Loading bar
                Column(
                  children: [
                    Container(
                      width: 180,
                      height: 2,
                      decoration: BoxDecoration(
                        color: RoverTheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: AnimatedBuilder(
                        animation: _shimmerAnimation,
                        builder: (context, child) {
                          return FractionalTranslation(
                            translation: Offset(_shimmerAnimation.value, 0),
                            child: Container(
                              width: 60,
                              decoration: BoxDecoration(
                                color: RoverTheme.primary,
                                borderRadius: BorderRadius.circular(1),
                                boxShadow: [
                                  BoxShadow(
                                    color: RoverTheme.primary.withOpacity(0.4),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'INITIALIZING TELEMETRY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: RoverTheme.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Footer
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: 0.4,
              child: Column(
                children: [
                  const Text(
                    'CRAFTED FOR ARID ENVIRONMENTS',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.sensors, size: 14),
                      SizedBox(width: 16),
                      Icon(Icons.wifi_tethering, size: 14),
                      SizedBox(width: 16),
                      Icon(Icons.navigation, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
