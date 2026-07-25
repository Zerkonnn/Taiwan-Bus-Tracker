// StopDetailScreen — all arrivals at a specific stop, refreshes every 20 s
// Mirrors src/screens/StopDetailScreen.tsx

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../utils/app_strings.dart';
import '../utils/theme.dart';
import '../widgets/bus_badge.dart';
import '../widgets/eta_tag.dart';

class StopDetailScreen extends ConsumerWidget {
  final String stopUID;
  final String stopName;

  const StopDetailScreen({
    super.key,
    required this.stopUID,
    required this.stopName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrivalsAsync = ref.watch(
      stopArrivalsProvider((stopUID: stopUID, city: defaultCity)),
    );
    final lang = ref.watch(languageProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stopName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              AppStrings.t(lang, 'updatesEvery30s'),
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                AppStrings.t(lang, 'arrivingSoonHeader'),
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.2),
              ),
            ),

            // ── Arrivals list ─────────────────────────────────────────────
            Expanded(
              child: arrivalsAsync.when(
                loading: () => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.blue),
                      const SizedBox(height: 12),
                      Text(AppStrings.t(lang, 'loadingEllipsis'),
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14)),
                    ],
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          color: AppColors.textMuted, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        e.toString().contains('Rate limited')
                            ? AppStrings.t(lang, 'tooManyRequestsRetry')
                            : AppStrings.t(lang, 'couldNotLoadArrivals'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => ref.invalidate(stopArrivalsProvider(
                            (stopUID: stopUID, city: defaultCity))),
                        child: Text(AppStrings.t(lang, 'retry'),
                            style: const TextStyle(color: AppColors.blue)),
                      ),
                    ],
                  ),
                ),
                data: (arrivals) {
                  if (arrivals.isEmpty) {
                    return _EmptyArrivals(lang: lang);
                  }
                  return RefreshIndicator(
                    color: AppColors.blue,
                    backgroundColor: AppColors.bgCard,
                    onRefresh: () async => ref.invalidate(
                        stopArrivalsProvider(
                            (stopUID: stopUID, city: defaultCity))),
                    child: ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: arrivals.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) =>
                          _ArrivalRow(arrival: arrivals[i], lang: lang),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  final EstimatedArrival arrival;
  final AppLanguage lang;
  const _ArrivalRow({required this.arrival, required this.lang});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/route_detail',
        arguments: {
          'routeName': arrival.routeName.zhTw,
          'routeUID': arrival.routeUID,
        },
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            BusBadge(routeName: arrival.routeName.forLang(lang)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.route(lang, arrival.routeName.forLang(lang)),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    arrival.direction == 0
                        ? AppStrings.t(lang, 'outbound')
                        : AppStrings.t(lang, 'inbound'),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            EtaTag(seconds: arrival.estimateTime, language: lang),
          ],
        ),
      ),
    );
  }
}

class _EmptyArrivals extends StatelessWidget {
  final AppLanguage lang;
  const _EmptyArrivals({required this.lang});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_outlined,
                color: AppColors.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(AppStrings.t(lang, 'noBusesArrivingSoon'),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 14)),
          ],
        ),
      );
}