// BusCard — route card with ETA and favourite toggle
// Mirrors src/components/BusCard.tsx

import 'package:flutter/material.dart';
import '../models/bus_models.dart';
import '../utils/theme.dart';
import 'bus_badge.dart';
import 'eta_tag.dart';

class BusCard extends StatelessWidget {
  final BusRoute route;
  final EstimatedArrival? arrival;
  final bool isActive;
  final bool isFavourite;
  final VoidCallback? onTap;
  final VoidCallback? onFavouriteTap;

  const BusCard({
    super.key,
    required this.route,
    this.arrival,
    this.isActive = false,
    this.isFavourite = false,
    this.onTap,
    this.onFavouriteTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.borderActive : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            BusBadge(routeName: route.routeName.zhTw),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${route.departureStopNameZh} ↔ ${route.destinationStopNameZh}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    route.city,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (arrival != null) EtaTag(seconds: arrival!.estimateTime),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onFavouriteTap,
              child: Icon(
                isFavourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavourite ? AppColors.yellow : AppColors.textMuted,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}