import 'package:flutter/material.dart';

class AppTheme {
  // Palette
  static const Color background = Color(0xFF090A0F);
  static const Color surface = Color(0xFF12141F);
  static const Color surfaceLight = Color(0xFF1B1E2E);
  static const Color border = Color(0xFF26293D);

  // Accents
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color purpleAccent = Color(0xFF7C4DFF);
  static const Color emeraldAccent = Color(0xFF00E676);
  static const Color textPrimary = Color(0xFFF0F2F8);
  static const Color textSecondary = Color(0xFF8E95AA);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: cyanAccent,
      colorScheme: const ColorScheme.dark(
        primary: cyanAccent,
        secondary: purpleAccent,
        surface: surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: cyanAccent,
        unselectedItemColor: textSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
