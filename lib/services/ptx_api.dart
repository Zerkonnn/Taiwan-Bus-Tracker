// PTX API service
//
// While waiting for PTX credentials, the app uses DEMO DATA automatically.
// Once approved, replace the two constants below and demo mode turns off.
//
// Register free at: https://tdx.transportdata.tw/register

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_models.dart';

const _clientId = 'd1229288-f2fa2a2e-6ce6-45d6';
const _clientSecret = '740f97a3-e6ca-4ed1-b392-31205dd440c2';

// Demo mode is ON when credentials are still placeholder values
bool get _demoMode =>
    _clientId == 'YOUR_PTX_CLIENT_ID' ||
    _clientSecret == 'YOUR_PTX_CLIENT_SECRET';

const _authUrl =
    'https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token';
const _baseUrl = 'https://tdx.transportdata.tw/api/basic/v2/Bus';

class _CacheEntry {
  final List<dynamic> data;
  final DateTime expiry;
  _CacheEntry(this.data, this.expiry);
  bool get isValid => DateTime.now().isBefore(expiry);
}

// Limits concurrent outbound requests to 1 and enforces a 350 ms gap between
// each call — prevents burst 429s when multiple providers load at once.
class _Throttle {
  static const _gap = Duration(milliseconds: 350);
  bool _busy = false;
  final _queue = <Completer<void>>[];

  Future<void> acquire() async {
    if (!_busy) {
      _busy = true;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isEmpty) {
      _busy = false;
      return;
    }
    final next = _queue.removeAt(0);
    Future.delayed(_gap, () {
      next.complete();
    });
  }
}

class PtxApi {
  static final PtxApi instance = PtxApi._();
  PtxApi._();

  String? _accessToken;
  DateTime? _tokenExpiry;
  final Map<String, _CacheEntry> _cache = {};
  final _throttle = _Throttle();

  // Live endpoints get 30 s; static route/stop data gets 5 min.
  Duration _ttlFor(String path) {
    if (path.contains('RealTimeByFrequency') ||
        path.contains('EstimatedTimeOfArrival')) {
      return const Duration(seconds: 30);
    }
    if (path.contains('Stop/City')) return const Duration(minutes: 2);
    // Road geometry practically never changes
    if (path.contains('/Shape/')) return const Duration(hours: 12);
    return const Duration(minutes: 5);
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────

  Future<String> _getAccessToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken!;
    }
    final response = await http.post(
      Uri.parse(_authUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': _clientId,
        'client_secret': _clientSecret,
      },
    );
    if (response.statusCode != 200) {
      throw Exception('PTX auth failed (${response.statusCode})');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresIn = data['expires_in'] as int;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
    return _accessToken!;
  }

  Future<List<T>> _getList<T>(
    String path,
    Map<String, String> extraParams,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: {'\$format': 'JSON', ...extraParams});
    final cacheKey = uri.toString();

    // Return cached result if still fresh — no network call needed
    final cached = _cache[cacheKey];
    if (cached != null && cached.isValid) {
      return cached.data
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Throttle: only one request at a time, 350 ms apart
    await _throttle.acquire();
    try {
      const maxRetries = 2;
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        final token = await _getAccessToken();
        final response = await http.get(uri,
            headers: {'Authorization': 'Bearer $token', 'Accept-Encoding': 'gzip'});

        if (response.statusCode == 429) {
          // Return stale cache silently — avoids blocking with retries and keeps
          // the UI showing the last known data rather than throwing an error.
          final stale = _cache[cacheKey];
          if (stale != null) {
            return stale.data
                .map((e) => fromJson(e as Map<String, dynamic>))
                .toList();
          }
          if (attempt < maxRetries - 1) {
            await Future.delayed(const Duration(seconds: 3));
            continue;
          }
          throw Exception('Rate limited');
        }
        if (response.statusCode != 200) {
          throw Exception('PTX API error ${response.statusCode}');
        }
        final List<dynamic> list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        _cache[cacheKey] = _CacheEntry(list, DateTime.now().add(_ttlFor(path)));
        return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
      }
      throw Exception('PTX API request failed after $maxRetries attempts');
    } finally {
      _throttle.release();
    }
  }

  // ─── Route Search ──────────────────────────────────────────────────────────

  Future<List<BusRoute>> searchRoutes(String routeName, String city) async {
    if (_demoMode) return Future.value(_demoSearchRoutes(routeName));
    final results = await _getList(
        '/Route/City/$city/${Uri.encodeComponent(routeName)}',
        {},
        BusRoute.fromJson);
    // PTX returns every route whose name *contains* the query (e.g. "52" also
    // matches "152", "252"...). Put exact matches first so the route the user
    // actually searched for isn't buried under unrelated substring matches.
    bool isExact(BusRoute r) =>
        r.routeName.zhTw == routeName || r.routeName.en == routeName;
    results.sort((a, b) {
      final aExact = isExact(a), bExact = isExact(b);
      if (aExact != bExact) return aExact ? -1 : 1;
      return 0;
    });
    return results;
  }

  // ─── Live Bus Positions ────────────────────────────────────────────────────

  Future<List<BusRealTime>> getBusPositions(String routeName, String city) async {
    if (_demoMode) return Future.value(_demoBusPositions(routeName));
    final all = await _getList(
        '/RealTimeByFrequency/City/$city/${Uri.encodeComponent(routeName)}',
        {}, BusRealTime.fromJson);
    // PTX returns all routes whose name *contains* the query (e.g. "5" → 5, 15, 25…).
    // Keep only exact matches so route "5" doesn't bleed into "15", "45", etc.
    return all
        .where((b) =>
            b.routeName.zhTw == routeName || b.routeName.en == routeName)
        .toList();
  }

  // ─── Arrival Estimates ─────────────────────────────────────────────────────

  Future<List<EstimatedArrival>> getEstimatedArrivals(
      String routeName, String city) async {
    if (_demoMode) return _demoArrivals(routeName);
    final results = await _getList(
        '/EstimatedTimeOfArrival/City/$city/${Uri.encodeComponent(routeName)}',
        {}, EstimatedArrival.fromJson);
    // Same exact-match filter as getBusPositions
    results.retainWhere((a) =>
        a.routeName.zhTw == routeName || a.routeName.en == routeName);
    results.sort((a, b) => a.estimateTime.compareTo(b.estimateTime));
    return results;
  }

  Future<List<EstimatedArrival>> getStopArrivals(
      String stopUID, String city) async {
    if (_demoMode) return _demoStopArrivals(stopUID);
    final results = await _getList(
        '/EstimatedTimeOfArrival/City/$city',
        {'\$filter': "StopUID eq '$stopUID'"}, EstimatedArrival.fromJson);
    results.sort((a, b) => a.estimateTime.compareTo(b.estimateTime));
    return results;
  }

  // ─── Stops ─────────────────────────────────────────────────────────────────

  Future<List<RouteStop>> getRouteStops(String routeName, String city) async {
    if (_demoMode) return Future.value(_demoRouteStops(routeName));

    // DisplayStopOfRoute returns route-direction groups with a nested Stops
    // array — not a flat list — so we can't use _getList with RouteStop.fromJson.
    final path =
        '/DisplayStopOfRoute/City/$city/${Uri.encodeComponent(routeName)}';
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: {'\$format': 'JSON'});
    final cacheKey = uri.toString();

    final cached = _cache[cacheKey];
    if (cached != null && cached.isValid) {
      return _flattenRouteStops(cached.data, routeName);
    }

    await _throttle.acquire();
    try {
      const maxRetries = 2;
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        final token = await _getAccessToken();
        final response = await http.get(uri, headers: {
          'Authorization': 'Bearer $token',
          'Accept-Encoding': 'gzip',
        });

        if (response.statusCode == 429) {
          final stale = _cache[cacheKey];
          if (stale != null) return _flattenRouteStops(stale.data, routeName);
          if (attempt < maxRetries - 1) {
            await Future.delayed(const Duration(seconds: 3));
            continue;
          }
          throw Exception('Rate limited');
        }
        if (response.statusCode != 200) {
          throw Exception('PTX API error ${response.statusCode}');
        }
        final List<dynamic> list =
            jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        _cache[cacheKey] =
            _CacheEntry(list, DateTime.now().add(_ttlFor(path)));
        return _flattenRouteStops(list, routeName);
      }
      throw Exception('PTX API request failed after $maxRetries attempts');
    } finally {
      _throttle.release();
    }
  }

  // Each element of the DisplayStopOfRoute response is a {RouteUID, Direction,
  // RouteName, Stops: [...]} group. We flatten into individual RouteStop objects,
  // filtering to the exact requested route name so "5" doesn't include "15", "25"…
  List<RouteStop> _flattenRouteStops(List<dynamic> data, String routeName) {
    final stops = <RouteStop>[];
    for (final group in data) {
      final g = group as Map<String, dynamic>;

      // Skip groups whose RouteName doesn't exactly match what was requested
      final gNameZh = g['RouteName'] is Map<String, dynamic>
          ? (g['RouteName'] as Map<String, dynamic>)['Zh_tw'] as String? ?? ''
          : '';
      final gNameEn = g['RouteName'] is Map<String, dynamic>
          ? (g['RouteName'] as Map<String, dynamic>)['En'] as String? ?? ''
          : '';
      if (gNameZh.isNotEmpty &&
          gNameZh != routeName &&
          gNameEn != routeName) { continue; }

      final routeUID = g['RouteUID'] as String? ?? '';
      final direction = g['Direction'] as int? ?? 0;
      final rawStops = g['Stops'] as List<dynamic>? ?? [];
      for (final s in rawStops) {
        final stop = s as Map<String, dynamic>;
        stops.add(RouteStop(
          routeUID: routeUID,
          direction: direction,
          stopUID: stop['StopUID'] as String? ?? '',
          stopName: stop['StopName'] is Map<String, dynamic>
              ? LocalizedName.fromJson(
                  stop['StopName'] as Map<String, dynamic>)
              : const LocalizedName(zhTw: '', en: ''),
          stopPosition: stop['StopPosition'] is Map<String, dynamic>
              ? BusPosition.fromJson(
                  stop['StopPosition'] as Map<String, dynamic>)
              : const BusPosition(lat: 0, lon: 0),
          stopSequence: stop['StopSequence'] as int? ?? 0,
        ));
      }
    }
    return stops;
  }

  // ─── Route Shapes ──────────────────────────────────────────────────────────

  // The road path of each direction of [routeName]. Empty in demo mode or
  // when TDX has no shape for the route — callers fall back to stop-to-stop.
  Future<List<BusShape>> getRouteShapes(String routeName, String city) async {
    if (_demoMode) return [];
    final shapes = await _getList(
        '/Shape/City/$city/${Uri.encodeComponent(routeName)}',
        {},
        BusShape.fromJson);
    // Like Route, Shape matches names by substring ("5" also returns "15")
    return shapes
        .where((s) =>
            (s.routeName.zhTw == routeName || s.routeName.en == routeName) &&
            s.points.length >= 2)
        .toList();
  }

  Future<List<BusStop>> getNearbyStops(double lat, double lon, String city,
      {int radius = 500}) {
    if (_demoMode) return Future.value(_demoNearbyStops(lat, lon));
    return _getList('/Stop/City/$city',
        {'\$spatialFilter': 'nearby($lat,$lon,$radius)'}, BusStop.fromJson);
  }
}

// ─── Demo Data (Taichung routes) ──────────────────────────────────────────────

List<BusRoute> _demoSearchRoutes(String query) {
  final all = [
    BusRoute(routeUID: 'TXG22', routeID: '22',
        routeName: const LocalizedName(zhTw: '22', en: '22'),
        departureStopNameZh: '火車站', destinationStopNameZh: '靜宜大學',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG23', routeID: '23',
        routeName: const LocalizedName(zhTw: '23', en: '23'),
        departureStopNameZh: '火車站', destinationStopNameZh: '大里',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG25', routeID: '25',
        routeName: const LocalizedName(zhTw: '25', en: '25'),
        departureStopNameZh: '火車站', destinationStopNameZh: '霧峰',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG36', routeID: '36',
        routeName: const LocalizedName(zhTw: '36', en: '36'),
        departureStopNameZh: '火車站', destinationStopNameZh: '霧峰',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG40', routeID: '40',
        routeName: const LocalizedName(zhTw: '40', en: '40'),
        departureStopNameZh: '火車站', destinationStopNameZh: '烏日',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG51', routeID: '51',
        routeName: const LocalizedName(zhTw: '51', en: '51'),
        departureStopNameZh: '火車站', destinationStopNameZh: '西屯',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG52', routeID: '52',
        routeName: const LocalizedName(zhTw: '52', en: '52'),
        departureStopNameZh: '火車站', destinationStopNameZh: '朝馬',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG54', routeID: '54',
        routeName: const LocalizedName(zhTw: '54', en: '54'),
        departureStopNameZh: '火車站', destinationStopNameZh: '逢甲',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG57', routeID: '57',
        routeName: const LocalizedName(zhTw: '57', en: '57'),
        departureStopNameZh: '朝馬', destinationStopNameZh: '大坑',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG60', routeID: '60',
        routeName: const LocalizedName(zhTw: '60', en: '60'),
        departureStopNameZh: '火車站', destinationStopNameZh: '中科',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG71', routeID: '71',
        routeName: const LocalizedName(zhTw: '71', en: '71'),
        departureStopNameZh: '火車站', destinationStopNameZh: '東海大學',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG75', routeID: '75',
        routeName: const LocalizedName(zhTw: '75', en: '75'),
        departureStopNameZh: '北屯', destinationStopNameZh: '南屯',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG79', routeID: '79',
        routeName: const LocalizedName(zhTw: '79', en: '79'),
        departureStopNameZh: '朝馬', destinationStopNameZh: '太平',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG88', routeID: '88',
        routeName: const LocalizedName(zhTw: '88', en: '88'),
        departureStopNameZh: '火車站', destinationStopNameZh: '逢甲',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG106', routeID: '106',
        routeName: const LocalizedName(zhTw: '106', en: '106'),
        departureStopNameZh: '豐原', destinationStopNameZh: '火車站',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG178', routeID: '178',
        routeName: const LocalizedName(zhTw: '178', en: '178'),
        departureStopNameZh: '火車站', destinationStopNameZh: '大甲',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG180', routeID: '180',
        routeName: const LocalizedName(zhTw: '180', en: '180'),
        departureStopNameZh: '朝馬', destinationStopNameZh: '豐原',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG270', routeID: '270',
        routeName: const LocalizedName(zhTw: '270', en: '270'),
        departureStopNameZh: '火車站', destinationStopNameZh: '清水',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG301', routeID: '301',
        routeName: const LocalizedName(zhTw: '301', en: '301'),
        departureStopNameZh: '中科', destinationStopNameZh: '火車站',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXG306', routeID: '306',
        routeName: const LocalizedName(zhTw: '306', en: '306'),
        departureStopNameZh: '朝馬', destinationStopNameZh: '彰化',
        city: 'Taichung', cityCode: 'TXG'),
    BusRoute(routeUID: 'TXGBRT', routeID: 'BRT',
        routeName: const LocalizedName(zhTw: 'BRT', en: 'BRT'),
        departureStopNameZh: '朝馬', destinationStopNameZh: '大慶',
        city: 'Taichung', cityCode: 'TXG'),
  ];
  if (query.isEmpty) return all;
  return all
      .where((r) =>
          r.routeName.zhTw.contains(query) ||
          r.routeID.contains(query) ||
          r.departureStopNameZh.contains(query) ||
          r.destinationStopNameZh.contains(query))
      .toList();
}

List<BusRealTime> _demoBusPositions(String routeName) {
  // Scatter a few buses around Taichung
  return [
    BusRealTime(plateNumb: 'KKA-1234', routeUID: routeName,
        routeName: LocalizedName(zhTw: routeName, en: routeName),
        direction: 0, busStatus: 0,
        busPosition: const BusPosition(lat: 24.1477, lon: 120.6736),
        speed: 32, updateTime: DateTime.now().toIso8601String()),
    BusRealTime(plateNumb: 'KKA-5678', routeUID: routeName,
        routeName: LocalizedName(zhTw: routeName, en: routeName),
        direction: 0, busStatus: 0,
        busPosition: const BusPosition(lat: 24.1510, lon: 120.6800),
        speed: 18, updateTime: DateTime.now().toIso8601String()),
    BusRealTime(plateNumb: 'KKA-9012', routeUID: routeName,
        routeName: LocalizedName(zhTw: routeName, en: routeName),
        direction: 1, busStatus: 0,
        busPosition: const BusPosition(lat: 24.1440, lon: 120.6670),
        speed: 25, updateTime: DateTime.now().toIso8601String()),
  ];
}

Future<List<EstimatedArrival>> _demoArrivals(String routeName) async {
  final stops = _demoRouteStops(routeName).where((s) => s.direction == 0).toList();
  int eta = 60;
  return stops.map((s) {
    eta += 120;
    return EstimatedArrival(
      plateNumb: 'KKA-1234', routeUID: routeName,
      routeName: LocalizedName(zhTw: routeName, en: routeName),
      direction: 0, stopUID: s.stopUID, stopID: s.stopUID,
      stopName: s.stopName, estimateTime: eta,
      stopCountDown: (eta / 60).round(), updateTime: DateTime.now().toIso8601String(),
    );
  }).toList();
}

Future<List<EstimatedArrival>> _demoStopArrivals(String stopUID) async {
  return [
    EstimatedArrival(plateNumb: 'KKA-1234', routeUID: 'TXG52',
        routeName: const LocalizedName(zhTw: '52', en: '52'),
        direction: 0, stopUID: stopUID, stopID: stopUID,
        stopName: const LocalizedName(zhTw: '示範站', en: 'Demo Stop'),
        estimateTime: 90, stopCountDown: 2,
        updateTime: DateTime.now().toIso8601String()),
    EstimatedArrival(plateNumb: 'KKB-5678', routeUID: 'TXG88',
        routeName: const LocalizedName(zhTw: '88', en: '88'),
        direction: 0, stopUID: stopUID, stopID: stopUID,
        stopName: const LocalizedName(zhTw: '示範站', en: 'Demo Stop'),
        estimateTime: 300, stopCountDown: 5,
        updateTime: DateTime.now().toIso8601String()),
    EstimatedArrival(plateNumb: 'KKC-9012', routeUID: 'TXG301',
        routeName: const LocalizedName(zhTw: '301', en: '301'),
        direction: 1, stopUID: stopUID, stopID: stopUID,
        stopName: const LocalizedName(zhTw: '示範站', en: 'Demo Stop'),
        estimateTime: 540, stopCountDown: 9,
        updateTime: DateTime.now().toIso8601String()),
  ];
}

List<RouteStop> _demoRouteStops(String routeName) {
  final names0 = ['火車站', '市政府', '中友百貨', '忠明南路', '五權西路',
      '台灣大道', '水湳', '中清路', '文心路', '朝馬'];
  final names1 = ['朝馬', '文心路', '中清路', '水湳', '台灣大道',
      '五權西路', '忠明南路', '中友百貨', '市政府', '火車站'];

  // Outbound 去程
  final out = names0.asMap().entries.map((e) => RouteStop(
    routeUID: routeName, direction: 0,
    stopUID: 'DEMO-0-${e.key}',
    stopName: LocalizedName(zhTw: e.value, en: e.value),
    stopPosition: BusPosition(
        lat: 24.1477 + e.key * 0.003,
        lon: 120.6736 + e.key * 0.002),
    stopSequence: e.key + 1,
  )).toList();

  // Inbound 回程
  final inb = names1.asMap().entries.map((e) => RouteStop(
    routeUID: routeName, direction: 1,
    stopUID: 'DEMO-1-${e.key}',
    stopName: LocalizedName(zhTw: e.value, en: e.value),
    stopPosition: BusPosition(
        lat: 24.1477 + (9 - e.key) * 0.003,
        lon: 120.6736 + (9 - e.key) * 0.002),
    stopSequence: e.key + 1,
  )).toList();

  return [...out, ...inb];
}

List<BusStop> _demoNearbyStops(double lat, double lon) {
  final names = ['中友百貨站', '市政府站', '火車站', '忠明南路口', '五權西路站'];
  return names.asMap().entries.map((e) => BusStop(
    stopUID: 'NEARBY-${e.key}',
    stopID: 'NEARBY-${e.key}',
    stopName: LocalizedName(zhTw: e.value, en: e.value),
    stopPosition: BusPosition(
        lat: lat + (e.key - 2) * 0.001,
        lon: lon + (e.key - 2) * 0.001),
    stopAddress: '台中市',
    bearing: 'N',
  )).toList();
}