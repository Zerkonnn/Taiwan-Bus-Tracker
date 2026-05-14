// EtaTag — arrival countdown chip
// Mirrors src/components/EtaTag.tsx

import 'package:flutter/material.dart';
import '../utils/theme.dart';

class EtaTag extends StatelessWidget {
  final int seconds;

  const EtaTag({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) {
    final color = etaColor(seconds);
    final label = formatEta(seconds);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}