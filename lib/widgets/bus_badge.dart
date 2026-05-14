// BusBadge — colored route-number pill
// Mirrors src/components/BusBadge.tsx

import 'package:flutter/material.dart';
import '../utils/theme.dart';

enum BadgeSize { sm, md, lg }

class BusBadge extends StatelessWidget {
  final String routeName;
  final BadgeSize size;

  const BusBadge({super.key, required this.routeName, this.size = BadgeSize.md});

  @override
  Widget build(BuildContext context) {
    final scheme = routeBadgeColor(routeName);

    final double fontSize = switch (size) {
      BadgeSize.sm => 11,
      BadgeSize.md => 13,
      BadgeSize.lg => 16,
    };
    final EdgeInsets padding = switch (size) {
      BadgeSize.sm => const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      BadgeSize.md => const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      BadgeSize.lg => const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        routeName,
        style: TextStyle(
          color: scheme.text,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}