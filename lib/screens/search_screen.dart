// SearchScreen — route search with popular-route quick access
// Mirrors src/screens/SearchScreen.tsx

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../utils/app_strings.dart';
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
    final lang = ref.watch(languageProvider);

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
                  Text(
                    AppStrings.t(lang, 'searchRoutesTitle'),
                    style: const TextStyle(
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
                    hintText: AppStrings.t(lang, 'enterRouteNumberEllipsis'),
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
                  loading: () => _Loading(lang: lang),
                  error: (e, _) => _Error(message: e.toString(), lang: lang),
                  data: (results) {
                    if (results.isNotEmpty) {
                      return _ResultList(
                          results: results,
                          onSelect: _selectRoute,
                          lang: lang);
                    }
                    if (_query.trim().isNotEmpty) {
                      return _NoResults(query: _query.trim(), lang: lang);
                    }
                    return _EmptyState(
                      lang: lang,
                      onPopularTap: (routeNum) {
                        _controller.text = routeNum;
                        setState(() => _query = routeNum);
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
  final AppLanguage lang;
  const _Loading({required this.lang});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.blue),
            ),
            const SizedBox(width: 10),
            Text(AppStrings.t(lang, 'searching'),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
}

class _Error extends StatelessWidget {
  final String message;
  final AppLanguage lang;
  const _Error({required this.message, required this.lang});
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
                  ? AppStrings.t(lang, 'tooManyRequestsWait')
                  : AppStrings.t(lang, 'searchUnavailable'),
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
  final AppLanguage lang;
  const _ResultList(
      {required this.results, required this.onSelect, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.t(lang, 'resultsHeader'),
            style: const TextStyle(
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
                      BusBadge(routeName: route.routeName.forLang(lang)),
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
                            Text(cityLabel(lang, route.city),
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
  final AppLanguage lang;
  const _EmptyState({required this.onPopularTap, required this.lang});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.t(lang, 'popularRoutesHeader'),
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularRoutes.map((routeNum) {
              final scheme = routeBadgeColor(routeNum);
              return GestureDetector(
                onTap: () => onPopularTap(routeNum),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.bg.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: scheme.bg.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    routeNum,
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
          Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppColors.textMuted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.t(lang, 'enterBusRouteNumberHint'),
                  style: const TextStyle(
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

class _NoResults extends StatelessWidget {
  final String query;
  final AppLanguage lang;
  const _NoResults({required this.query, required this.lang});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppColors.textMuted, size: 32),
            const SizedBox(height: 10),
            Text(
              AppStrings.noRoutesFoundForQuery(lang, query),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              AppStrings.t(lang, 'tryRouteNumberLike'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
}