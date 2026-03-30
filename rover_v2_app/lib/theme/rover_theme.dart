import 'package:flutter/material.dart';

class RoverTheme {
  static const Color primary = Color(0xFFC2652A);
  static const Color primaryContainer = Color(0xFFE08850);
  static const Color onPrimary = Colors.white;
  static const Color background = Color(0xFFFAF5EE);
  static const Color surface = Color(0xFFFAF5EE);
  static const Color onSurface = Color(0xFF3A302A);
  static const Color secondary = Color(0xFF78706A);
  static const Color onSecondary = Colors.white;
  static const Color outlineVariant = Color(0xFFD8D0C8);
  static const Color surfaceContainerHigh = Color(0xFFECE6DC);
  static const Color surfaceContainerHighest = Color(0xFFE6E0D6);
  static const Color surfaceContainerLow = Color(0xFFF6F0E8);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        surface: surface,
        onSurface: onSurface,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Manrope',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'EB Garamond',
          fontWeight: FontWeight.bold,
          color: primary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'EB Garamond',
          fontWeight: FontWeight.bold,
          color: primary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'EB Garamond',
          fontWeight: FontWeight.bold,
          color: primary,
        ),
        bodyLarge: TextStyle(fontFamily: 'Manrope', color: onSurface),
        bodyMedium: TextStyle(fontFamily: 'Manrope', color: onSurface),
        labelSmall: TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontSize: 10,
          color: secondary,
        ),
      ),
    );
  }
}
