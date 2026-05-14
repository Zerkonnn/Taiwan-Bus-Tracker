// SearchScreen — route search with popular-route quick access
// Mirrors src/screens/SearchScreen.tsx

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../utils/theme.dart';
import '../widgets/bus_badge.dart';

const _popularRoutes = ['52', '88', '301', '75', '106', '23', '36', '40'];

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _selectRoute(BusRoute route) {
    Navigator.pushNamed(
      context,
      '/route_detail',
      arguments: {
        'routeName': route.routeName.zhTw,
        'routeUID': route.routeUID,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(
      routeSearchProvider(
        (query: _query, city: defaultCity),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Search Routes',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // ── Search input ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgInput,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter route number, e.g. 52…',
                    hintStyle:
                        const TextStyle(color: AppColors.textMuted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: AppColors.blue),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: AppColors.textMuted, size: 18),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      if (mounted) setState(() => _query = v);
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Results or popular routes ────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: searchAsync.when(
                  loading: () => const _Loading(),
                  error: (e, _) => _Error(message: e.toString()),
                  data: (results) {
                    if (results.isNotEmpty) {
                      return _ResultList(
                          results: results, onSelect: _selectRoute);
                    }
                    return _EmptyState(
                      onPopularTap: (num) {
                        _controller.text = num;
                        setState(() => _query = num);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.blue),
            ),
            SizedBox(width: 10),
            Text('Searching…',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
}

class _Error extends StatelessWidget {
  final String message;
  const _Error({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.textMuted, size: 32),
            const SizedBox(height: 10),
            Text(
              message.contains('Rate limited')
                  ? 'Too many requests — wait a moment and try again'
                  : 'Search unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
}

class _ResultList extends StatelessWidget {
  final List<BusRoute> results;
  final void Function(BusRoute) onSelect;
  const _ResultList({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RESULTS',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final route = results[i];
              return GestureDetector(
                onTap: () => onSelect(route),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
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
                                  fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(route.city,
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textMuted, size: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final void Function(String) onPopularTap;
  const _EmptyState({required this.onPopularTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('POPULAR ROUTES',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularRoutes.map((num) {
              final scheme = routeBadgeColor(num);
              return GestureDetector(
                onTap: () => onPopularTap(num),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.bg.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: scheme.bg.withOpacity(0.3)),
                  ),
                  child: Text(
                    num,
                    style: TextStyle(
                        color: scheme.bg,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Icon(Icons.info_outline,
                  color: AppColors.textMuted, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Enter a bus route number, e.g. "52" or "301"',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}