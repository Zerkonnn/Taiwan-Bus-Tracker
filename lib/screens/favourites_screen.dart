// FavouritesScreen — saved routes (persisted to SharedPreferences)
// Mirrors src/screens/FavouritesScreen.tsx

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/bus_providers.dart';
import '../utils/theme.dart';
import '../widgets/bus_badge.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouritesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Text(
                'Saved Routes',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: favourites.isEmpty
                  ? _EmptyState(
                      onSearchTap: () =>
                          Navigator.pushNamed(context, '/search'),
                    )
                  : ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: favourites.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final routeName = favourites[i];
                        return _FavRow(
                          routeName: routeName,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/route_detail',
                            arguments: {
                              'routeName': routeName,
                              'routeUID': routeName,
                            },
                          ),
                          onRemove: () => ref
                              .read(favouritesProvider.notifier)
                              .toggle(routeName),
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

class _FavRow extends StatelessWidget {
  final String routeName;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _FavRow({
    required this.routeName,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            BusBadge(routeName: routeName),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Route $routeName',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.star_rounded,
                    color: AppColors.yellow, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onSearchTap;
  const _EmptyState({required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_outline_rounded,
                color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No saved routes yet',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'Star a route on its detail page to save it here',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onSearchTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.blue.withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, color: AppColors.blue, size: 16),
                    SizedBox(width: 8),
                    Text('Search Routes',
                        style: TextStyle(
                            color: AppColors.blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}