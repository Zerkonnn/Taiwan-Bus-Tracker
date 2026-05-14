// Riverpod providers — mirrors src/hooks/useBusData.ts
//
// StreamProvider.family is used for live/polling data (auto-refresh).
// FutureProvider.family is used for one-shot fetches.
// StateNotifierProvider is used for local favourites (persisted via SharedPreferences).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_models.dart';
import '../services/ptx_api.dart';

// ─── Route Search ─────────────────────────────────────────────────────────────
// Triggered by the search screen; query must be non-empty.

typedef SearchParams = ({String query, String city});

final routeSearchProvider =
    FutureProvider.autoDispose.family<List<BusRoute>, SearchParams>(
  (ref, params) {
    if (params.query.trim().isEmpty) return Future.value([]);
    return PtxApi.instance.searchRoutes(params.query, params.city);
  },
);

// ─── Live Bus Positions — polls every 20 s ───────────────────────────────────
// Less frequent than arrival estimates; used for map markers only.

typedef RouteParams = ({String routeName, String city});

final busPositionsProvider =
    StreamProvider.autoDispose.family<List<BusRealTime>, RouteParams>(
  (ref, params) async* {
    while (true) {
      try {
        final positions = await PtxApi.instance
            .getBusPositions(params.routeName, params.city);
        yield positions;
      } catch (_) {
        // On error keep previous value — don't wipe the display
      }
      await Future.delayed(const Duration(seconds: 20));
    }
  },
);

// ─── Arrival Estimates — polls every 15 s ────────────────────────────────────

final arrivalEstimatesProvider =
    StreamProvider.autoDispose.family<List<EstimatedArrival>, RouteParams>(
  (ref, params) async* {
    while (true) {
      try {
        final arrivals = await PtxApi.instance
            .getEstimatedArrivals(params.routeName, params.city);
        yield arrivals;
      } catch (_) {
        // On error keep previous value — don't wipe the display
      }
      await Future.delayed(const Duration(seconds: 15));
    }
  },
);

// ─── Stop Arrivals — polls every 15 s ─────────────────────────────────────────

typedef StopParams = ({String stopUID, String city});

final stopArrivalsProvider =
    StreamProvider.autoDispose.family<List<EstimatedArrival>, StopParams>(
  (ref, params) async* {
    while (true) {
      try {
        final arrivals = await PtxApi.instance
            .getStopArrivals(params.stopUID, params.city);
        yield arrivals;
      } catch (_) {
        // On error keep previous value — don't wipe the display
      }
      await Future.delayed(const Duration(seconds: 15));
    }
  },
);

// ─── Route Stops (static, cached 5 min) ──────────────────────────────────────

final routeStopsProvider =
    FutureProvider.autoDispose.family<List<RouteStop>, RouteParams>(
  (ref, params) =>
      PtxApi.instance.getRouteStops(params.routeName, params.city),
);

// ─── Nearby Stops ─────────────────────────────────────────────────────────────

typedef NearbyParams = ({double lat, double lon, String city});

final nearbyStopsProvider =
    FutureProvider.autoDispose.family<List<BusStop>, NearbyParams>(
  (ref, params) =>
      PtxApi.instance.getNearbyStops(params.lat, params.lon, params.city),
);

// ─── Favourites (persisted via SharedPreferences) ─────────────────────────────

class FavouritesNotifier extends StateNotifier<List<String>> {
  FavouritesNotifier() : super([]) {
    _load();
  }

  static const _key = 'favourites';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_key) ?? [];
  }

  Future<void> toggle(String routeName) async {
    final updated = state.contains(routeName)
        ? state.where((r) => r != routeName).toList()
        : [...state, routeName];
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated);
  }

  bool isFavourite(String routeName) => state.contains(routeName);
}

final favouritesProvider =
    StateNotifierProvider<FavouritesNotifier, List<String>>(
  (ref) => FavouritesNotifier(),
);