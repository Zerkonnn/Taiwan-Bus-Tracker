// App theme — mirrors src/utils/theme.ts

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_strings.dart';
import '../design/tokens.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
// Legacy names kept so existing screens compile; they now point at the design
// tokens (lib/design/tokens.dart). New code should use AppPalette directly.

class AppColors {
  static const bg = AppPalette.canvas;
  static const bgCard = AppPalette.surfaceRaised;
  static const bgSheet = AppPalette.surface;
  static const bgInput = AppPalette.surfaceRaised;
  static const border = AppPalette.divider;
  static const borderActive = AppPalette.accent;

  // One accent: the former blue and green both map to it.
  static const blue = AppPalette.accent;
  static const green = AppPalette.accent;
  static const yellow = AppPalette.warning;
  static const red = AppPalette.danger;

  static const textPrimary = AppPalette.textPrimary;
  static const textSecondary = AppPalette.textSecondary;
  static const textMuted = AppPalette.textTertiary;

  // Badge schemes: [bg, text]
  static const badgeBlue = (bg: AppPalette.accent, text: AppPalette.onAccent);
  static const badgeGreen = (bg: AppPalette.accent, text: AppPalette.onAccent);
  static const badgeRed = (bg: AppPalette.danger, text: Color(0xFF2A0A0A));
  static const badgeYellow = (bg: AppPalette.warning, text: Color(0xFF2A1A00));
}

// ─── Theme ────────────────────────────────────────────────────────────────────

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppPalette.accent,
    onPrimary: AppPalette.onAccent,
    secondary: AppPalette.accent,
    onSecondary: AppPalette.onAccent,
    surface: AppPalette.surface,
    onSurface: AppPalette.textPrimary,
    onSurfaceVariant: AppPalette.textSecondary,
    surfaceContainerHighest: AppPalette.surfaceRaised,
    outline: AppPalette.outline,
    outlineVariant: AppPalette.divider,
    error: AppPalette.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.canvas,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(
        color: AppPalette.divider, thickness: 1, space: 1),
    textTheme: const TextTheme(
      titleLarge: AppText.title,
      titleMedium: AppText.heading,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
      labelLarge: AppText.bodyStrong,
      labelMedium: AppText.label,
      labelSmall: AppText.micro,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.canvas,
      foregroundColor: AppPalette.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: AppText.title,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppPalette.accentSoft,
      height: 64,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          AppText.micro.copyWith(
              color: states.contains(WidgetState.selected)
                  ? AppPalette.textPrimary
                  : AppPalette.textTertiary)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? AppPalette.accent
              : AppPalette.textTertiary)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.surfaceRaised,
      hintStyle: AppText.body.copyWith(color: AppPalette.textTertiary),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md, vertical: AppSpace.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppPalette.accent, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppPalette.surfaceRaised,
      contentTextStyle: AppText.body,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.accent,
        foregroundColor: AppPalette.onAccent,
        minimumSize: const Size(0, 44),
        textStyle: AppText.bodyStrong,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.accent,
        foregroundColor: AppPalette.onAccent,
        elevation: 0,
        minimumSize: const Size(0, 44),
        textStyle: AppText.bodyStrong,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppPalette.accent),
  );
}

// ─── Formatters ───────────────────────────────────────────────────────────────

String formatEta(int seconds, AppLanguage lang) {
  if (seconds < 0) return AppStrings.t(lang, 'notDeparted');
  if (seconds == 0) return AppStrings.t(lang, 'arriving');
  if (lang == AppLanguage.zh) {
    if (seconds < 60) return '$seconds 秒';
    final mins = (seconds / 60).round();
    if (mins >= 60) return '${mins ~/ 60} 小時 ${mins % 60} 分';
    return '$mins 分';
  }
  if (seconds < 60) return '${seconds}s';
  final mins = (seconds / 60).round();
  if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}m';
  return '${mins}m';
}

/// Color for ETA — accent when the bus is close, neutral otherwise.
Color etaColor(int seconds) {
  if (seconds < 0) return AppPalette.textTertiary;
  if (seconds <= 180) return AppPalette.accent;
  if (seconds <= 600) return AppPalette.textPrimary;
  return AppPalette.textSecondary;
}

/// Route badge colours. Neutral for every route: the number is the content,
/// colour is reserved for status (see RouteBadge in lib/design).
({Color bg, Color text}) routeBadgeColor(String routeName) =>
    (bg: AppPalette.surfaceRaised, text: AppPalette.textPrimary);

// ─── Geo helpers ──────────────────────────────────────────────────────────────

/// Haversine distance in meters between two GPS points
double haversineDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const r = 6371000.0;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

// ─── Google Maps dark style JSON ──────────────────────────────────────────────
// Neutral charcoal base that matches the UI surfaces. Business POIs are hidden
// so bus stops and routes are the most prominent things on the map.

const String darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1a1f27"}]},
  {"elementType":"labels.icon","stylers":[{"saturation":-60},{"lightness":-10}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#a9b1bd"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1f27"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#3a4350"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d3d9e2"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1e242d"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#8790a0"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#173226"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6fae8c"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c333e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1a1f27"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#363e4b"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#4a5466"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#d3d9e2"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a9b1bd"}]},
  {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#3d4a5c"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#b9c0cb"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f2a3d"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5d8bab"}]}
]
''';
