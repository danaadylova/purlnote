import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Purlnote's colors, matching the screen mockups.
abstract final class PurlnoteColors {
  /// Text and dark chips.
  static const plum = Color(0xFF3B1C34);

  /// Secondary text.
  static const plumMuted = Color(0xFF6E5566);

  /// Screen background: white with the faintest touch of plum. Also the
  /// light text on plum.
  static const cream = Color(0xFFFCFAFC);

  /// Segmented controls, panels and track backgrounds: a pale lilac.
  static const sand = Color(0xFFF1E9F0);

  /// Dividers.
  static const line = Color(0xFFE6DCE6);

  /// Text-field borders (3.4:1 against the background, enough for WCAG 2.2 AA).
  static const inputBorder = Color(0xFF958393);

  /// The top of the plum fade behind the main tabs, turning to [cream] by
  /// the bottom.
  static const lilacMist = Color(0xFFF3E8F1);

  /// The surface the pattern pages lie on in the reader: a muted mauve, so
  /// the white page reads as paper on a desk.
  static const desk = Color(0xFFE7E0E6);

  /// The reader's top bar and the segmented control in it.
  static const barLilac = Color(0xFFF6F1F5);
  static const barLilacDeep = Color(0xFFECE2EA);
  static const barEdge = Color(0xFFE4D9E2);

  /// The glow band: lighter plum where the light falls, deeper plum at the
  /// far edge.
  static const plumGlow = Color(0xFF6A3260);
  static const plumDeep = Color(0xFF2A1325);

  /// Buttons, active tab, links.
  static const moss = Color(0xFF3F5C37);
  static const mossDark = Color(0xFF2F4729);

  /// Selected states and "ready" badges.
  static const mossLight = Color(0xFFE3ECD8);

  /// Note pins, row highlight, progress.
  static const marigold = Color(0xFFE7A33E);

  /// Pen ink and the row ruler's edges.
  static const marigoldDark = Color(0xFFC9822A);

  /// Warnings and the offline banner.
  static const blush = Color(0xFFF4CDBE);
  static const brown = Color(0xFF8A5A2B);
}

/// The soft fade behind the Notebook, Library and More: lilac at the top,
/// near-white at the bottom.
const plumFade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0, 0.7],
  colors: [PurlnoteColors.lilacMist, PurlnoteColors.cream],
);

/// The plum band at the top of the Notebook: light falls from the top left
/// and fades to deep plum.
const plumGlowBand = RadialGradient(
  center: Alignment(-0.6, -1),
  radius: 1.4,
  stops: [0, 0.55, 1],
  colors: [PurlnoteColors.plumGlow, PurlnoteColors.plum, PurlnoteColors.plumDeep],
);

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
      // Dark status bar icons, also over the see-through bars of the More and
      // Library tabs (a see-through bar would otherwise get light icons).
      systemOverlayStyle: SystemUiOverlayStyle.dark,
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
