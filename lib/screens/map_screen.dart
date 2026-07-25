// MapScreen â€” Google Maps + TDX Taichung Bus API
// Google Maps handles the interactive map; TDX provides accurate live bus
// positions, ETAs, route stop positions (for polylines), and nearby stops.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../services/ptx_api.dart';
import '../utils/app_strings.dart';
import '../utils/theme.dart';

const _defaultCenter = LatLng(24.1477, 120.6736);

// Same key used for Maps SDK in AndroidManifest.xml â€” must also have
// Directions API enabled in Google Cloud Console for this project.
const _googleMapsApiKey = 'AIzaSyDUPCYVGg1mKjrkzbBtSsaopGXbY8SDj18';

// â”€â”€â”€ Popular Taiwan locations (instant search fallback) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _LocationResult {
  final String shortName;    // Chinese name (or Nominatim result)
  final String shortNameEn;  // English name for popular locations
  final String displayName;
  final double lat;
  final double lon;

  const _LocationResult({
    required this.shortName,
    this.shortNameEn = '',
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory _LocationResult.fromNominatim(Map<String, dynamic> json) {
    final full = json['display_name'] as String;
    final short = full.split(',').first.trim();
    return _LocationResult(
      shortName: short,
      displayName: full,
      lat: double.parse(json['lat'] as String),
      lon: double.parse(json['lon'] as String),
    );
  }
}

const _popularLocations = [
  _LocationResult(shortName: 'é€¢ç”²å¤§å­¸', shortNameEn: 'Feng Chia University', displayName: 'å°ä¸­å¸‚è¥¿å±¯å€é€¢ç”²å¤§å­¸', lat: 24.1800, lon: 120.6445),
  _LocationResult(shortName: 'å°ä¸­ç«è»Šç«™', shortNameEn: 'Taichung Train Station', displayName: 'å°ä¸­å¸‚ä¸­å€å°ä¸­ç«è»Šç«™', lat: 24.1369, lon: 120.6852),
  _LocationResult(shortName: 'å°ä¸­å¸‚æ”¿åºœ', shortNameEn: 'Taichung City Hall', displayName: 'å°ä¸­å¸‚è¥¿å±¯å€å¸‚æ”¿åŒ—äºŒè·¯', lat: 24.1634, lon: 120.6469),
  _LocationResult(shortName: 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸', shortNameEn: 'Nat\'l Chung Hsing University (NCHU)', displayName: 'å°ä¸­å¸‚å—å€èˆˆå¤§è·¯145è™Ÿ', lat: 24.1170, lon: 120.6752),
  _LocationResult(shortName: 'å°ä¸­æ¦®ç¸½', shortNameEn: 'Taichung Veterans General Hospital', displayName: 'å°ä¸­å¸‚è¥¿å±¯å€å°ç£å¤§é“å››æ®µ1650è™Ÿ', lat: 24.1731, lon: 120.6362),
  _LocationResult(shortName: 'æœé¦¬è½‰é‹ç«™', shortNameEn: 'Chaoma Bus Terminal', displayName: 'å°ä¸­å¸‚è¥¿å±¯å€æœé¦¬ä¸‰è·¯', lat: 24.1548, lon: 120.6245),
  _LocationResult(shortName: 'é«˜éµå°ä¸­ç«™', shortNameEn: 'Taichung HSR Station', displayName: 'å°ä¸­å¸‚çƒæ—¥å€ç«™å€äºŒè·¯', lat: 24.0626, lon: 120.6854),
  _LocationResult(shortName: 'å°ä¸­æ©Ÿå ´', shortNameEn: 'Taichung Airport', displayName: 'å°ä¸­å¸‚æ¸…æ°´å€éŽ®å—è·¯', lat: 24.2641, lon: 120.6208),
  _LocationResult(shortName: 'ä¸€ä¸­å•†åœˆ', shortNameEn: 'First High School Shopping Area', displayName: 'å°ä¸­å¸‚åŒ—å€è‚²æ‰è¡—ä¸€å¸¶', lat: 24.1534, lon: 120.6869),
  _LocationResult(shortName: 'ä¸­å‹ç™¾è²¨', shortNameEn: 'Chung Yu Department Store', displayName: 'å°ä¸­å¸‚ä¸­å€ä¸‰æ°‘è·¯ä¸‰æ®µ', lat: 24.1456, lon: 120.6819),
  _LocationResult(shortName: 'å°ä¸­åœ‹å®¶æ­ŒåŠ‡é™¢', shortNameEn: 'National Taichung Theater', displayName: 'å°ä¸­å¸‚è¥¿å±¯å€æƒ ä¾†è·¯äºŒæ®µ101è™Ÿ', lat: 24.1630, lon: 120.6447),
  _LocationResult(shortName: 'æ–°å…‰ä¸‰è¶Šå°ä¸­ä¸­æ¸¯', shortNameEn: 'Shin Kong Mitsukoshi Taichung', displayName: 'å°ä¸­å¸‚è¥¿å±¯å€å°ç£å¤§é“ä¸‰æ®µ301è™Ÿ', lat: 24.1634, lon: 120.6469),
  _LocationResult(shortName: 'å¤§é‡Œå¸‚å€', shortNameEn: 'Dali District', displayName: 'å°ä¸­å¸‚å¤§é‡Œå€', lat: 24.0999, lon: 120.6784),
  _LocationResult(shortName: 'è±åŽŸç«è»Šç«™', shortNameEn: 'Fengyuan Train Station', displayName: 'å°ä¸­å¸‚è±åŽŸå€åœ“ç’°å—è·¯', lat: 24.2519, lon: 120.7188),
  _LocationResult(shortName: 'æ±æµ·å¤§å­¸', shortNameEn: 'Tunghai University', displayName: 'å°ä¸­å¸‚é¾äº•å€å°ç£å¤§é“å››æ®µ1727è™Ÿ', lat: 24.1792, lon: 120.5993),
];

const _aliases = <String, String>{
  // Feng Chia University â€” covers romanised, phonetic Mandarin, and abbreviation
  'fengchia': 'é€¢ç”²å¤§å­¸', 'feng chia': 'é€¢ç”²å¤§å­¸', 'fengjia': 'é€¢ç”²å¤§å­¸',
  'feng jia': 'é€¢ç”²å¤§å­¸', 'fcu': 'é€¢ç”²å¤§å­¸', 'feng chia university': 'é€¢ç”²å¤§å­¸',

  // Taichung Train Station
  'taichung station': 'å°ä¸­ç«è»Šç«™', 'train station': 'å°ä¸­ç«è»Šç«™',
  'taichung railway': 'å°ä¸­ç«è»Šç«™', 'taichung train': 'å°ä¸­ç«è»Šç«™',
  'huo che zhan': 'å°ä¸­ç«è»Šç«™',

  // City Hall
  'city hall': 'å°ä¸­å¸‚æ”¿åºœ', 'taichung city hall': 'å°ä¸­å¸‚æ”¿åºœ',

  // NCHU â€” covers full English name and common abbreviations
  'nchu': 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸', 'chung hsing': 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸',
  'national chung hsing': 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸',
  'chung hsing university': 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸',
  'zhong xing': 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸', 'zhongxing': 'åœ‹ç«‹ä¸­èˆˆå¤§å­¸',

  // THSR
  'thsr': 'é«˜éµå°ä¸­ç«™', 'hsr': 'é«˜éµå°ä¸­ç«™', 'high speed': 'é«˜éµå°ä¸­ç«™',
  'taichung hsr': 'é«˜éµå°ä¸­ç«™', 'gaotie': 'é«˜éµå°ä¸­ç«™',

  // Tunghai University
  'tunghai': 'æ±æµ·å¤§å­¸', 'dong hai': 'æ±æµ·å¤§å­¸',
  'tunghai university': 'æ±æµ·å¤§å­¸', 'thu': 'æ±æµ·å¤§å­¸',

  // Airport
  'airport': 'å°ä¸­æ©Ÿå ´', 'taichung airport': 'å°ä¸­æ©Ÿå ´',

  // Veterans General Hospital
  'veterans': 'å°ä¸­æ¦®ç¸½', 'taichung veterans': 'å°ä¸­æ¦®ç¸½', 'vghtc': 'å°ä¸­æ¦®ç¸½',
};

List<_LocationResult> _filterPopular(String query) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return _popularLocations.take(5).toList();

  for (final entry in _aliases.entries) {
    if (q.contains(entry.key) || entry.key.contains(q)) {
      final match = _popularLocations.firstWhere(
        (p) => p.shortName == entry.value,
        orElse: () => _popularLocations.first,
      );
      final others = _popularLocations
          .where((p) =>
              p.shortName.contains(q) ||
              p.displayName.contains(q) ||
              p.shortName != match.shortName)
          .take(4)
          .toList();
      return [match, ...others.where((p) => p.shortName != match.shortName)];
    }
  }

  return _popularLocations
      .where((p) =>
          p.shortName.contains(q) ||
          p.shortNameEn.toLowerCase().contains(q) ||
          p.displayName.contains(q) ||
          q.contains(p.shortName))
      .toList();
}

Future<List<_LocationResult>> _nominatimSearch(String query, LatLng origin) async {
  final q = query.trim();
  if (q.length < 2) return [];

  // Translate English alias to Chinese for a more accurate OSM lookup
  String searchQuery = q;
  final qLower = q.toLowerCase();
  for (final entry in _aliases.entries) {
    if (qLower.contains(entry.key)) {
      searchQuery = entry.value;
      break;
    }
  }

  // Try progressively: Chinese name in Taiwan â†’ original query in Taiwan â†’ original query
  final queries = [
    if (searchQuery != q) '$searchQuery å°ä¸­',
    '$searchQuery Taiwan',
    '$q Taiwan',
    q,
  ];

  for (final sq in queries) {
    try {
      final uri =
          Uri.parse('https://nominatim.openstreetmap.org/search').replace(
        queryParameters: {
          'q': sq,
          'format': 'json',
          'limit': '6',
          'countrycodes': 'tw',       // restrict to Taiwan
          'accept-language': 'zh-TW,zh,en',
          'addressdetails': '1',
        },
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'TaiwanBusTracker/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) continue;
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      if (data.isNotEmpty) {
        // Prefer amenity/education results over roads or postcodes
        final sorted = List<Map<String, dynamic>>.from(
          data.map((e) => e as Map<String, dynamic>),
        )..sort((a, b) {
            const preferred = {'amenity', 'tourism', 'building', 'landuse'};
            final aScore = preferred.contains(a['class']) ? 0 : 1;
            final bScore = preferred.contains(b['class']) ? 0 : 1;
            if (aScore != bScore) return aScore.compareTo(bScore);
            // Same class tier â€” prefer whichever branch is closer to the user,
            // since chain results (e.g. a department store) return every
            // branch nationwide and Nominatim's default order favours the
            // most "important" one (often Taipei) over the nearest one.
            final aDist = haversineDistance(origin.latitude, origin.longitude,
                double.parse(a['lat'] as String), double.parse(a['lon'] as String));
            final bDist = haversineDistance(origin.latitude, origin.longitude,
                double.parse(b['lat'] as String), double.parse(b['lon'] as String));
            return aDist.compareTo(bDist);
          });
        // Substitute curated coordinates when result matches a known popular location,
        // because Nominatim returns polygon centroids which can be off for large areas.
        return sorted.map((e) {
          final r = _LocationResult.fromNominatim(e);
          for (final p in _popularLocations) {
            if (r.shortName.contains(p.shortName) ||
                p.shortName.contains(r.shortName)) {
              return _LocationResult(
                shortName: p.shortName,
                displayName: r.displayName,
                lat: p.lat,
                lon: p.lon,
              );
            }
          }
          return r;
        }).toList();
      }
    } catch (_) {
      continue;
    }
  }

  return _filterPopular(q);
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  LatLng? _userLocation;
  bool _locationGranted = false;
  String? _selectedRoute;

  List<_LocationResult> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _showSuggestions = false;

  Timer? _debounce;

  // Directions state
  _LocationResult? _selectedDestination;
  List<LatLng> _directionsPolyline = [];
  String? _directionsEta;
  String? _directionsDistance;
  bool _fetchingDirections = false;
  String? _transportMode; // 'bus' | 'walk' | 'car' | null = no route
  List<String> _busLines = [];
  String? _walkHint;

  // â”€â”€â”€ Sheet / route-detail state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _sheetController = DraggableScrollableController();
  final _busSearchController = TextEditingController();
  String _busSearchQuery = '';
  int _sheetTab = 0; // 0 = nearby, 1 = search
  bool _inRouteDetail = false;
  int? _selectedDirection; // 0 = outbound åŽ»ç¨‹, 1 = inbound å›žç¨‹
  String? _userStopUID; // stop the user tapped from â€” highlighted in route detail

  // Current fractional height (0..1) of the draggable sheet â€” used to keep
  // GoogleMap's own bounds from extending underneath it. On Android, the
  // GoogleMap platform view greedily wins the gesture arena for any touch
  // that lands within its widget bounds (flutter/flutter#59433), so taps on
  // sibling widgets stacked on top (like the sheet's tab bar) never reach
  // Flutter at all unless the map's layout literally stops short of them.
  double _sheetExtent = 0.10;

  // Cached each build from languageProvider so event handlers (map taps,
  // async direction fetches) that run outside the build phase can read the
  // current language without calling ref.watch outside of build().
  AppLanguage _lang = AppLanguage.zh;

  @override
  void initState() {
    super.initState();
    _requestLocation();
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && _searchController.text.isEmpty) {
        setState(() {
          _suggestions = _popularLocations.take(5).toList();
          _showSuggestions = true;
        });
      }
      if (!_searchFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showSuggestions = false);
        });
      }
    });
    _sheetController.addListener(_onSheetExtentChanged);
  }

  void _onSheetExtentChanged() {
    if (!_sheetController.isAttached) return;
    setState(() => _sheetExtent = _sheetController.size);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _busSearchController.dispose();
    _sheetController.removeListener(_onSheetExtentChanged);
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) { return; }

      if (mounted) setState(() => _locationGranted = true);

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) {
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() => _userLocation = loc);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 14));
      }
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();

    if (q.isEmpty) {
      setState(() {
        _suggestions = _popularLocations.take(5).toList();
        _showSuggestions = true;
        _loadingSuggestions = false;
      });
      return;
    }

    final instant = _filterPopular(q);
    setState(() {
      _suggestions = instant;
      _showSuggestions = true;
      _loadingSuggestions = q.length >= 2;
    });

    if (q.length < 2) return;

    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await _nominatimSearch(q, _userLocation ?? _defaultCenter);
      if (mounted) {
        setState(() {
          _suggestions = results.isNotEmpty ? results : _filterPopular(q);
          _loadingSuggestions = false;
          _showSuggestions = true;
        });
      }
    });
  }

  void _selectSuggestion(_LocationResult result) {
    _searchController.text = result.shortName;
    _debounce?.cancel();
    _searchFocus.unfocus();
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
      _loadingSuggestions = false;
      _selectedDestination = result;
      _directionsPolyline = [];
      _directionsEta = null;
      _directionsDistance = null;
      _fetchingDirections = true;
    });
    // Move camera to destination immediately, then re-fit after route loads
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lon), 15),
    );
    _fetchDirections(result);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _suggestions = _popularLocations.take(5).toList();
      _showSuggestions = false;
      _loadingSuggestions = false;
    });
    _clearDirections();
  }

  // â”€â”€â”€ Route detail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _toggleSheet() {
    const snaps = [0.10, 0.38, 0.72];
    final current = _sheetController.size;
    // Advance to the next snap point, cycling back to the first after the last
    final next = snaps.firstWhere(
      (s) => s > current + 0.05,
      orElse: () => snaps.first,
    );
    _sheetController.animateTo(
      next,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _enterRouteDetail(String routeID, int direction, {String? userStopUID}) {
    setState(() {
      _selectedRoute = routeID;
      _selectedDirection = direction;
      _inRouteDetail = true;
      _userStopUID = userStopUID;
    });
    _sheetController.animateTo(0.38,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _exitRouteDetail() {
    setState(() {
      _selectedRoute = null;
      _selectedDirection = null;
      _inRouteDetail = false;
      _userStopUID = null;
    });
  }

  // â”€â”€â”€ Directions API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _clearDirections() {
    setState(() {
      _selectedDestination = null;
      _directionsPolyline = [];
      _directionsEta = null;
      _directionsDistance = null;
      _fetchingDirections = false;
      _transportMode = null;
      _busLines = [];
      _walkHint = null;
    });
  }

  // Shared helper â€” tries Google transit (bus) from [from] to [to].
  // Returns parsed result or null on failure/no route.
  Future<({String eta, String dist, List<LatLng> points, List<String> busLines})?> _tryTransit(
    LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json',
      ).replace(queryParameters: {
        'origin': '${from.latitude},${from.longitude}',
        'destination': '${to.latitude},${to.longitude}',
        'mode': 'transit',
        'transit_mode': 'bus',
        'language': 'zh-TW',
        'key': _googleMapsApiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) return null;
      final leg = ((routes[0] as Map)['legs'] as List<dynamic>)[0]
          as Map<String, dynamic>;
      final eta = (leg['duration'] as Map)['text'] as String;
      final dist = (leg['distance'] as Map)['text'] as String;
      final points = _extractDetailedPolyline(leg);
      // Extract bus line numbers
      final busLines = <String>[];
      for (final step in leg['steps'] as List<dynamic>) {
        final s = step as Map<String, dynamic>;
        if (s['travel_mode'] == 'TRANSIT') {
          final td = s['transit_details'] as Map<String, dynamic>?;
          final line = td?['line'] as Map<String, dynamic>?;
          if (line != null) {
            final type = (line['vehicle'] as Map<String, dynamic>?)?['type'] as String?;
            if (type == null || type == 'BUS') {
              final name = (line['short_name'] ?? line['name']) as String?;
              if (name != null && !busLines.contains(name)) busLines.add(name);
            }
          }
        }
      }
      return (eta: eta, dist: dist, points: points, busLines: busLines);
    } catch (_) {
      return null;
    }
  }

  Future<({String eta, String dist, List<LatLng> points})?> _tryDriving(
      LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json',
      ).replace(queryParameters: {
        'origin': '${from.latitude},${from.longitude}',
        'destination': '${to.latitude},${to.longitude}',
        'mode': 'driving',
        'key': _googleMapsApiKey,
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) return null;
      final leg = ((routes[0] as Map)['legs'] as List<dynamic>)[0]
          as Map<String, dynamic>;
      final eta = (leg['duration'] as Map)['text'] as String;
      final dist = (leg['distance'] as Map)['text'] as String;
      return (eta: eta, dist: dist, points: _extractDetailedPolyline(leg));
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchDirections(_LocationResult destination) async {
    setState(() {
      _fetchingDirections = true;
      _transportMode = null;
      _busLines = [];
      _walkHint = null;
    });

    final dest = LatLng(destination.lat, destination.lon);
    final origin = _userLocation ?? _defaultCenter;

    // â”€â”€ Step 1: direct transit to destination â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final direct = await _tryTransit(origin, dest);
    if (direct != null && mounted) {
      setState(() {
        _directionsEta = direct.eta;
        _directionsDistance = direct.dist;
        _directionsPolyline = direct.points;
        _fetchingDirections = false;
        _transportMode = 'bus';
        _busLines = direct.busLines;
        _walkHint = null;
      });
      if (direct.points.isNotEmpty) {
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
            _latLngBounds([origin, dest, ...direct.points]), 72));
      }
      return;
    }

    // â”€â”€ Step 2: no direct bus â€” find stops near destination, walk the last bit
    try {
      final nearbyAtDest = await PtxApi.instance.getNearbyStops(
        destination.lat, destination.lon, defaultCity, radius: 800,
      );
      nearbyAtDest.sort((a, b) => haversineDistance(
        destination.lat, destination.lon,
        a.stopPosition.lat, a.stopPosition.lon,
      ).compareTo(haversineDistance(
        destination.lat, destination.lon,
        b.stopPosition.lat, b.stopPosition.lon,
      )));

      for (final stop in nearbyAtDest.take(5)) {
        final stopLatLng = LatLng(stop.stopPosition.lat, stop.stopPosition.lon);
        final partial = await _tryTransit(origin, stopLatLng);
        if (partial == null) continue;

        final walkDist = haversineDistance(
          stop.stopPosition.lat, stop.stopPosition.lon,
          destination.lat, destination.lon,
        );
        final walkMins = (walkDist / 75).ceil();
        final distLabel = walkDist < 1000
            ? '${walkDist.toStringAsFixed(0)} m'
            : '${(walkDist / 1000).toStringAsFixed(1)} km';
        final hint = AppStrings.walkHintLabel(
            _lang, walkMins, distLabel, destination.shortName);

        if (mounted) {
          setState(() {
            _directionsEta = partial.eta;
            _directionsDistance = partial.dist;
            _directionsPolyline = partial.points;
            _fetchingDirections = false;
            _transportMode = 'bus';
            _busLines = partial.busLines;
            _walkHint = hint;
          });
          // Fix: include actual dest in bounds so the pin is always visible
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
              _latLngBounds([origin, dest, stopLatLng,
                  ...partial.points]), 72));
        }
        return;
      }
    } catch (_) {}

    // â”€â”€ Step 3: close enough to walk? (â‰¤ 1.5 km straight-line) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final straightLine = haversineDistance(
        origin.latitude, origin.longitude, dest.latitude, dest.longitude);
    if (straightLine <= 1500 && mounted) {
      final walkMins = (straightLine / 75).ceil();
      final distLabel = straightLine < 1000
          ? '${straightLine.toStringAsFixed(0)} m'
          : '${(straightLine / 1000).toStringAsFixed(1)} km';
      setState(() {
        _directionsEta = AppStrings.approxMinsLabel(_lang, walkMins);
        _directionsDistance = distLabel;
        _directionsPolyline = [];
        _fetchingDirections = false;
        _transportMode = 'walk';
        _busLines = [];
        _walkHint = null;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
          _latLngBounds([origin, dest]), 72));
      return;
    }

    // â”€â”€ Step 4: fall back to driving directions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final car = await _tryDriving(origin, dest);
    if (car != null && mounted) {
      setState(() {
        _directionsEta = car.eta;
        _directionsDistance = car.dist;
        _directionsPolyline = car.points;
        _fetchingDirections = false;
        _transportMode = 'car';
        _busLines = [];
        _walkHint = null;
      });
      if (car.points.isNotEmpty) {
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
            _latLngBounds([origin, dest, ...car.points]), 72));
      }
      return;
    }

    // â”€â”€ No route found at all â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (mounted) {
      setState(() {
        _fetchingDirections = false;
        _transportMode = null;
        _directionsPolyline = [];
        _directionsEta = null;
        _directionsDistance = null;
        _busLines = [];
        _walkHint = null;
      });
    }
  }

  // Concatenates each step's own polyline instead of using overview_polyline,
  // which Google deliberately simplifies for small-scale display and cuts
  // corners at turns. Per-step polylines follow the actual road geometry.
  List<LatLng> _extractDetailedPolyline(Map<String, dynamic> leg) {
    final points = <LatLng>[];
    for (final step in leg['steps'] as List<dynamic>) {
      final s = step as Map<String, dynamic>;
      final encoded = (s['polyline'] as Map<String, dynamic>?)?['points'] as String?;
      if (encoded == null) continue;
      final stepPoints = _decodePolyline(encoded);
      if (points.isNotEmpty &&
          stepPoints.isNotEmpty &&
          points.last == stepPoints.first) {
        points.addAll(stepPoints.skip(1));
      } else {
        points.addAll(stepPoints);
      }
    }
    return points;
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  LatLngBounds _latLngBounds(List<LatLng> points) {
    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // â”€â”€â”€ Build Google Maps marker set â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Set<Marker> _buildMarkers(
    List<BusRealTime> buses,
    List<RouteStop> routeStops,
  ) {
    final markers = <Marker>{};

    // Live bus position markers â€” filtered by direction when in route detail
    for (final bus in buses) {
      if (_selectedDirection != null && bus.direction != _selectedDirection) continue;
      markers.add(Marker(
        markerId: MarkerId('bus_${bus.plateNumb}'),
        position: LatLng(bus.busPosition.lat, bus.busPosition.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: AppStrings.route(_lang, _selectedRoute ?? ''),
          snippet:
              '${bus.plateNumb}  ${bus.direction == 0 ? AppStrings.t(_lang, 'outbound') : AppStrings.t(_lang, 'inbound')}',
        ),
        zIndexInt: 2,
      ));
    }

    // Route stop markers â€” show only selected direction, hidden while destination active
    if (_selectedDestination == null && _selectedDirection != null) {
      for (final stop in routeStops) {
        if (stop.direction != _selectedDirection) continue;
        markers.add(Marker(
          markerId: MarkerId('rstop_${stop.stopUID}'),
          position: LatLng(stop.stopPosition.lat, stop.stopPosition.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: stop.stopName.forLang(_lang),
            snippet:
                '${AppStrings.route(_lang, _selectedRoute ?? '')}  â€¢  ${AppStrings.stopFallbackLabel(_lang, stop.stopSequence)}',
          ),
          onTap: () => _showStopOptions(stop),
          alpha: 0.85,
          zIndexInt: 1,
        ));
      }
    }

    // Destination pin (when a location is selected from search)
    if (_selectedDestination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(_selectedDestination!.lat, _selectedDestination!.lon),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: _selectedDestination!.shortName),
        zIndexInt: 10,
      ));
    }

    return markers;
  }

  // â”€â”€â”€ Build route polylines from TDX stop positions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Set<Polyline> _buildPolylines(List<RouteStop> stops) {
    final polylines = <Polyline>{};

    // TDX bus route polyline â€” only the selected direction when in route detail
    if (stops.isNotEmpty && _selectedDirection != null) {
      final dirStops = stops
          .where((s) => s.direction == _selectedDirection)
          .toList()
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

      if (dirStops.isNotEmpty) {
        polylines.add(Polyline(
          polylineId: const PolylineId('route_selected'),
          points: dirStops
              .map((s) => LatLng(s.stopPosition.lat, s.stopPosition.lon))
              .toList(),
          color: AppColors.blue,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ));
      }
    }

    // Directions route â€” colour depends on transport mode
    if (_directionsPolyline.isNotEmpty) {
      final routeColor = _transportMode == 'car'
          ? AppColors.yellow
          : _transportMode == 'walk'
              ? AppColors.blue
              : AppColors.green;
      polylines.add(Polyline(
        polylineId: const PolylineId('directions'),
        points: _directionsPolyline,
        color: routeColor,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ));
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final favourites = ref.watch(favouritesProvider);
    _lang = ref.watch(languageProvider);

    final List<BusRealTime> buses;
    final List<RouteStop> routeStops;
    if (_selectedRoute != null) {
      final routeParams = (routeName: _selectedRoute!, city: defaultCity);
      buses = ref.watch(busPositionsProvider(routeParams)).value ?? [];
      routeStops = ref.watch(routeStopsProvider(routeParams)).value ?? [];
    } else {
      buses = const [];
      routeStops = const [];
    }

    List<NearbyStop> sortedNearby = [];
    if (_userLocation != null) {
      final nearbyAsync = ref.watch(nearbyStopsProvider((
        lat: _userLocation!.latitude,
        lon: _userLocation!.longitude,
        city: defaultCity,
      )));
      final raw = nearbyAsync.value ?? [];
      sortedNearby = raw
          .map((s) => NearbyStop(
                stop: s,
                distance: haversineDistance(
                  _userLocation!.latitude,
                  _userLocation!.longitude,
                  s.stopPosition.lat,
                  s.stopPosition.lon,
                ),
              ))
          .toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));
      if (sortedNearby.length > 6) sortedNearby = sortedNearby.sublist(0, 6);
    }

    // Aggregate live arrivals for nearby stops (up to 4 stops â€” covers both sides
    // of the road so inbound and outbound buses both appear).
    // Paused while route detail is open to avoid competing with route position polls.
    final List<EstimatedArrival> nearbyArrivals;
    bool nearbyStillLoading = false;
    if (sortedNearby.isNotEmpty && !_inRouteDetail) {
      final raw = <EstimatedArrival>[];
      for (final ns in sortedNearby.take(4)) {
        final prov = ref.watch(stopArrivalsProvider((
          stopUID: ns.stop.stopUID,
          city: defaultCity,
        )));
        // Track whether we're still waiting for the first response
        if (prov.value == null && !prov.hasError) nearbyStillLoading = true;
        final a = prov.value ?? [];
        raw.addAll(a);
      }
      raw.sort((a, b) => a.estimateTime.compareTo(b.estimateTime));
      final seen = <String>{};
      nearbyArrivals = raw
          // Only show buses with normal stop status (0) and a valid ETA
          .where((a) => a.stopStatus == 0 && a.estimateTime >= 0)
          .where((a) => seen.add('${a.routeUID}-${a.direction}'))
          .toList();
    } else {
      nearbyArrivals = const [];
      nearbyStillLoading = false;
    }

    final markers = _buildMarkers(buses, routeStops);
    final polylines = _buildPolylines(routeStops);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // â”€â”€ Google Maps â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          // Bottom is pinned above the sheet's current top edge (rather than
          // filling the whole Stack) so the map's platform view never
          // underlaps the sheet â€” see _sheetExtent doc comment above.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: _sheetExtent * MediaQuery.sizeOf(context).height,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _userLocation ?? _defaultCenter,
                zoom: 14,
              ),
              style: darkMapStyle,
              onMapCreated: (controller) {
                _mapController = controller;
                if (_userLocation != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_userLocation!, 14),
                  );
                }
              },
              myLocationEnabled: _locationGranted,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: markers,
              polylines: polylines,
              onTap: (_) {
                _searchFocus.unfocus();
                setState(() => _showSuggestions = false);
              },
            ),
          ),

          // â”€â”€ Search bar + dropdown â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xF21F2330),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _searchFocus.hasFocus
                          ? AppColors.borderActive
                          : AppColors.border,
                    ),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 8,
                          offset: Offset(0, 3))
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: AppStrings.t(_lang, 'searchLocationHint'),
                      hintStyle: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                      prefixIcon: _loadingSuggestions
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.blue)))
                          : const Icon(Icons.search_rounded,
                              color: AppColors.blue, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.textMuted, size: 18),
                              onPressed: _clearSearch)
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 13),
                    ),
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      _debounce?.cancel();
                      setState(() => _loadingSuggestions = true);
                      _nominatimSearch(v, _userLocation ?? _defaultCenter).then((results) {
                        if (mounted) {
                          setState(() {
                            _suggestions = results.isNotEmpty
                                ? results
                                : _filterPopular(v);
                            _loadingSuggestions = false;
                            _showSuggestions = true;
                          });
                        }
                      });
                    },
                  ),
                ),
                if (_showSuggestions) ...[
                  const SizedBox(height: 4),
                  Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xF21F2330),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 3))
                        ],
                      ),
                      child: _buildSuggestionsList(),
                    ),
                  ),
                ],

                // â”€â”€ ETA card (shown after a destination is selected) â”€â”€â”€â”€â”€â”€â”€â”€
                if (_selectedDestination != null && !_showSuggestions) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xF21F2330),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _fetchingDirections || _transportMode == null
                            ? AppColors.border
                            : _transportMode == 'car'
                                ? AppColors.yellow.withValues(alpha: 0.5)
                                : _transportMode == 'walk'
                                    ? AppColors.blue.withValues(alpha: 0.5)
                                    : AppColors.green.withValues(alpha: 0.5),
                      ),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black38,
                            blurRadius: 8,
                            offset: Offset(0, 3))
                      ],
                    ),
                    child: _fetchingDirections
                        ? Row(children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.green),
                            ),
                            const SizedBox(width: 10),
                            Text(AppStrings.t(_lang, 'findingRoutes'),
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13)),
                          ])
                        : _transportMode == null
                            // â”€â”€ No route found â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                            ? Row(children: [
                                const Icon(Icons.not_interested_rounded,
                                    color: AppColors.textMuted, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedDestination!.shortName,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                          AppStrings.t(
                                              _lang, 'noRoutesFound'),
                                          style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _clearDirections,
                                  child: const Icon(Icons.close_rounded,
                                      color: AppColors.textMuted, size: 18),
                                ),
                              ])
                            // â”€â”€ Route found â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                            : Row(children: [
                                Icon(
                                  _transportMode == 'car'
                                      ? Icons.directions_car_rounded
                                      : _transportMode == 'walk'
                                          ? Icons.directions_walk_rounded
                                          : Icons.directions_bus_rounded,
                                  color: _transportMode == 'car'
                                      ? AppColors.yellow
                                      : _transportMode == 'walk'
                                          ? AppColors.blue
                                          : AppColors.green,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(
                                            _selectedDestination!.shortName,
                                            style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Bus line badges (bus mode only)
                                        if (_transportMode == 'bus' &&
                                            _busLines.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          ..._busLines.take(4).map((line) =>
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 4),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.green
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                      color: AppColors.green
                                                          .withValues(
                                                              alpha: 0.35)),
                                                ),
                                                child: Text(line,
                                                    style: const TextStyle(
                                                        color: AppColors.green,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                              )),
                                        ],
                                        // Mode label for car/walk
                                        if (_transportMode == 'car' ||
                                            _transportMode == 'walk') ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (_transportMode == 'car'
                                                      ? AppColors.yellow
                                                      : AppColors.blue)
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: (_transportMode == 'car'
                                                          ? AppColors.yellow
                                                          : AppColors.blue)
                                                      .withValues(alpha: 0.35)),
                                            ),
                                            child: Text(
                                              _transportMode == 'car'
                                                  ? AppStrings.t(
                                                      _lang, 'drive')
                                                  : AppStrings.t(
                                                      _lang, 'walk'),
                                              style: TextStyle(
                                                  color: _transportMode == 'car'
                                                      ? AppColors.yellow
                                                      : AppColors.blue,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ]),
                                      // ETA + distance
                                      if (_directionsEta != null)
                                        Text(
                                          '$_directionsEta Â· $_directionsDistance',
                                          style: TextStyle(
                                              color: _transportMode == 'car'
                                                  ? AppColors.yellow
                                                  : _transportMode == 'walk'
                                                      ? AppColors.blue
                                                      : AppColors.green,
                                              fontSize: 12),
                                        ),
                                      // Walk hint (bus to nearby stop + walk)
                                      if (_walkHint != null) ...[
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          const Icon(
                                              Icons.directions_walk_rounded,
                                              color: AppColors.textMuted,
                                              size: 11),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              _walkHint!,
                                              style: const TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 11),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ]),
                                      ],
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _clearDirections,
                                  child: const Icon(Icons.close_rounded,
                                      color: AppColors.textMuted, size: 18),
                                ),
                              ]),
                  ),
                ],
              ],
            ),
          ),

          // â”€â”€ Right-side buttons â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Column(
              children: [
                _MapBtn(
                  icon: Icons.my_location_rounded,
                  color: AppColors.blue,
                  onTap: () {
                    if (_userLocation != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_userLocation!, 15),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _LangBtn(
                  lang: _lang,
                  onTap: () =>
                      ref.read(languageProvider.notifier).toggle(),
                ),
                const SizedBox(height: 8),
                _MapBtn(
                  icon: Icons.document_scanner_rounded,
                  color: AppColors.textSecondary,
                  onTap: () => Navigator.pushNamed(context, '/scan'),
                ),
              ],
            ),
          ),

          // â”€â”€ Back button (visible only in route detail) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_inRouteDetail)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 90,
              left: 12,
              child: GestureDetector(
                onTap: _exitRouteDetail,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xF21F2330),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 6,
                          offset: Offset(0, 2))
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${AppStrings.route(_lang, _selectedRoute ?? '')}  ${_selectedDirection == 0 ? AppStrings.t(_lang, 'outbound') : AppStrings.t(_lang, 'inbound')}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    if (buses.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                                color: AppColors.green,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('${buses.length}',
                            style: const TextStyle(
                                color: AppColors.green, fontSize: 11)),
                      ]),
                  ]),
                ),
              ),
            ),

          // â”€â”€ Draggable bottom sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.10,
            minChildSize: 0.10,
            maxChildSize: 0.72,
            snap: true,
            snapSizes: const [0.10, 0.38, 0.72],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppColors.bgSheet,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: _inRouteDetail
                    ? _buildRouteDetailSheet(
                        scrollController, routeStops, buses)
                    : _buildTabSheet(scrollController, nearbyArrivals,
                        sortedNearby, favourites, nearbyStillLoading),
              );
            },
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€ Stop options modal â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showStopOptions(RouteStop stop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSheet,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF3A3D48),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(AppStrings.route(_lang, _selectedRoute ?? ''),
                  style: const TextStyle(
                      color: AppColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(stop.stopName.forLang(_lang),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              '${AppStrings.stopFallbackLabel(_lang, stop.stopSequence)}  â€¢  ${_selectedDirection == 0 ? AppStrings.t(_lang, 'outbound') : AppStrings.t(_lang, 'inbound')}',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: Text(AppStrings.t(_lang, 'getDirectionsToStop')),
              onPressed: stop.stopPosition.lat == 0 && stop.stopPosition.lon == 0
                  ? null // disable when position unknown
                  : () {
                      Navigator.pop(context);
                      final dest = _LocationResult(
                        shortName: stop.stopName.forLang(_lang),
                        displayName: stop.stopName.forLang(_lang),
                        lat: stop.stopPosition.lat,
                        lon: stop.stopPosition.lon,
                      );
                      _selectSuggestion(dest);
                    },
            ),
          ),
          if (stop.stopPosition.lat == 0 && stop.stopPosition.lon == 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                AppStrings.t(_lang, 'stopLocationUnavailable'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
        ]),
      ),
    );
  }

  // â”€â”€â”€ Sheet content builders â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTabSheet(
    ScrollController sc,
    List<EstimatedArrival> nearbyArrivals,
    List<NearbyStop> sortedNearby,
    List<String> favourites,
    bool nearbyLoading,
  ) {
    return ListView(
      controller: sc,
      padding: EdgeInsets.fromLTRB(
          12, 0, 12, 12 + MediaQuery.of(context).padding.bottom),
      children: [
        // Drag handle â€” drag or tap to cycle through snap positions
        GestureDetector(
          onTap: _toggleSheet,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFF3A3D48),
                      borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ),
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(children: [
            _SheetTab(
                label: AppStrings.t(_lang, 'nearbyTab'),
                active: _sheetTab == 0,
                onTap: () => setState(() => _sheetTab = 0)),
            _SheetTab(
                label: AppStrings.t(_lang, 'routesTab'),
                active: _sheetTab == 1,
                onTap: () => setState(() => _sheetTab = 1)),
          ]),
        ),
        const SizedBox(height: 12),
        if (_sheetTab == 0)
          _buildNearbyTab(nearbyArrivals, sortedNearby, nearbyLoading)
        else
          _buildSearchTab(favourites),
      ],
    );
  }

  Widget _buildRouteDetailSheet(
    ScrollController sc,
    List<RouteStop> routeStops,
    List<BusRealTime> buses,
  ) {
    // Get per-stop arrival ETAs for this route
    final arrivalsAsync = _selectedRoute != null
        ? ref.watch(arrivalEstimatesProvider((
            routeName: _selectedRoute!,
            city: defaultCity,
          )))
        : const AsyncValue<List<EstimatedArrival>>.data([]);
    final arrivals = arrivalsAsync.value ?? [];

    // Build stopUID â†’ best ETA for selected direction
    final etaMap = <String, ({int seconds, int stopStatus})>{};
    for (final a in arrivals) {
      if (a.direction == _selectedDirection) {
        final existing = etaMap[a.stopUID];
        if (existing == null || a.estimateTime < existing.seconds) {
          etaMap[a.stopUID] = (seconds: a.estimateTime, stopStatus: a.stopStatus);
        }
      }
    }

    // Compute direction tab labels from terminal stops
    final outStops = routeStops.where((s) => s.direction == 0).toList()
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    final inStops = routeStops.where((s) => s.direction == 1).toList()
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

    final outEnd =
        outStops.isNotEmpty ? outStops.last.stopName.forLang(_lang) : '';
    final inEnd =
        inStops.isNotEmpty ? inStops.last.stopName.forLang(_lang) : '';

    final dirStops = (_selectedDirection == 0 ? outStops : inStops);
    final isLoading = routeStops.isEmpty;

    return ListView(
      controller: sc,
      padding: EdgeInsets.fromLTRB(
          12, 0, 12, 12 + MediaQuery.of(context).padding.bottom),
      children: [
        GestureDetector(
          onTap: _toggleSheet,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFF3A3D48),
                      borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ),

        // Direction tabs â€” show when stops are loaded
        if (!isLoading && (outEnd.isNotEmpty || inEnd.isNotEmpty)) ...[
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(children: [
              _SheetTab(
                label: outEnd.isNotEmpty
                    ? AppStrings.toDestination(_lang, outEnd)
                    : AppStrings.t(_lang, 'outbound'),
                active: _selectedDirection == 0,
                onTap: () => setState(() => _selectedDirection = 0),
              ),
              _SheetTab(
                label: inEnd.isNotEmpty
                    ? AppStrings.toDestination(_lang, inEnd)
                    : AppStrings.t(_lang, 'inbound'),
                active: _selectedDirection == 1,
                onTap: () => setState(() => _selectedDirection = 1),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],

        // Loading state
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.blue, strokeWidth: 2)),
          )
        else ...[
          // Stop list with ETAs
          ...dirStops.asMap().entries.map((e) {
            final stop = e.value;
            final isFirst = e.key == 0;
            final isLast = e.key == dirStops.length - 1;
            final isUserStop = stop.stopUID == _userStopUID;
            final etaData = etaMap[stop.stopUID];
            final etaSec = etaData?.seconds;
            final stopSt = etaData?.stopStatus ?? -1;

            // ETA label + colour â€” mirrors the reference Taichung app style
            String? etaLabel;
            Color etaColor = AppColors.textMuted;
            bool isApproach = false;
            if (stopSt == 0 && etaSec != null && etaSec >= 0) {
              if (etaSec <= 60) {
                etaLabel = AppStrings.t(_lang, 'approach');
                etaColor = AppColors.red;
                isApproach = true;
              } else {
                final mins = (etaSec / 60).ceil();
                etaLabel = AppStrings.minsLabel(_lang, mins);
                etaColor = mins <= 2
                    ? AppColors.yellow
                    : AppColors.textMuted;
              }
            } else if (stopSt > 0) {
              etaLabel = AppStrings.t(_lang, 'servOver');
            }

            // Live bus within 300 m of this stop
            final hasBus = stop.stopPosition.lat != 0 &&
                buses.any((b) =>
                    b.direction == _selectedDirection &&
                    haversineDistance(b.busPosition.lat, b.busPosition.lon,
                            stop.stopPosition.lat, stop.stopPosition.lon) <
                        300);

            final stopLabelValue = stop.stopName.forLang(_lang);
            final stopLabel = stopLabelValue.isNotEmpty
                ? stopLabelValue
                : AppStrings.stopFallbackLabel(_lang, stop.stopSequence);

            // Border colour priority: user's stop > bus nearby > default
            final borderColor = isUserStop
                ? AppColors.blue.withValues(alpha: 0.7)
                : hasBus
                    ? AppColors.green.withValues(alpha: 0.5)
                    : AppColors.border;

            // Dot colour: user's stop = solid blue, bus here = green, terminal = blue outline
            final dotColor = isUserStop
                ? AppColors.blue
                : hasBus
                    ? AppColors.green
                    : isFirst || isLast
                        ? AppColors.blue
                        : AppColors.border;

            return GestureDetector(
              onTap: () => _showStopOptions(stop),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isUserStop
                      ? AppColors.blue.withValues(alpha: 0.08)
                      : AppColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  // ETA pill (left side, like the reference app)
                  if (etaLabel != null)
                    Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isApproach
                            ? AppColors.red
                            : etaColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        etaLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isApproach ? Colors.white : etaColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 72),
                  const SizedBox(width: 10),
                  // Stop dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(
                          color: isUserStop || hasBus
                              ? dotColor
                              : AppColors.blue,
                          width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Stop name
                  Expanded(
                    child: Text(
                      stopLabel,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: isUserStop
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (hasBus)
                    const Icon(Icons.directions_bus_rounded,
                        color: AppColors.green, size: 14),
                ]),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildNearbyTab(
      List<EstimatedArrival> arrivals,
      List<NearbyStop> sortedNearby,
      bool loading) {
    if (_userLocation == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text(AppStrings.t(_lang, 'gettingLocation'),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13))),
      );
    }
    if (sortedNearby.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text(AppStrings.t(_lang, 'noNearbyStops'),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13))),
      );
    }
    // First load â€” show spinner instead of "no buses"
    if (loading && arrivals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(
                color: AppColors.blue, strokeWidth: 2)),
      );
    }
    if (arrivals.isEmpty) {
      final h = DateTime.now().hour;
      final offHours = h < 6 || h >= 23;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (offHours) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.yellow.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppColors.yellow, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.t(_lang, 'busServiceInactiveShort'),
                      style: const TextStyle(
                          color: AppColors.yellow, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ] else ...[
              const Icon(Icons.directions_bus_outlined,
                  color: AppColors.textMuted, size: 28),
              const SizedBox(height: 8),
              Text(AppStrings.t(_lang, 'noBusesArrivingSoon'),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.t(_lang, 'arrivingSoonHeader'),
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 1.2)),
        const SizedBox(height: 8),
        ...arrivals.map((a) => _buildArrivalCard(a)),
      ],
    );
  }

  Widget _buildArrivalCard(EstimatedArrival arrival) {
    final mins = (arrival.estimateTime / 60).ceil();
    final etaLabel = mins <= 0
        ? AppStrings.t(_lang, 'arriving')
        : AppStrings.minsLabel(_lang, mins);
    final etaColor =
        mins <= 1 ? AppColors.green : mins <= 5 ? AppColors.yellow : AppColors.textMuted;

    return GestureDetector(
      onTap: () => _enterRouteDetail(
        arrival.routeName.zhTw,
        arrival.direction,
        userStopUID: arrival.stopUID,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6)),
            child: Text(arrival.routeName.forLang(_lang),
                style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(arrival.stopName.forLang(_lang),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    arrival.direction == 0
                        ? AppStrings.t(_lang, 'outbound')
                        : AppStrings.t(_lang, 'inbound'),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Text(etaLabel,
              style: TextStyle(
                  color: etaColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 16),
        ]),
      ),
    );
  }

  Widget _buildSearchTab(List<String> favourites) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _busSearchController,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: AppStrings.t(_lang, 'enterRouteNumberHint'),
              hintStyle: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.blue, size: 20),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
            ),
            onChanged: (v) =>
                setState(() => _busSearchQuery = v.trim()),
          ),
        ),
        const SizedBox(height: 12),
        if (_busSearchQuery.isNotEmpty)
          Consumer(builder: (ctx, cref, _) {
            final searchAsync = cref.watch(routeSearchProvider((
              query: _busSearchQuery,
              city: defaultCity,
            )));
            return searchAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.blue, strokeWidth: 2)),
              ),
              error: (_, __) => Text(
                  AppStrings.t(_lang, 'searchFailedTryAgain'),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
              data: (routes) {
                if (routes.isEmpty) {
                  return Text(AppStrings.t(_lang, 'routeNotFound'),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.t(_lang, 'resultsHeader'),
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    ...routes.expand((r) => [
                          _buildDirectionCard(r, 0, favourites),
                          _buildDirectionCard(r, 1, favourites),
                        ]),
                  ],
                );
              },
            );
          })
        else
          Text(AppStrings.t(_lang, 'searchTaichungRoutes'),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
      ],
    );
  }

  Widget _buildDirectionCard(
      BusRoute route, int direction, List<String> favourites) {
    final from = direction == 0
        ? route.departureStopNameZh
        : route.destinationStopNameZh;
    final to = direction == 0
        ? route.destinationStopNameZh
        : route.departureStopNameZh;
    final dirLabel = direction == 0
        ? AppStrings.t(_lang, 'outbound')
        : AppStrings.t(_lang, 'inbound');
    final isFav = favourites.contains(route.routeName.zhTw);

    return GestureDetector(
      onTap: () => _enterRouteDetail(route.routeID, direction),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          // Route number badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Text(route.routeName.forLang(_lang),
                style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          // Direction
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(from,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: AppColors.textMuted, size: 13),
                  ),
                  Text(to,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ]),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(3)),
                  child: Text(dirLabel,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          // Favourite + chevron
          GestureDetector(
            onTap: () => ref
                .read(favouritesProvider.notifier)
                .toggle(route.routeName.zhTw),
            child: Icon(
                isFav ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFav ? AppColors.yellow : AppColors.textMuted,
                size: 18),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 16),
        ]),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (_loadingSuggestions && _suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.blue)),
          const SizedBox(width: 10),
          Text(AppStrings.t(_lang, 'searching'),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
        ]),
      );
    }

    if (_suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.location_off_outlined,
              color: AppColors.textMuted, size: 16),
          const SizedBox(width: 8),
          Text(AppStrings.t(_lang, 'noLocationsFound'),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
        ]),
      );
    }

    return Column(
      children: _suggestions.asMap().entries.map((e) {
        final isLast = e.key == _suggestions.length - 1;
        return _SuggestionTile(
          result: e.value,
          isLast: isLast,
          lang: _lang,
          onTap: () => _selectSuggestion(e.value),
        );
      }).toList(),
    );
  }
}

// â”€â”€â”€ Widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SuggestionTile extends StatelessWidget {
  final _LocationResult result;
  final bool isLast;
  final AppLanguage lang;
  final VoidCallback onTap;
  const _SuggestionTile(
      {required this.result,
      required this.isLast,
      required this.lang,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    // In English mode, show the English name first (when available) and the
    // Chinese name as the secondary line — reversed from the zh default.
    final showEnFirst = lang == AppLanguage.en && result.shortNameEn.isNotEmpty;
    final primaryName = showEnFirst ? result.shortNameEn : result.shortName;
    final secondaryName = showEnFirst ? result.shortName : result.shortNameEn;

    return InkWell(
      onTap: onTap,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(14))
          : BorderRadius.zero,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom:
                      BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.place_outlined,
                color: AppColors.blue, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show both Chinese and English when both are available
                  Text(primaryName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (secondaryName.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(secondaryName,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 1),
                  Text(result.displayName,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.north_west_rounded,
                color: AppColors.textMuted, size: 13),
          ],
        ),
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MapBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xCC1F2330),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _LangBtn extends StatelessWidget {
  final AppLanguage lang;
  final VoidCallback onTap;
  const _LangBtn({required this.lang, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xCC1F2330),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          lang == AppLanguage.zh ? '中' : 'EN',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SheetTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SheetTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.bgSheet : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.textPrimary : AppColors.textMuted,
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
