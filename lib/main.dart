// Taiwan Bus Tracker â€” Flutter entry point
// Mirrors App.tsx + AppNavigator.tsx from the React Native version

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/bus_providers.dart';
import 'screens/map_screen.dart';
import 'screens/search_screen.dart';
import 'screens/route_detail_screen.dart';
import 'screens/stop_detail_screen.dart';
import 'screens/favourites_screen.dart';
import 'screens/scan_screen.dart';
import 'utils/app_strings.dart';
import 'utils/theme.dart';

void main() {
  runApp(
    // ProviderScope is the Riverpod equivalent of QueryClientProvider
    const ProviderScope(
      child: TaiwanBusApp(),
    ),
  );
}

class TaiwanBusApp extends StatelessWidget {
  const TaiwanBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taiwan Bus Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Named routes â€” mirrors React Navigation stack + tab navigator
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (_) => const _MainTabs(),
            );
          case '/search':
            return MaterialPageRoute(
              builder: (_) => const SearchScreen(),
            );
          case '/route_detail':
            final args = settings.arguments as Map<String, String>;
            return MaterialPageRoute(
              builder: (_) => RouteDetailScreen(
                routeName: args['routeName']!,
                routeUID: args['routeUID']!,
              ),
            );
          case '/stop_detail':
            final args = settings.arguments as Map<String, String>;
            return MaterialPageRoute(
              builder: (_) => StopDetailScreen(
                stopUID: args['stopUID']!,
                stopName: args['stopName']!,
              ),
            );
          case '/scan':
            return MaterialPageRoute(
              builder: (_) => const ScanScreen(),
            );
          default:
            return MaterialPageRoute(
              builder: (_) => const _MainTabs(),
            );
        }
      },
    );
  }
}

// â”€â”€â”€ Bottom tab navigator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MainTabs extends ConsumerStatefulWidget {
  const _MainTabs();

  @override
  ConsumerState<_MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends ConsumerState<_MainTabs> {
  int _index = 0;

  static const _screens = [
    MapScreen(),
    FavouritesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.bgSheet,
        indicatorColor: AppColors.blue.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.map_outlined, color: AppColors.textMuted),
            selectedIcon:
                const Icon(Icons.map_rounded, color: AppColors.blue),
            label: AppStrings.t(lang, 'mapTab'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.star_outline_rounded,
                color: AppColors.textMuted),
            selectedIcon:
                const Icon(Icons.star_rounded, color: AppColors.blue),
            label: AppStrings.t(lang, 'savedTab'),
          ),
        ],
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}