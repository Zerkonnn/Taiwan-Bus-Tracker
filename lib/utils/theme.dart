// App theme — mirrors src/utils/theme.ts

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_strings.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────

class AppColors {
  static const bg = Color(0xFF0F1117);
  static const bgCard = Color(0xFF1F2330);
  static const bgSheet = Color(0xFF161920);
  static const bgInput = Color(0xFF1F2330);
  static const border = Color(0xFF2A2D36);
  static const borderActive = Color(0xFF4A9EFF);

  static const blue = Color(0xFF4A9EFF);
  static const green = Color(0xFF4ECB7A);
  static const yellow = Color(0xFFF5C542);
  static const red = Color(0xFFFF5C5C);

  static const textPrimary = Color(0xFFE8EAF2);
  static const textSecondary = Color(0xFFAAB0CC);
  static const textMuted = Color(0xFF555A72);

  // Badge schemes: [bg, text]
  static const badgeBlue = (bg: blue, text: Color(0xFF0A1628));
  static const badgeGreen = (bg: green, text: Color(0xFF0A2015));
  static const badgeRed = (bg: red, text: Color(0xFF2A0A0A));
  static const badgeYellow = (bg: yellow, text: Color(0xFF2A1A00));
}

// ─── Theme ────────────────────────────────────────────────────────────────────

ThemeData buildAppTheme() => ThemeData(
      colorScheme: const ColorScheme.dark(
        primary: AppColors.blue,
        surface: AppColors.bgCard,
        onPrimary: Color(0xFF0A1628),
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      useMaterial3: true,
      fontFamily: 'sans-serif',
    );

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

/// Color for ETA — green = arriving, blue = soon, yellow = later, grey = far
Color etaColor(int seconds) {
  if (seconds <= 60) return AppColors.green;
  if (seconds <= 300) return AppColors.blue;
  if (seconds <= 600) return AppColors.yellow;
  return AppColors.textMuted;
}

/// Badge color scheme based on first char of route name (matches RN version)
({Color bg, Color text}) routeBadgeColor(String routeName) {
  if (routeName.isEmpty) {
    return (bg: AppColors.blue, text: const Color(0xFF0A1628));
  }
  const schemes = [
    (bg: AppColors.blue, text: Color(0xFF0A1628)),
    (bg: AppColors.green, text: Color(0xFF0A2015)),
    (bg: AppColors.red, text: Color(0xFF2A0A0A)),
    (bg: AppColors.yellow, text: Color(0xFF2A1A00)),
  ];
  return schemes[routeName.codeUnitAt(0) % 4];
}

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

const String darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1a2335"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a9bb0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a2335"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#243050"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2d3c5a"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1a2b"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1e2a40"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6b7f9a"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#253555"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#2d3c5a"}]}
]
''';