// Design tokens — the single source of truth for colour, type, spacing,
// shape and elevation. Screens and components should use these instead of
// hard-coded values so the whole app keeps one visual language.
//
// Principles:
//  • Neutral charcoal surfaces; ONE accent (teal) for actions, selection and
//    "arriving soon". Amber / coral are reserved for status only.
//  • Floating elements over the map are separated by elevation (shadow),
//    content inside sheets by hairline dividers — not by outlined cards.
//  • 4 pt spacing grid, a small fixed type scale, tabular figures for times.

import 'package:flutter/material.dart';

class AppPalette {
  AppPalette._();

  // Surfaces, darkest → lightest
  static const canvas = Color(0xFF0E1116); // screen background
  static const surface = Color(0xFF171B22); // bars, sheets, floating panels
  static const surfaceRaised = Color(0xFF232934); // inputs, selected/pressed
  // Panels floating over the (darker) map — one step lighter than the map so
  // they read as raised even where a shadow is invisible on dark tiles.
  static const elevated = Color(0xFF222833);
  static const elevatedEdge = Color(0x24FFFFFF); // faint top-light edge
  static const divider = Color(0xFF2A313C); // hairlines between rows
  static const outline = Color(0xFF3A4350); // chip / control outlines

  // Text
  static const textPrimary = Color(0xFFF4F6F9);
  static const textSecondary = Color(0xFFB9C0CB);
  static const textTertiary = Color(0xFF8790A0);

  // Accent — the only "brand" colour
  static const accent = Color(0xFF1FD1A5);
  static const onAccent = Color(0xFF00261C);
  static Color get accentSoft => accent.withValues(alpha: 0.18);

  // Status only
  static const warning = Color(0xFFFFC247);
  static const danger = Color(0xFFFF6B5B);
}

class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class AppRadius {
  AppRadius._();
  static const sm = 6.0; // badges
  static const md = 10.0; // controls, chips, inputs
  static const lg = 12.0; // floating panels
  static const sheet = 16.0; // bottom sheet top corners
}

class AppShadow {
  AppShadow._();

  /// For anything floating directly over the map.
  static const floating = [
    BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

  /// Bottom sheet casting upwards onto the map.
  static const sheet = [
    BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, -2)),
  ];
}

class AppText {
  AppText._();

  static const _tabular = [FontFeature.tabularFigures()];

  static const title = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, height: 1.25,
      color: AppPalette.textPrimary);
  static const heading = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, height: 1.3,
      color: AppPalette.textPrimary);
  static const body = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400, height: 1.35,
      color: AppPalette.textPrimary);
  static const bodyStrong = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w500, height: 1.35,
      color: AppPalette.textPrimary);
  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400, height: 1.3,
      color: AppPalette.textSecondary);
  static const label = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, height: 1.3,
      letterSpacing: 0.2, color: AppPalette.textSecondary);
  static const micro = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w500, height: 1.2,
      color: AppPalette.textSecondary);

  /// Countdown / time values — tabular so digits don't jitter as they change.
  static const time = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w600, height: 1.2,
      fontFeatures: _tabular, color: AppPalette.textPrimary);
}

class AppDecor {
  AppDecor._();

  /// Panel floating over the map (search bar, trip card, map buttons).
  static const floatingPanel = BoxDecoration(
    color: AppPalette.elevated,
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
    border: Border.fromBorderSide(BorderSide(color: AppPalette.elevatedEdge)),
    boxShadow: AppShadow.floating,
  );
}
