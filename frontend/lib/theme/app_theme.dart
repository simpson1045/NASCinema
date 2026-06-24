import 'package:flutter/material.dart';

/// NASCinema "Blockbuster cyberpunk" palette — shares NASRadio's deep-navy base
/// and frosted-glass grammar, but with a marquee amber + violet accent so it
/// reads "movies" at a glance.
class NasColors {
  static const bg = Color(0xFF0A0E27); // app canvas
  static const surface = Color(0xFF141A35); // cards, sheets
  static const surfaceRaised = Color(0xFF1D2547); // posters, inputs
  static const amber = Color(0xFFFFB020); // primary accent
  static const violet = Color(0xFFB46BFF); // secondary accent
  static const text = Color(0xFFEEF1FF); // primary text
  static const muted = Color(0xFF8B93BF); // secondary text
  static const ok = Color(0xFF2EE696); // healthy / direct-play
  static const bad = Color(0xFFFF5C6C); // error / unavailable
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: NasColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: NasColors.amber,
        onPrimary: NasColors.bg,
        secondary: NasColors.violet,
        onSecondary: NasColors.bg,
        surface: NasColors.surface,
        onSurface: NasColors.text,
        error: NasColors.bad,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: NasColors.text, displayColor: NasColors.text),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: NasColors.text,
      ),
      cardTheme: CardThemeData(
        color: NasColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NasColors.surfaceRaised,
        hintStyle: const TextStyle(color: NasColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NasColors.amber, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NasColors.amber,
          foregroundColor: NasColors.bg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
