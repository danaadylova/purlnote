import 'package:flutter/material.dart';

/// Purlnote's colors, matching the screen mockups.
abstract final class PurlnoteColors {
  /// Text and dark chips.
  static const plum = Color(0xFF3B1C34);

  /// Secondary text.
  static const plumMuted = Color(0xFF6E5566);

  /// Screen background.
  static const cream = Color(0xFFFFF8EE);

  /// Segmented controls and track backgrounds.
  static const sand = Color(0xFFF1E6D8);

  /// Dividers.
  static const line = Color(0xFFEADDCB);

  /// Text-field borders (3.3:1 against cream, enough for WCAG 2.2 AA).
  static const inputBorder = Color(0xFF9A8576);

  /// Buttons, active tab, links.
  static const moss = Color(0xFF3F5C37);
  static const mossDark = Color(0xFF2F4729);

  /// Selected states and "ready" badges.
  static const mossLight = Color(0xFFE3ECD8);

  /// Note pins, row highlight, progress.
  static const marigold = Color(0xFFE7A33E);

  /// Warnings and the offline banner.
  static const blush = Color(0xFFF4CDBE);
  static const brown = Color(0xFF8A5A2B);
}

ThemeData buildPurlnoteTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: PurlnoteColors.moss,
    primary: PurlnoteColors.moss,
    onPrimary: Colors.white,
    surface: PurlnoteColors.cream,
    onSurface: PurlnoteColors.plum,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: PurlnoteColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: PurlnoteColors.cream,
      foregroundColor: PurlnoteColors.plum,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: PurlnoteColors.plum),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: PurlnoteColors.plum),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: PurlnoteColors.plum),
      bodyMedium: TextStyle(color: PurlnoteColors.plum),
      bodySmall: TextStyle(color: PurlnoteColors.plumMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PurlnoteColors.moss,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    dividerColor: PurlnoteColors.line,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PurlnoteColors.moss,
      linearTrackColor: PurlnoteColors.sand,
    ),
  );
}
