// RouteDetailScreen — stop list with live ETAs and direction toggle
// Mirrors src/screens/RouteDetailScreen.tsx

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../utils/theme.dart';
import '../widgets/bus_badge.dart';

// Taichung city buses typically operate 06:00–23:00.
bool _outsideServiceHours() {
  final h = DateTime.now().hour;
  return h < 6 || h >= 23;
}

class RouteDetailScreen extends ConsumerStatefulWidget {
  final String routeName;
  final String routeUID;

  const RouteDetailScreen({
    super.key,
    required this.routeName,
    required this.routeUID,
  });

  @override
  ConsumerState<RouteDetailScreen> createState() =>
      _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  int _direction = 0; // 0 = 去程, 1 = 回程

  @override
  Widget build(BuildContext context) {
    final params = (routeName: widget.routeName, city: defaultCity);

    final positionsAsync = ref.watch(busPositionsProvider(params));
    final arrivalsAsync = ref.watch(arrivalEstimatesProvider(params));
    final stopsAsync = ref.watch(routeStopsProvider(params));
    final favourites = ref.watch(favouritesProvider);
    final isFav = favourites.contains(widget.routeName);

    // Direction-filtered stops
    final stops = stopsAsync.value
            ?.where((s) => s.direction == _direction)
            .toList() ??
        [];

    // stopUID → earliest ETA for this direction
    final arrivalMap = <String, int>{};
    final dirArrivals = arrivalsAsync.value
            ?.where((a) => a.direction == _direction)
            .toList() ??
        [];
    for (final a in dirArrivals) {
      if (!arrivalMap.containsKey(a.stopUID) ||
          a.estimateTime < arrivalMap[a.stopUID]!) {
        arrivalMap[a.stopUID] = a.estimateTime;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
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
                  BusBadge(
                      routeName: widget.routeName, size: BadgeSize.lg),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: isFav
                          ? AppColors.yellow
                          : AppColors.textMuted,
                    ),
                    onPressed: () => ref
                        .read(favouritesProvider.notifier)
                        .toggle(widget.routeName),
                  ),
                ],
              ),
            ),

            // ── Live bus count ────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${positionsAsync.value?.length ?? 0} buses in service',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  const Text('Updates every 30s',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),

            // ── Direction toggle ──────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _DirButton(
                      label: 'Outbound',
                      active: _direction == 0,
                      onTap: () => setState(() => _direction = 0),
                    ),
                    _DirButton(
                      label: 'Inbound',
                      active: _direction == 1,
                      onTap: () => setState(() => _direction = 1),
                    ),
                  ],
                ),
              ),
            ),

            // ── Service hours warning ─────────────────────────────────────
            if (_outsideServiceHours() &&
                (positionsAsync.value?.isEmpty ?? true))
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.yellow.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppColors.yellow, size: 14),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Bus service is inactive right now (operating hours: 06:00–23:00). Stop list is still available.',
                      style: TextStyle(
                          color: AppColors.yellow, fontSize: 11),
                    ),
                  ),
                ]),
              ),

            // ── Stop list ─────────────────────────────────────────────────
            Expanded(
              child: stopsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
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
                            ? 'Too many requests\nWait a moment and retry'
                            : 'Could not load stops',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => ref.invalidate(routeStopsProvider(params)),
                        child: const Text('Retry',
                            style: TextStyle(color: AppColors.blue)),
                      ),
                    ],
                  ),
                ),
                data: (_) {
                  if (stops.isEmpty) {
                    return const _EmptyStops();
                  }
                  return RefreshIndicator(
                    color: AppColors.blue,
                    backgroundColor: AppColors.bgCard,
                    onRefresh: () async {
                      ref.invalidate(busPositionsProvider(params));
                      ref.invalidate(arrivalEstimatesProvider(params));
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: stops.length,
                      itemBuilder: (_, i) {
                        final stop = stops[i];
                        final eta = arrivalMap[stop.stopUID];
                        final hasBus = eta != null && eta <= 120;
                        final isLast = i == stops.length - 1;
                        return _StopRow(
                          stop: stop,
                          eta: eta,
                          hasBus: hasBus,
                          isLast: isLast,
                        );
                      },
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

class _DirButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DirButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? const Color(0xFF0A1628)
                  : AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  final RouteStop stop;
  final int? eta;
  final bool hasBus;
  final bool isLast;

  const _StopRow({
    required this.stop,
    required this.eta,
    required this.hasBus,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasBus ? AppColors.green : AppColors.bgCard,
                    border: Border.all(
                      color: hasBus ? AppColors.green : AppColors.border,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: hasBus
                          ? AppColors.green.withOpacity(0.33)
                          : AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Stop info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.stopName.zhTw,
                          style: TextStyle(
                            color: hasBus
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (eta != null)
                          Text(
                            formatEta(eta!),
                            style: TextStyle(
                                color: etaColor(eta!), fontSize: 12),
                          )
                        else
                          const Text('—',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                  if (hasBus)
                    Container(
                      padding: const EdgeInsets.all(6),
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.directions_bus_rounded,
                          color: AppColors.green, size: 14),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStops extends StatelessWidget {
  const _EmptyStops();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_outlined,
                color: AppColors.textMuted, size: 40),
            SizedBox(height: 12),
            Text('No stop data',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 14)),
          ],
        ),
      );
}