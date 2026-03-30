import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/rover_splash_screen.dart';
import 'screens/rover_status_screen.dart';
import 'screens/rover_control_screen.dart';
import 'screens/rover_settings_screen.dart';
import 'theme/rover_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const RoverApp());
}

class RoverApp extends StatelessWidget {
  const RoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rover App',
      debugShowCheckedModeBanner: false,
      theme: RoverTheme.lightTheme,
      home: const RoverSplashScreen(),
      routes: {
        '/status': (context) => const RoverStatusScreen(),
        '/control': (context) => const RoverControlScreen(),
        '/settings': (context) => const RoverSettingsScreen(),
      },
    );
  }
}
