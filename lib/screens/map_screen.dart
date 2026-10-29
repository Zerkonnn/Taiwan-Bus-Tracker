// MapScreen — Google Maps + TDX Taichung Bus API
// Google Maps handles the interactive map; TDX provides accurate live bus
// positions, ETAs, route stop positions (for polylines), and nearby stops.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../services/ptx_api.dart';
import '../services/trip_history.dart';
import '../utils/app_strings.dart';
import '../utils/crash_recovery.dart';
import '../utils/theme.dart';
import '../design/components.dart';
import '../design/tokens.dart';

const _defaultCenter = LatLng(24.1477, 120.6736);

// Same key used for Maps SDK in AndroidManifest.xml — must also have
// Directions API enabled in Google Cloud Console for this project.
const _googleMapsApiKey = 'AIzaSyDUPCYVGg1mKjrkzbBtSsaopGXbY8SDj18';

// ─── Popular Taiwan locations (instant search fallback) ───────────────────────

class _LocationResult {
  final String shortName;    // Chinese name (or Nominatim result)
  final String shortNameEn;  // English name for popular locations
  final String displayName;
  final double lat;
  final double lon;
  // > 0 when this is a remembered trip the user has made on that many days.
  final int tripDays;

  const _LocationResult({
    required this.shortName,
    this.shortNameEn = '',
    required this.displayName,
    required this.lat,
    required this.lon,
    this.tripDays = 0,
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

// One bus itinerary returned by the Directions API (may include transfers).
class _TransitOption {
  final String eta;
  final String dist;
  final int durationSecs;
  final int distanceMeters;
  final int transfers; // bus changes: 0 = one bus all the way
  final int walkMeters; // total walking along the itinerary
  // The itinerary in travel order, one entry per walk / bus ride. Mutable so
  // bus rides can be swapped for the road-snapped version once it loads.
  final List<_RouteSegment> segments;
  final List<String> busLines;

  const _TransitOption({
    required this.eta,
    required this.dist,
    required this.durationSecs,
    required this.distanceMeters,
    required this.transfers,
    required this.walkMeters,
    required this.segments,
    required this.busLines,
  });

  Iterable<LatLng> get points => segments.expand((s) => s.points);
}

enum _SegMode { walk, bus, car }

// One leg of a route on the map, drawn according to how it is travelled:
// bus rides as a solid outlined line, walking as a trail of footprints.
class _RouteSegment {
  final _SegMode mode;
  final List<LatLng> points;
  final String? line; // bus route number (bus only)
  final LatLng? from; // boarding stop (bus only)
  final LatLng? to; // alighting stop (bus only)

  const _RouteSegment(this.mode, this.points, {this.line, this.from, this.to});

  _RouteSegment withPoints(List<LatLng> points) =>
      _RouteSegment(mode, points, line: line, from: from, to: to);
}

// A route option shown to the user, with every reason it was picked —
// one itinerary can be e.g. both the fastest and the easiest.
class _RouteChoice {
  final List<String> kinds; // 'fastest' | 'easiest' | 'shortest'
  final _TransitOption option;
  _RouteChoice(this.kinds, this.option);
}

// Walking is drawn in the light text colour so it never reads as part of a
// (teal) bus ride.
const _walkColor = AppPalette.textPrimary;

// Radius (m) used for "bus stops near you" — matches getNearbyStops' default.
const _nearbyRadius = 500;

const _popularLocations = [
  _LocationResult(shortName: '逢甲大學', shortNameEn: 'Feng Chia University', displayName: '台中市西屯區逢甲大學', lat: 24.1800, lon: 120.6445),
  _LocationResult(shortName: '台中火車站', shortNameEn: 'Taichung Train Station', displayName: '台中市中區台中火車站', lat: 24.1369, lon: 120.6852),
  _LocationResult(shortName: '台中市政府', shortNameEn: 'Taichung City Hall', displayName: '台中市西屯區市政北二路', lat: 24.1634, lon: 120.6469),
  _LocationResult(shortName: '國立中興大學', shortNameEn: 'Nat\'l Chung Hsing University (NCHU)', displayName: '台中市南區興大路145號', lat: 24.1170, lon: 120.6752),
  _LocationResult(shortName: '台中榮總', shortNameEn: 'Taichung Veterans General Hospital', displayName: '台中市西屯區台灣大道四段1650號', lat: 24.1731, lon: 120.6362),
  _LocationResult(shortName: '朝馬轉運站', shortNameEn: 'Chaoma Bus Terminal', displayName: '台中市西屯區朝馬三路', lat: 24.1548, lon: 120.6245),
  _LocationResult(shortName: '高鐵台中站', shortNameEn: 'Taichung HSR Station', displayName: '台中市烏日區站區二路', lat: 24.0626, lon: 120.6854),
  _LocationResult(shortName: '台中機場', shortNameEn: 'Taichung Airport', displayName: '台中市清水區鎮南路', lat: 24.2641, lon: 120.6208),
  _LocationResult(shortName: '一中商圈', shortNameEn: 'First High School Shopping Area', displayName: '台中市北區育才街一帶', lat: 24.1534, lon: 120.6869),
  _LocationResult(shortName: '中友百貨', shortNameEn: 'Chung Yu Department Store', displayName: '台中市中區三民路三段', lat: 24.1456, lon: 120.6819),
  _LocationResult(shortName: '台中國家歌劇院', shortNameEn: 'National Taichung Theater', displayName: '台中市西屯區惠來路二段101號', lat: 24.1630, lon: 120.6447),
  _LocationResult(shortName: '新光三越台中中港', shortNameEn: 'Shin Kong Mitsukoshi Taichung', displayName: '台中市西屯區台灣大道三段301號', lat: 24.1634, lon: 120.6469),
  _LocationResult(shortName: '大里市區', shortNameEn: 'Dali District', displayName: '台中市大里區', lat: 24.0999, lon: 120.6784),
  _LocationResult(shortName: '豐原火車站', shortNameEn: 'Fengyuan Train Station', displayName: '台中市豐原區圓環南路', lat: 24.2519, lon: 120.7188),
  _LocationResult(shortName: '東海大學', shortNameEn: 'Tunghai University', displayName: '台中市龍井區台灣大道四段1727號', lat: 24.1792, lon: 120.5993),
];

const _aliases = <String, String>{
  // Feng Chia University — covers romanised, phonetic Mandarin, and abbreviation
  'fengchia': '逢甲大學', 'feng chia': '逢甲大學', 'fengjia': '逢甲大學',
  'feng jia': '逢甲大學', 'fcu': '逢甲大學', 'feng chia university': '逢甲大學',

  // Taichung Train Station
  'taichung station': '台中火車站', 'train station': '台中火車站',
  'taichung railway': '台中火車站', 'taichung train': '台中火車站',
  'huo che zhan': '台中火車站',

  // City Hall
  'city hall': '台中市政府', 'taichung city hall': '台中市政府',

  // NCHU — covers full English name and common abbreviations
  'nchu': '國立中興大學', 'chung hsing': '國立中興大學',
  'national chung hsing': '國立中興大學',
  'chung hsing university': '國立中興大學',
  'zhong xing': '國立中興大學', 'zhongxing': '國立中興大學',

  // THSR
  'thsr': '高鐵台中站', 'hsr': '高鐵台中站', 'high speed': '高鐵台中站',
  'taichung hsr': '高鐵台中站', 'gaotie': '高鐵台中站',

  // Tunghai University
  'tunghai': '東海大學', 'dong hai': '東海大學',
  'tunghai university': '東海大學', 'thu': '東海大學',

  // Airport
  'airport': '台中機場', 'taichung airport': '台中機場',

  // Veterans General Hospital
  'veterans': '台中榮總', 'taichung veterans': '台中榮總', 'vghtc': '台中榮總',
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

  // Try progressively: Chinese name in Taiwan → original query in Taiwan → original query
  final queries = [
    if (searchQuery != q) '$searchQuery 台中',
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
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      if (data.isNotEmpty) {
        // Prefer amenity/education results over roads or postcodes
        final sorted = List<Map<String, dynamic>>.from(
          data.map((e) => e as Map<String, dynamic>),
        )..sort((a, b) {
            const preferred = {'amenity', 'tourism', 'building', 'landuse'};
            final aScore = preferred.contains(a['class']) ? 0 : 1;
            final bScore = preferred.contains(b['class']) ? 0 : 1;
            if (aScore != bScore) return aScore.compareTo(bScore);
            // Same class tier — prefer whichever branch is closer to the user,
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

// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  // ─── Voice User Interface (VUI) ─────────────────────────────────────────
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _voiceText = '';
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  LatLng? _userLocation;
  bool _locationGranted = false;
  StreamSubscription<Position>? _positionSub;
  String? _selectedRoute;

  List<_LocationResult> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _showSuggestions = false;

  Timer? _debounce;

  // Directions state
  _LocationResult? _selectedDestination;
  List<_RouteSegment> _directionsSegments = [];
  String? _directionsEta;
  String? _directionsDistance;
  bool _fetchingDirections = false;
  String? _transportMode; // 'bus' | 'walk' | 'car' | null = no route
  List<String> _busLines = [];
  String? _walkHint;

  // Bus route options for the current destination. From all itineraries
  // Google returns we pick the fastest (least time), the easiest (fewest
  // transfers, then least walking) and the shortest (least distance).
  // Several can be the same itinerary, so they are merged into choices.
  List<_RouteChoice> _routeChoices = [];
  int _selectedChoice = 0;

  // Trips the user has made on 2+ days from around here — suggested first,
  // and the top one is offered automatically in a banner.
  List<_LocationResult> _frequentTrips = [];
  bool _usualTripDismissed = false;

  // ─── Sheet / route-detail state ───────────────────────────────────────────
  final _sheetController = DraggableScrollableController();
  final _busSearchController = TextEditingController();
  String _busSearchQuery = '';
  // Waits for the user to stop typing so "52" doesn't also search "5"
  Timer? _busSearchDebounce;
  int _sheetTab = 0; // 0 = nearby, 1 = search
  bool _inRouteDetail = false;
  int? _selectedDirection; // 0 = outbound 去程, 1 = inbound 回程
  String? _userStopUID; // stop the user tapped from — highlighted in route detail

  // Current fractional height (0..1) of the draggable sheet — used to keep
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

  // Small dot icon for route stop markers (the default Google pin is too big
  // when a route has dozens of stops). Null until generated.
  BitmapDescriptor? _stopDotIcon;
  BitmapDescriptor? _nearbyDotIcon; // green dot for stops around the user

  // Walking legs are drawn as alternating left / right footprints, bus rides
  // as a solid line with a route-number badge where you board.
  BitmapDescriptor? _footLeftIcon;
  BitmapDescriptor? _footRightIcon;
  final Map<String, BitmapDescriptor> _busBadgeIcons = {};

  // Footprint spacing follows the zoom so the trail keeps the same look on
  // screen. Only redrawn once the zoom settles on a new half-step.
  double _cameraZoom = 14;
  double _footprintZoom = 14;

  @override
  void initState() {
    super.initState();
    // Route search runs on a locally cached route list — warm it up now
    PtxApi.instance.prefetchRoutes(defaultCity);
    final locationReady = _requestLocation();
    _restoreSession(locationReady);
    _createStopDotIcon(14).then((icon) {
      if (mounted) setState(() => _stopDotIcon = icon);
    });
    _createStopDotIcon(12, color: AppPalette.textSecondary).then((icon) {
      if (mounted) setState(() => _nearbyDotIcon = icon);
    });
    Future.wait([
      _createFootprintIcon(left: true),
      _createFootprintIcon(left: false),
    ]).then((icons) {
      if (!mounted) return;
      setState(() {
        _footLeftIcon = icons[0];
        _footRightIcon = icons[1];
      });
    });
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && _searchController.text.isEmpty) {
        setState(() {
          _suggestions = _defaultSuggestions();
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
    _initSpeech();
    _loadFrequentTrips();
  }

  // ─── Crash recovery: remember / restore what the user is doing ───────────

  // Called every build so the snapshot is always current if a crash happens.
  void _saveSession() {
    final dest = _selectedDestination;
    CrashRecovery.session
      ..['dest'] = dest == null
          ? null
          : {
              'name': dest.shortName,
              'nameEn': dest.shortNameEn,
              'displayName': dest.displayName,
              'lat': dest.lat,
              'lon': dest.lon,
            }
      ..['route'] = _inRouteDetail && _selectedRoute != null
          ? {
              'name': _selectedRoute,
              'dir': _selectedDirection ?? 0,
              'userStop': _userStopUID,
            }
          : null
      ..['sheetTab'] = _sheetTab
      ..['busQuery'] = _busSearchQuery;
  }

  // After an automatic crash restart, put the user back where they were:
  // same sheet tab and bus search, same open route, same destination.
  void _restoreSession(Future<void> locationReady) {
    final dest = CrashRecovery.takeRestored('dest') as Map<String, Object?>?;
    final route = CrashRecovery.takeRestored('route') as Map<String, Object?>?;
    final tab = CrashRecovery.takeRestored('sheetTab') as int?;
    final query = CrashRecovery.takeRestored('busQuery') as String?;
    if (dest == null && route == null && tab == null && query == null) return;

    if (tab != null) _sheetTab = tab;
    if (query != null && query.isNotEmpty) {
      _busSearchQuery = query;
      _busSearchController.text = query;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (route != null) {
        _enterRouteDetail(route['name'] as String, route['dir'] as int,
            userStopUID: route['userStop'] as String?);
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(AppStrings.t(_lang, 'restoredAfterCrash')),
        duration: const Duration(seconds: 3),
      ));
    });
    if (dest != null) {
      // Wait for GPS so directions start from the user's real position
      locationReady.whenComplete(() {
        if (!mounted) return;
        _selectSuggestion(
          _LocationResult(
            shortName: dest['name'] as String,
            shortNameEn: dest['nameEn'] as String,
            displayName: dest['displayName'] as String,
            lat: dest['lat'] as double,
            lon: dest['lon'] as double,
          ),
          record: false,
        );
      });
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && _isListening) {
          _stopListening();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  void _onSheetExtentChanged() {
    if (!_sheetController.isAttached) return;
    setState(() => _sheetExtent = _sheetController.size);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _debounce?.cancel();
    _busSearchDebounce?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _busSearchController.dispose();
    _sheetController.removeListener(_onSheetExtentChanged);
    _sheetController.dispose();
    _pulseController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  // ─── Voice User Interface (VUI) ──────────────────────────────────────────

  Future<void> _speak(String text) async {
    await _tts.setLanguage(_lang == AppLanguage.zh ? 'zh-TW' : 'en-US');
    await _tts.speak(text);
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize();
      if (!_speechAvailable) {
        if (mounted) _speak(AppStrings.t(_lang, 'voiceUnavailable'));
        return;
      }
    }
    setState(() {
      _isListening = true;
      _voiceText = '';
    });
    await _speech.listen(
      onResult: (result) {
        if (mounted) setState(() => _voiceText = result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: _lang == AppLanguage.zh ? 'zh_TW' : 'en_US',
      ),
    );
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
    final text = _voiceText.trim();
    if (text.isNotEmpty) _processVoiceCommand(text);
  }

  Future<void> _processVoiceCommand(String text) async {
    final lower = text.toLowerCase();

    // ── "nearby buses" intent ──────────────────────────────────────────
    const nearbyKeywords = [
      'nearby', 'near me', 'buses near', 'close by',
      '附近', '周邊', '附近站牌', '附近公車',
    ];
    if (nearbyKeywords.any((k) => lower.contains(k))) {
      if (_inRouteDetail) _exitRouteDetail();
      setState(() => _sheetTab = 0);
      _sheetController.animateTo(0.38,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      _speak(AppStrings.t(_lang, 'voiceShowingNearby'));
      return;
    }

    // ── Route number intent (e.g. "route 52", "52", "公車 52") ──────────
    final routeMatch = RegExp(r'\b\d{1,3}\b').firstMatch(text);
    if (routeMatch != null) {
      final routeNum = routeMatch.group(0)!;
      try {
        final routes = await PtxApi.instance.searchRoutes(routeNum, defaultCity);
        final exact = routes.where(
          (r) => r.routeName.zhTw == routeNum || r.routeName.en == routeNum,
        );
        final route =
            exact.isNotEmpty ? exact.first : (routes.isNotEmpty ? routes.first : null);
        if (route != null) {
          _speak(AppStrings.voiceOpeningRoute(_lang, route.routeName.forLang(_lang)));
          if (mounted) {
            Navigator.pushNamed(context, '/route_detail', arguments: {
              'routeName': route.routeName.zhTw,
              'routeUID': route.routeUID,
            });
          }
          return;
        }
      } catch (_) {
        // Fall through to location matching below
      }
    }

    // ── Location / destination intent ────────────────────────────────────
    final popularMatch = _filterPopular(text);
    if (popularMatch.isNotEmpty) {
      _speak(AppStrings.voiceFindingDirections(_lang, popularMatch.first.shortName));
      _selectSuggestion(popularMatch.first);
      return;
    }

    final nomResults = await _nominatimSearch(text, _userLocation ?? _defaultCenter);
    if (nomResults.isNotEmpty && mounted) {
      _speak(AppStrings.voiceFindingDirections(_lang, nomResults.first.shortName));
      _selectSuggestion(nomResults.first);
      return;
    }

    _speak(AppStrings.t(_lang, 'voiceNotUnderstood'));
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
        _loadFrequentTrips();
      }
      _watchLocation();
    } catch (_) {}
  }

  // Keep _userLocation current as the user moves. The 100 m filter keeps
  // nearbyStopsProvider (keyed on lat/lon) from refetching TDX on GPS jitter.
  void _watchLocation() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
      }
    }, onError: (_) {});
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();

    if (q.isEmpty) {
      setState(() {
        _suggestions = _defaultSuggestions();
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

  // Remembered frequent trips first, then popular places (no duplicates).
  List<_LocationResult> _defaultSuggestions() {
    final popular = _popularLocations.where((p) => !_frequentTrips.any((t) =>
        haversineDistance(t.lat, t.lon, p.lat, p.lon) < 200));
    return [..._frequentTrips.take(3), ...popular].take(6).toList();
  }

  Future<void> _loadFrequentTrips() async {
    final origin = _userLocation;
    final trips = await TripHistory.instance.frequentTrips(
        originLat: origin?.latitude, originLon: origin?.longitude);
    if (!mounted) return;
    setState(() {
      _frequentTrips = trips
          .map((t) => _LocationResult(
                shortName: t.name,
                shortNameEn: t.nameEn,
                displayName: t.displayName,
                lat: t.lat,
                lon: t.lon,
                tripDays: t.dayCount,
              ))
          .toList();
      // Refresh the open suggestion list if it is showing the defaults
      if (_showSuggestions && _searchController.text.isEmpty) {
        _suggestions = _defaultSuggestions();
      }
    });
  }

  void _selectSuggestion(_LocationResult result, {bool record = true}) {
    _searchController.text = result.shortName;
    _debounce?.cancel();
    _searchFocus.unfocus();
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
      _loadingSuggestions = false;
      _selectedDestination = result;
      _directionsSegments = [];
      _directionsEta = null;
      _directionsDistance = null;
      _fetchingDirections = true;
    });
    // Move camera to destination immediately, then re-fit after route loads
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(result.lat, result.lon), 15),
    );
    _fetchDirections(result);
    if (!record) return;
    TripHistory.instance
        .record(
          name: result.shortName,
          nameEn: result.shortNameEn,
          displayName: result.displayName,
          lat: result.lat,
          lon: result.lon,
          originLat: _userLocation?.latitude,
          originLon: _userLocation?.longitude,
        )
        .then((_) => _loadFrequentTrips())
        .catchError((_) {});
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _suggestions = _defaultSuggestions();
      _showSuggestions = false;
      _loadingSuggestions = false;
    });
    _clearDirections();
  }

  // ─── Route detail ─────────────────────────────────────────────────────────

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

  // [routeName] is the public route number (e.g. "351"), which the TDX
  // endpoints are keyed on — NOT RouteID, which differs for some routes
  // (351 → "3510", 352延 → "3521").
  void _enterRouteDetail(String routeName, int direction,
      {String? userStopUID}) {
    setState(() {
      _selectedRoute = routeName;
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

  // ─── Directions API ───────────────────────────────────────────────────────

  void _clearDirections() {
    setState(() {
      _selectedDestination = null;
      _directionsSegments = [];
      _directionsEta = null;
      _directionsDistance = null;
      _fetchingDirections = false;
      _transportMode = null;
      _busLines = [];
      _walkHint = null;
      _routeChoices = [];
      _selectedChoice = 0;
    });
  }

  // Shared helper — asks Google for bus (transit) itineraries from [from] to
  // [to], including alternatives with transfers. Returns an empty list on
  // failure / no route.
  Future<List<_TransitOption>> _tryTransit(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json',
      ).replace(queryParameters: {
        'origin': '${from.latitude},${from.longitude}',
        'destination': '${to.latitude},${to.longitude}',
        'mode': 'transit',
        'transit_mode': 'bus',
        'alternatives': 'true',
        'language': 'zh-TW',
        'key': _googleMapsApiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] != 'OK') return [];
      final options = <_TransitOption>[];
      for (final route in data['routes'] as List<dynamic>) {
        try {
          final leg = ((route as Map)['legs'] as List<dynamic>)[0]
              as Map<String, dynamic>;
          final duration = leg['duration'] as Map<String, dynamic>;
          final distance = leg['distance'] as Map<String, dynamic>;
          // Extract bus line numbers (in riding order), rides and walking
          final busLines = <String>[];
          int rides = 0;
          int walkMeters = 0;
          for (final step in leg['steps'] as List<dynamic>) {
            final s = step as Map<String, dynamic>;
            if (s['travel_mode'] == 'WALKING') {
              walkMeters +=
                  ((s['distance'] as Map?)?['value'] as num?)?.toInt() ?? 0;
            }
            if (s['travel_mode'] == 'TRANSIT') {
              rides++;
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
          options.add(_TransitOption(
            eta: duration['text'] as String,
            dist: distance['text'] as String,
            durationSecs: (duration['value'] as num).toInt(),
            distanceMeters: (distance['value'] as num).toInt(),
            transfers: rides > 1 ? rides - 1 : 0,
            walkMeters: walkMeters,
            segments: _extractSegments(leg),
            busLines: busLines,
          ));
        } catch (_) {
          // Skip a malformed alternative, keep the others
        }
      }
      return options;
    } catch (_) {
      return [];
    }
  }

  // Picks the fastest, easiest and shortest itineraries and shows the
  // fastest one first.
  void _setTransitOptions(List<_TransitOption> options, {String? walkHint}) {
    final fastest = options.reduce(
        (a, b) => b.durationSecs < a.durationSecs ? b : a);
    // Most convenient: fewest bus changes, then least walking, then quickest
    int convenience(_TransitOption a, _TransitOption b) {
      if (a.transfers != b.transfers) return a.transfers.compareTo(b.transfers);
      if (a.walkMeters != b.walkMeters) {
        return a.walkMeters.compareTo(b.walkMeters);
      }
      return a.durationSecs.compareTo(b.durationSecs);
    }
    final easiest = options.reduce((a, b) => convenience(b, a) < 0 ? b : a);
    final shortest = options.reduce((a, b) =>
        b.distanceMeters < a.distanceMeters ||
                (b.distanceMeters == a.distanceMeters &&
                    b.durationSecs < a.durationSecs)
            ? b
            : a);

    final choices = <_RouteChoice>[];
    void add(String kind, _TransitOption option) {
      for (final c in choices) {
        if (identical(c.option, option)) {
          c.kinds.add(kind);
          return;
        }
      }
      choices.add(_RouteChoice([kind], option));
    }
    add('fastest', fastest);
    add('easiest', easiest);
    add('shortest', shortest);

    setState(() {
      _routeChoices = choices;
      _selectedChoice = 0;
      _fetchingDirections = false;
      _transportMode = 'bus';
      _walkHint = walkHint;
      _applyTransitOption(fastest);
    });
    _snapBusSegmentsToRoads(options);
  }

  // Must be called inside setState.
  void _applyTransitOption(_TransitOption option) {
    _directionsEta = option.eta;
    _directionsDistance = option.dist;
    _directionsSegments = option.segments;
    for (final seg in option.segments) {
      if (seg.line != null) _ensureBusBadge(seg.line!);
    }
    _busLines = option.busLines;
  }

  void _chooseRouteOption(int index) {
    if (index == _selectedChoice || index >= _routeChoices.length) return;
    setState(() {
      _selectedChoice = index;
      _applyTransitOption(_routeChoices[index].option);
    });
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
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
      _routeChoices = [];
      _selectedChoice = 0;
    });

    final dest = LatLng(destination.lat, destination.lon);
    final origin = _userLocation ?? _defaultCenter;

    // ── Step 1: direct transit to destination ────────────────────────────────
    final direct = await _tryTransit(origin, dest);
    if (direct.isNotEmpty && mounted) {
      _setTransitOptions(direct);
      final allPoints = direct.expand((o) => o.points);
      if (allPoints.isNotEmpty) {
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
            _latLngBounds([origin, dest, ...allPoints]), 72));
      }
      return;
    }

    // ── Step 2: no direct bus — find stops near destination, walk the last bit
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
        if (partial.isEmpty) continue;

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

        // Draw the last stretch on foot from the stop to the destination
        final lastWalk = await _tryWalking(stopLatLng, dest) ??
            [stopLatLng, dest];
        for (final option in partial) {
          option.segments.add(_RouteSegment(_SegMode.walk, lastWalk));
        }

        if (mounted) {
          _setTransitOptions(partial, walkHint: hint);
          // Fix: include actual dest in bounds so the pin is always visible
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
              _latLngBounds([origin, dest, stopLatLng,
                  ...partial.expand((o) => o.points)]), 72));
        }
        return;
      }
    } catch (_) {}

    // ── Step 3: close enough to walk? (≤ 1.5 km straight-line) ─────────────
    final straightLine = haversineDistance(
        origin.latitude, origin.longitude, dest.latitude, dest.longitude);
    if (straightLine <= 1500 && mounted) {
      final walkPath = await _tryWalking(origin, dest);
      if (!mounted) return;
      final walkMins = (straightLine / 75).ceil();
      final distLabel = straightLine < 1000
          ? '${straightLine.toStringAsFixed(0)} m'
          : '${(straightLine / 1000).toStringAsFixed(1)} km';
      setState(() {
        _directionsEta = AppStrings.approxMinsLabel(_lang, walkMins);
        _directionsDistance = distLabel;
        _directionsSegments = [
          _RouteSegment(_SegMode.walk, walkPath ?? [origin, dest]),
        ];
        _fetchingDirections = false;
        _transportMode = 'walk';
        _busLines = [];
        _walkHint = null;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
          _latLngBounds([origin, dest, ...?walkPath]), 72));
      return;
    }

    // ── Step 4: fall back to driving directions ──────────────────────────────
    final car = await _tryDriving(origin, dest);
    if (car != null && mounted) {
      setState(() {
        _directionsEta = car.eta;
        _directionsDistance = car.dist;
        _directionsSegments = [_RouteSegment(_SegMode.car, car.points)];
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

    // ── No route found at all ────────────────────────────────────────────────
    if (mounted) {
      setState(() {
        _fetchingDirections = false;
        _transportMode = null;
        _directionsSegments = [];
        _directionsEta = null;
        _directionsDistance = null;
        _busLines = [];
        _walkHint = null;
      });
    }
  }

  // Splits a transit leg into walk / bus segments in travel order.
  List<_RouteSegment> _extractSegments(Map<String, dynamic> leg) {
    final segments = <_RouteSegment>[];
    for (final step in leg['steps'] as List<dynamic>) {
      final s = step as Map<String, dynamic>;
      final mode = s['travel_mode'];
      if (mode == 'TRANSIT') {
        final td = s['transit_details'] as Map<String, dynamic>?;
        final line = td?['line'] as Map<String, dynamic>?;
        LatLng? stopAt(String key) {
          final loc = (td?[key] as Map<String, dynamic>?)?['location']
              as Map<String, dynamic>?;
          if (loc == null) return null;
          return LatLng(
              (loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        }

        segments.add(_RouteSegment(
          _SegMode.bus,
          _decodeStepPolyline(s),
          line: (line?['short_name'] ?? line?['name']) as String?,
          from: stopAt('departure_stop'),
          to: stopAt('arrival_stop'),
        ));
      } else {
        // A walking step's own polyline is a summary; its turn-by-turn
        // sub-steps carry the full path along the streets.
        final subSteps = s['steps'] as List<dynamic>?;
        final points = subSteps != null && subSteps.isNotEmpty
            ? _joinPaths(subSteps
                .map((sub) => _decodeStepPolyline(sub as Map<String, dynamic>)))
            : _decodeStepPolyline(s);
        segments.add(_RouteSegment(
            mode == 'WALKING' ? _SegMode.walk : _SegMode.car, points));
      }
    }
    return segments.where((seg) => seg.points.length >= 2).toList();
  }

  List<LatLng> _decodeStepPolyline(Map<String, dynamic> step) {
    final encoded =
        (step['polyline'] as Map<String, dynamic>?)?['points'] as String?;
    return encoded == null ? [] : _decodePolyline(encoded);
  }

  List<LatLng> _joinPaths(Iterable<List<LatLng>> paths) {
    final points = <LatLng>[];
    for (final path in paths) {
      if (points.isNotEmpty && path.isNotEmpty && points.last == path.first) {
        points.addAll(path.skip(1));
      } else {
        points.addAll(path);
      }
    }
    return points;
  }

  Future<List<LatLng>?> _tryWalking(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json',
      ).replace(queryParameters: {
        'origin': '${from.latitude},${from.longitude}',
        'destination': '${to.latitude},${to.longitude}',
        'mode': 'walking',
        'key': _googleMapsApiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) return null;
      final leg = ((routes[0] as Map)['legs'] as List<dynamic>)[0]
          as Map<String, dynamic>;
      final points = _extractDetailedPolyline(leg);
      return points.length >= 2 ? points : null;
    } catch (_) {
      return null;
    }
  }

  // ─── Snapping bus rides to the road ───────────────────────────────────────
  //
  // For many Taiwan bus lines Google has no route geometry, so its transit
  // polyline just joins stop to stop and cuts every corner. TDX publishes the
  // real road path of each route (Bus/Shape); we cut out the part between the
  // boarding and alighting stops and draw that instead. Any ride that can't
  // be matched confidently keeps Google's line.

  Future<void> _snapBusSegmentsToRoads(List<_TransitOption> options) async {
    final shapesByLine = <String, List<BusShape>>{};
    var changed = false;
    for (final option in options) {
      for (var i = 0; i < option.segments.length; i++) {
        final seg = option.segments[i];
        if (seg.mode != _SegMode.bus ||
            seg.line == null ||
            seg.from == null ||
            seg.to == null) {
          continue;
        }
        var shapes = shapesByLine[seg.line!];
        if (shapes == null) {
          try {
            shapes =
                await PtxApi.instance.getRouteShapes(seg.line!, defaultCity);
          } catch (_) {
            shapes = const [];
          }
          shapesByLine[seg.line!] = shapes;
        }
        final snapped = _sliceShape(shapes, seg.from!, seg.to!, seg.points);
        if (snapped != null) {
          option.segments[i] = seg.withPoints(snapped);
          changed = true;
        }
      }
    }
    if (!changed || !mounted || _routeChoices.isEmpty) return;
    // Redraw only if one of these options is still the one on screen
    final current = _routeChoices[_selectedChoice].option;
    if (options.any((o) => identical(o, current))) {
      setState(() => _applyTransitOption(current));
    }
  }

  // The stretch of a route shape from [from] to [to], or null when no shape
  // passes close to both stops in that order with a plausible length.
  List<LatLng>? _sliceShape(List<BusShape> shapes, LatLng from, LatLng to,
      List<LatLng> googlePoints) {
    const maxStopOffset = 80.0; // m — stops sit on the kerb, not the centreline
    final googleLength = _pathLength(googlePoints);
    List<LatLng>? best;
    var bestError = double.infinity;
    for (final shape in shapes) {
      final pts = shape.points.map((p) => LatLng(p.lat, p.lon)).toList();
      final a = _projectOnPath(pts, from, 0);
      if (a == null || a.dist > maxStopOffset) continue;
      // Alighting must come after boarding along the route
      final b = _projectOnPath(pts, to, a.pos);
      if (b == null || b.dist > maxStopOffset) continue;
      final slice = [
        a.point,
        ...pts.sublist(a.index + 1, b.index + 1),
        b.point
      ];
      // Guards against the wrong direction or a loop matched the long way round
      final length = _pathLength(slice);
      if (googleLength > 0 &&
          (length > googleLength * 1.6 || length < googleLength * 0.6)) {
        continue;
      }
      final error = a.dist + b.dist;
      if (error < bestError) {
        bestError = error;
        best = slice;
      }
    }
    return best;
  }

  // Closest point on [path] to [p], searching only at or after position
  // [minPos] (segment index + fraction along it). Distances in metres.
  ({int index, double pos, LatLng point, double dist})? _projectOnPath(
      List<LatLng> path, LatLng p, double minPos) {
    final cosLat = math.cos(p.latitude * math.pi / 180);
    const mPerDeg = 111320.0;
    ({int index, double pos, LatLng point, double dist})? best;
    for (var i = minPos.floor(); i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      // Local flat coordinates (metres) relative to p
      final ax = (a.longitude - p.longitude) * cosLat * mPerDeg;
      final ay = (a.latitude - p.latitude) * mPerDeg;
      final bx = (b.longitude - p.longitude) * cosLat * mPerDeg;
      final by = (b.latitude - p.latitude) * mPerDeg;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      if (i == minPos.floor()) t = math.max(t, minPos - i);
      final cx = ax + dx * t, cy = ay + dy * t;
      final dist = math.sqrt(cx * cx + cy * cy);
      if (best == null || dist < best.dist) {
        best = (
          index: i,
          pos: i + t,
          point: LatLng(a.latitude + (b.latitude - a.latitude) * t,
              a.longitude + (b.longitude - a.longitude) * t),
          dist: dist,
        );
      }
    }
    return best;
  }

  double _pathLength(List<LatLng> path) {
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      total += haversineDistance(path[i].latitude, path[i].longitude,
          path[i + 1].latitude, path[i + 1].longitude);
    }
    return total;
  }

  // Concatenates each step's own polyline instead of using overview_polyline,
  // which Google deliberately simplifies for small-scale display and cuts
  // corners at turns. Per-step polylines follow the actual road geometry.
  List<LatLng> _extractDetailedPolyline(Map<String, dynamic> leg) =>
      _joinPaths((leg['steps'] as List<dynamic>)
          .map((step) => _decodeStepPolyline(step as Map<String, dynamic>)));

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

  // ─── Build Google Maps marker set ─────────────────────────────────────────

  // Nearby stops are shown on the map only on the plain home view.
  bool get _showNearbyOnMap => !_inRouteDetail && _selectedDestination == null;

  Set<Marker> _buildMarkers(
    List<BusRealTime> buses,
    List<RouteStop> routeStops,
    List<NearbyStop> nearbyStations,
  ) {
    final markers = <Marker>{};

    // Bus stops around the user (one marker per real stop)
    if (_showNearbyOnMap && _nearbyDotIcon != null) {
      for (final ns in nearbyStations) {
        markers.add(Marker(
          markerId: MarkerId('nearby_${ns.stop.stopName.zhTw}'),
          position: LatLng(ns.stop.stopPosition.lat, ns.stop.stopPosition.lon),
          icon: _nearbyDotIcon!,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: ns.stop.stopName.forLang(_lang),
            snippet: '${ns.distance.round()} m',
          ),
          zIndexInt: 0,
        ));
      }
    }

    // Live bus position markers — filtered by direction when in route detail
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

    // Route stop markers — show only selected direction, hidden while destination active
    if (_selectedDestination == null && _selectedDirection != null) {
      for (final stop in routeStops) {
        if (stop.direction != _selectedDirection) continue;
        markers.add(Marker(
          markerId: MarkerId('rstop_${stop.stopUID}'),
          position: LatLng(stop.stopPosition.lat, stop.stopPosition.lon),
          icon: _stopDotIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          // Centre the dot on the stop (default anchor is the pin's tip)
          anchor: _stopDotIcon != null
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: stop.stopName.forLang(_lang),
            snippet:
                '${AppStrings.route(_lang, _selectedRoute ?? '')}  •  ${AppStrings.stopFallbackLabel(_lang, stop.stopSequence)}',
          ),
          onTap: () => _showStopOptions(stop),
          zIndexInt: 1,
        ));
      }
    }

    // Footprint trails along walking legs, a badge where each bus is boarded
    if (_selectedDestination != null) {
      for (var i = 0; i < _directionsSegments.length; i++) {
        final seg = _directionsSegments[i];
        if (seg.mode == _SegMode.walk) {
          markers.addAll(_footprintMarkers(seg.points, 'walk$i'));
        } else if (seg.mode == _SegMode.bus && seg.line != null) {
          final badge = _busBadgeIcons[seg.line!];
          if (badge == null) continue;
          markers.add(Marker(
            markerId: MarkerId('board_$i'),
            position: seg.points.first,
            icon: badge,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 5,
            consumeTapEvents: true,
          ));
        }
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

  // ─── Build route polylines ─────────────────────────────────────────────────

  Set<Polyline> _buildPolylines(
      List<RouteStop> stops, List<BusShape> shapes) {
    final polylines = <Polyline>{};

    // TDX bus route polyline — only the selected direction when in route detail
    if (stops.isNotEmpty && _selectedDirection != null) {
      final dirStops = stops
          .where((s) => s.direction == _selectedDirection)
          .toList()
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

      // Follow the road shape when TDX has one; else join the stops
      final shape = _shapeForDirection(shapes, _selectedDirection!);
      final points = shape != null
          ? shape.points.map((p) => LatLng(p.lat, p.lon)).toList()
          : dirStops
              .map((s) => LatLng(s.stopPosition.lat, s.stopPosition.lon))
              .toList();
      if (points.length >= 2) {
        polylines.addAll(_busLine('route_selected', points));
      }
    }

    // Directions route, styled per leg
    for (var i = 0; i < _directionsSegments.length; i++) {
      final seg = _directionsSegments[i];
      switch (seg.mode) {
        case _SegMode.bus:
          polylines.addAll(_busLine('dir_$i', seg.points));
        case _SegMode.car:
          polylines.add(Polyline(
            polylineId: PolylineId('dir_$i'),
            points: seg.points,
            color: AppColors.yellow,
            width: 5,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ));
        case _SegMode.walk:
          // Faint guide under the footprints so the path still reads when
          // zoomed far out and the prints thin out
          polylines.add(Polyline(
            polylineId: PolylineId('dir_$i'),
            points: seg.points,
            color: _walkColor.withValues(alpha: 0.28),
            width: 2,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ));
      }
    }

    return polylines;
  }

  // A bus ride: the accent line on a dark casing, so it stands out from both
  // the map and the thin walking guide.
  List<Polyline> _busLine(String id, List<LatLng> points) => [
        Polyline(
          polylineId: PolylineId('${id}_casing'),
          points: points,
          color: AppPalette.onAccent,
          width: 9,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ),
        Polyline(
          polylineId: PolylineId(id),
          points: points,
          color: AppColors.green,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 2,
        ),
      ];

  BusShape? _shapeForDirection(List<BusShape> shapes, int direction) {
    for (final shape in shapes) {
      if (shape.direction == direction) return shape;
    }
    // A single undivided shape (e.g. a loop route) serves both directions
    if (shapes.length == 1 && shapes.first.direction == null) {
      return shapes.first;
    }
    return null;
  }

  // Footprints every ~16 dp along [path], each turned to face the way of
  // travel and alternating left / right foot.
  List<Marker> _footprintMarkers(List<LatLng> path, String id) {
    if (_footLeftIcon == null || _footRightIcon == null || path.length < 2) {
      return const [];
    }
    final metresPerDp = 156543.03392 *
        math.cos(path.first.latitude * math.pi / 180) /
        math.pow(2, _footprintZoom);
    final length = _pathLength(path);
    // Cap the count so a long walk seen zoomed out stays light on markers
    final spacing = math.max(metresPerDp * 16, length / 250);

    final markers = <Marker>[];
    var nextAt = spacing / 2; // distance along the path of the next print
    var travelled = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      final segLength =
          haversineDistance(a.latitude, a.longitude, b.latitude, b.longitude);
      if (segLength == 0) continue;
      final bearing = _bearing(a, b);
      while (nextAt <= travelled + segLength) {
        final t = (nextAt - travelled) / segLength;
        final n = markers.length;
        markers.add(Marker(
          markerId: MarkerId('${id}_$n'),
          position: LatLng(a.latitude + (b.latitude - a.latitude) * t,
              a.longitude + (b.longitude - a.longitude) * t),
          icon: n.isEven ? _footLeftIcon! : _footRightIcon!,
          anchor: const Offset(0.5, 0.5),
          rotation: bearing,
          flat: true, // turns with the map so prints stay along the street
          consumeTapEvents: true,
          zIndexInt: 3,
        ));
        nextAt += spacing;
      }
      travelled += segLength;
    }
    return markers;
  }

  // Compass bearing from [a] to [b], degrees clockwise from north.
  double _bearing(LatLng a, LatLng b) {
    final dLon =
        (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180);
    final dLat = b.latitude - a.latitude;
    return (math.atan2(dLon, dLat) * 180 / math.pi + 360) % 360;
  }

  void _ensureBusBadge(String line) {
    if (_busBadgeIcons.containsKey(line)) return;
    _createBusBadgeIcon(line).then((icon) {
      if (mounted) setState(() => _busBadgeIcons[line] = icon);
    });
  }

  @override
  Widget build(BuildContext context) {
    final favourites = ref.watch(favouritesProvider);
    _lang = ref.watch(languageProvider);

    final List<BusRealTime> buses;
    final List<RouteStop> routeStops;
    final List<BusShape> routeShapes;
    if (_selectedRoute != null) {
      final routeParams = (routeName: _selectedRoute!, city: defaultCity);
      buses = ref.watch(busPositionsProvider(routeParams)).value ?? [];
      routeStops = ref.watch(routeStopsProvider(routeParams)).value ?? [];
      routeShapes = ref.watch(routeShapesProvider(routeParams)).value ?? [];
    } else {
      buses = const [];
      routeStops = const [];
      routeShapes = const [];
    }

    List<NearbyStop> sortedNearby = [];
    List<NearbyStop> nearbyStations = [];
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
      // TDX returns one record per route & side of the road at the same stop
      // (e.g. 87 records = 8 real stops), so group by stop name, keeping the
      // closest record of each, to count and show real stops.
      final seenNames = <String>{};
      nearbyStations = sortedNearby
          .where((ns) => seenNames.add(ns.stop.stopName.zhTw))
          .toList();
      if (sortedNearby.length > 6) sortedNearby = sortedNearby.sublist(0, 6);
    }

    // Aggregate live arrivals for nearby stops (up to 4 stops — covers both sides
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

    final markers = _buildMarkers(buses, routeStops, nearbyStations);
    _saveSession();
    final polylines = _buildPolylines(routeStops, routeShapes);

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Sheet sizes are fractions of THIS area's height, which shrinks when
      // the keyboard opens and excludes the bottom tab bar — so measure it
      // instead of using the full screen height, or the map's bottom edge
      // ends up far above the sheet and leaves a blank gap.
      body: LayoutBuilder(builder: (context, constraints) {
        final sheetTop = _sheetExtent * constraints.maxHeight;
        return Stack(
        children: [
          // ── Google Maps ──────────────────────────────────────────────────
          // Bottom is pinned above the sheet's current top edge (rather than
          // filling the whole Stack) so the map's platform view never
          // underlaps the sheet — see _sheetExtent doc comment above.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: sheetTop,
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
              onCameraMove: (position) => _cameraZoom = position.zoom,
              onCameraIdle: () {
                final zoom = (_cameraZoom * 2).round() / 2;
                if (zoom != _footprintZoom) {
                  setState(() => _footprintZoom = zoom);
                }
              },
              myLocationEnabled: _locationGranted,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: markers,
              polylines: polylines,
              circles: {
                if (_showNearbyOnMap && _userLocation != null)
                  Circle(
                    circleId: const CircleId('nearby_radius'),
                    center: _userLocation!,
                    radius: _nearbyRadius.toDouble(),
                    fillColor: AppColors.green.withValues(alpha: 0.06),
                    strokeColor: AppColors.green.withValues(alpha: 0.35),
                    strokeWidth: 1,
                  ),
              },
              onTap: (_) {
                _searchFocus.unfocus();
                setState(() => _showSuggestions = false);
              },
            ),
          ),

          // ── Search bar — suggestions expand inside the same panel; the
          // scan and language actions live at its right end instead of
          // floating as separate map buttons.
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpace.sm,
            left: AppSpace.md,
            right: AppSpace.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MapSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  hint: AppStrings.t(_lang, 'searchLocationHint'),
                  loading: _loadingSuggestions,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
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
                  actions: [
                    CompactIconButton(
                      icon: Icons.document_scanner_outlined,
                      tooltip: AppStrings.t(_lang, 'scanBusStopTitle'),
                      onTap: () => Navigator.pushNamed(context, '/scan'),
                    ),
                    _LangToggle(
                      lang: _lang,
                      onTap: () =>
                          ref.read(languageProvider.notifier).toggle(),
                    ),
                  ],
                  below: _showSuggestions
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: SingleChildScrollView(
                              child: _buildSuggestionsList()),
                        )
                      : null,
                ),

                // ── Usual trip banner — offered automatically when the user
                // has made a trip from around here on 2+ days ─────────────
                if (_frequentTrips.isNotEmpty &&
                    _selectedDestination == null &&
                    !_showSuggestions &&
                    !_inRouteDetail &&
                    !_usualTripDismissed) ...[
                  const SizedBox(height: AppSpace.sm),
                  MapPromptChip(
                    icon: Icons.history_rounded,
                    label: AppStrings.usualTripBanner(
                        _lang,
                        _lang == AppLanguage.en &&
                                _frequentTrips.first.shortNameEn.isNotEmpty
                            ? _frequentTrips.first.shortNameEn
                            : _frequentTrips.first.shortName),
                    actionLabel: AppStrings.t(_lang, 'viewRoutes'),
                    onTap: () => _selectSuggestion(_frequentTrips.first),
                    onDismiss: () =>
                        setState(() => _usualTripDismissed = true),
                  ),
                ],

                // ── ETA card (shown after a destination is selected) ────────
                if (_selectedDestination != null && !_showSuggestions) ...[
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: AppDecor.floatingPanel,
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
                            // ── No route found ───────────────────────────
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
                            // ── Route found ──────────────────────────────
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
                                          '$_directionsEta · $_directionsDistance',
                                          style: TextStyle(
                                              color: _transportMode == 'car'
                                                  ? AppColors.yellow
                                                  : _transportMode == 'walk'
                                                      ? AppColors.blue
                                                      : AppColors.green,
                                              fontSize: 12),
                                        ),
                                      // Transfers + walking, then the
                                      // fastest / easiest / shortest choice
                                      if (_transportMode == 'bus' &&
                                          _routeChoices.isNotEmpty) ...[
                                        Text(
                                          '${AppStrings.transfersLabel(_lang, _routeChoices[_selectedChoice].option.transfers)}'
                                          ' · ${AppStrings.walkLabel(_lang, _routeChoices[_selectedChoice].option.walkMeters)}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11),
                                        ),
                                        const SizedBox(height: 6),
                                        _buildRouteOptionChips(),
                                      ],
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

          // ── Back button (visible only in route detail) ──────────────
          if (_inRouteDetail)
            Positioned(
              bottom: sheetTop + AppSpace.md,
              left: AppSpace.md,
              child: GestureDetector(
                onTap: _exitRouteDetail,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: AppDecor.floatingPanel,
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

          // ── Draggable bottom sheet ───────────────────────────────────────
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
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.sheet)),
                  boxShadow: AppShadow.sheet,
                ),
                child: _inRouteDetail
                    ? _buildRouteDetailSheet(
                        scrollController, routeStops, buses)
                    : _buildTabSheet(scrollController, nearbyArrivals,
                        sortedNearby, nearbyStations, favourites,
                        nearbyStillLoading),
              );
            },
          ),

          // ── Voice mic button — tracks the sheet's live top edge exactly
          // like GoogleMap does, so it never sits underneath the sheet.
          // Map controls step aside when the sheet covers most of the map
          if (!_showSuggestions && _sheetExtent < 0.5)
            Positioned(
              bottom: sheetTop + AppSpace.md + 52 + AppSpace.sm,
              right: AppSpace.md + 4,
              child: MapControlButton(
                icon: Icons.my_location_rounded,
                tooltip: AppStrings.t(_lang, 'myLocation'),
                onTap: () {
                  if (_userLocation != null) {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(_userLocation!, 15),
                    );
                  }
                },
              ),
            ),
          if (_sheetExtent < 0.5 || _isListening)
          Positioned(
            bottom: sheetTop + AppSpace.md,
            right: AppSpace.md,
            child: _VoiceMicButton(
              isListening: _isListening,
              pulse: _pulseController,
              onHoldStart: _startListening,
              onHoldEnd: _stopListening,
            ),
          ),

          // ── Live transcription bubble while listening ──────────────────
          if (_isListening)
            Positioned(
              bottom: sheetTop + AppSpace.md,
              left: AppSpace.md,
              right: 52 + AppSpace.md * 2,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: AppDecor.floatingPanel,
                  child: Row(children: [
                    const Icon(Icons.graphic_eq_rounded,
                        color: AppColors.blue, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _voiceText.isEmpty
                            ? AppStrings.t(_lang, 'voiceListening')
                            : _voiceText,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      );
      }),
    );
  }

  // ─── Stop options modal ───────────────────────────────────────────────────

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
              '${AppStrings.stopFallbackLabel(_lang, stop.stopSequence)}  •  ${_selectedDirection == 0 ? AppStrings.t(_lang, 'outbound') : AppStrings.t(_lang, 'inbound')}',
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

  // ─── Sheet content builders ───────────────────────────────────────────────

  Widget _buildTabSheet(
    ScrollController sc,
    List<EstimatedArrival> nearbyArrivals,
    List<NearbyStop> sortedNearby,
    List<NearbyStop> nearbyStations,
    List<String> favourites,
    bool nearbyLoading,
  ) {
    return ListView(
      controller: sc,
      padding: EdgeInsets.only(
          bottom: AppSpace.lg + MediaQuery.of(context).padding.bottom),
      children: [
        SheetHandle(onTap: _toggleSheet),
        SheetTabs(
          labels: [
            AppStrings.t(_lang, 'nearbyTab'),
            AppStrings.t(_lang, 'routesTab'),
          ],
          selected: _sheetTab,
          onSelect: (i) => setState(() => _sheetTab = i),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(
            key: ValueKey(_sheetTab),
            child: _sheetTab == 0
                ? _buildNearbyTab(nearbyArrivals, sortedNearby,
                    nearbyStations, nearbyLoading)
                : _buildSearchTab(favourites),
          ),
        ),
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

    // Build stopUID → best ETA for selected direction
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
        SheetHandle(onTap: _toggleSheet),

        // Direction tabs — show when stops are loaded
        if (!isLoading && (outEnd.isNotEmpty || inEnd.isNotEmpty)) ...[
          SheetTabs(
            labels: [
              outEnd.isNotEmpty
                  ? AppStrings.toDestination(_lang, outEnd)
                  : AppStrings.t(_lang, 'outbound'),
              inEnd.isNotEmpty
                  ? AppStrings.toDestination(_lang, inEnd)
                  : AppStrings.t(_lang, 'inbound'),
            ],
            selected: _selectedDirection ?? 0,
            onSelect: (i) => setState(() => _selectedDirection = i),
          ),
          const SizedBox(height: AppSpace.sm),
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

            // ETA label + colour — mirrors the reference Taichung app style
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

  // Header ("8 bus stops within 500 m") + stop chips, then live arrivals.
  Widget _buildNearbyTab(
      List<EstimatedArrival> arrivals,
      List<NearbyStop> sortedNearby,
      List<NearbyStop> nearbyStations,
      bool loading) {
    final arrivalsView = _buildNearbyArrivals(arrivals, sortedNearby, loading);
    if (_userLocation == null || nearbyStations.isEmpty) return arrivalsView;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          AppStrings.nearbyStopsCount(
              _lang, nearbyStations.length, _nearbyRadius),
          icon: Icons.place_outlined,
        ),
        // Sized by its chips (no fixed height) so taller CJK text or a larger
        // system font size can't overflow it.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Row(children: [
            for (final ns in nearbyStations)
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: OptionChip(
                  label:
                      '${ns.stop.stopName.forLang(_lang)}  ${_formatMeters(ns.distance)}',
                  onTap: () {
                    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                        LatLng(ns.stop.stopPosition.lat,
                            ns.stop.stopPosition.lon),
                        17));
                    _mapController?.showMarkerInfoWindow(
                        MarkerId('nearby_${ns.stop.stopName.zhTw}'));
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.xs),
        arrivalsView,
      ],
    );
  }

  static String _formatMeters(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';

  Widget _buildNearbyArrivals(
      List<EstimatedArrival> arrivals,
      List<NearbyStop> sortedNearby,
      bool loading) {
    if (_userLocation == null) {
      return SheetMessage(
          loading: true, text: AppStrings.t(_lang, 'gettingLocation'));
    }
    if (sortedNearby.isEmpty) {
      return SheetMessage(
          icon: Icons.location_off_outlined,
          text: AppStrings.t(_lang, 'noNearbyStops'));
    }
    // First load — show spinner instead of "no buses"
    if (loading && arrivals.isEmpty) return const SheetMessage(loading: true);
    if (arrivals.isEmpty) {
      final h = DateTime.now().hour;
      final offHours = h < 6 || h >= 23;
      return SheetMessage(
        icon: offHours
            ? Icons.schedule_rounded
            : Icons.directions_bus_outlined,
        text: AppStrings.t(
            _lang, offHours ? 'busServiceInactiveShort' : 'noBusesArrivingSoon'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(AppStrings.t(_lang, 'arrivingSoonHeader')),
        for (var i = 0; i < arrivals.length; i++)
          _buildArrivalCard(arrivals[i],
              divider: i < arrivals.length - 1),
      ],
    );
  }

  // One live arrival: route · stop and direction · countdown.
  Widget _buildArrivalCard(EstimatedArrival arrival, {bool divider = true}) {
    final mins = (arrival.estimateTime / 60).ceil();
    final etaLabel = mins <= 0
        ? AppStrings.t(_lang, 'arriving')
        : AppStrings.minsLabel(_lang, mins);
    return ListRow(
      leading: RouteBadge(arrival.routeName.forLang(_lang)),
      title: Text(arrival.stopName.forLang(_lang)),
      subtitle: Text(arrival.direction == 0
          ? AppStrings.t(_lang, 'outbound')
          : AppStrings.t(_lang, 'inbound')),
      trailing: Text(etaLabel,
          style: AppText.time.copyWith(color: etaColor(arrival.estimateTime))),
      divider: divider,
      onTap: () => _enterRouteDetail(
        arrival.routeName.zhTw,
        arrival.direction,
        userStopUID: arrival.stopUID,
      ),
    );
  }

  // Chinese keyboards often type full-width digits (５２), which TDX doesn't
  // match — convert them to ASCII and drop stray spaces.
  static String _normalizeRouteQuery(String raw) => String.fromCharCodes(
        raw.trim().runes.map((c) => c >= 0xFF10 && c <= 0xFF19 ? c - 0xFEE0 : c),
      ).replaceAll(' ', '');

  Widget _buildSearchTab(List<String> favourites) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
          child: TextField(
            controller: _busSearchController,
            style: AppText.body,
            cursorColor: AppPalette.accent,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: AppStrings.t(_lang, 'enterRouteNumberHint'),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppPalette.textSecondary, size: 20),
              isDense: true,
            ),
            onChanged: (v) {
              _busSearchDebounce?.cancel();
              _busSearchDebounce =
                  Timer(const Duration(milliseconds: 400), () {
                if (!mounted) return;
                setState(() => _busSearchQuery = _normalizeRouteQuery(v));
              });
            },
          ),
        ),
        if (_busSearchQuery.isNotEmpty)
          Consumer(builder: (ctx, cref, _) {
            final searchAsync = cref.watch(routeSearchProvider((
              query: _busSearchQuery,
              city: defaultCity,
            )));
            return searchAsync.when(
              loading: () => const SheetMessage(loading: true),
              error: (_, __) => SheetMessage(
                  icon: Icons.cloud_off_rounded,
                  text: AppStrings.t(_lang, 'searchFailedTryAgain')),
              data: (routes) {
                if (routes.isEmpty) {
                  return SheetMessage(
                      icon: Icons.search_off_rounded,
                      text: AppStrings.t(_lang, 'routeNotFound'));
                }
                final rows = [
                  for (final r in routes) ...[(r, 0), (r, 1)],
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(AppStrings.resultsCount(_lang, routes.length)),
                    for (var i = 0; i < rows.length; i++)
                      _buildDirectionCard(rows[i].$1, rows[i].$2, favourites,
                          divider: i < rows.length - 1),
                  ],
                );
              },
            );
          })
        else
          SheetMessage(
              icon: Icons.directions_bus_outlined,
              text: AppStrings.t(_lang, 'searchTaichungRoutes')),
      ],
    );
  }

  // One route + direction: number · "from → to" · favourite star.
  Widget _buildDirectionCard(
      BusRoute route, int direction, List<String> favourites,
      {bool divider = true}) {
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

    return ListRow(
      leading: RouteBadge(route.routeName.forLang(_lang)),
      title: Text('$from → $to'),
      subtitle: Text(dirLabel),
      trailing: CompactIconButton(
        icon: isFav ? Icons.star_rounded : Icons.star_outline_rounded,
        color: isFav ? AppPalette.accent : AppPalette.textTertiary,
        onTap: () =>
            ref.read(favouritesProvider.notifier).toggle(route.routeName.zhTw),
      ),
      divider: divider,
      onTap: () => _enterRouteDetail(route.routeName.zhTw, direction),
    );
  }

  // Fastest / easiest / shortest chips. When one itinerary is all three,
  // say so instead.
  Widget _buildRouteOptionChips() {
    if (_routeChoices.length == 1) {
      return Row(children: [
        const Icon(Icons.verified_rounded, color: AppColors.green, size: 12),
        const SizedBox(width: 4),
        Flexible(
          child: Text(AppStrings.t(_lang, 'bestAllRound'),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
      ]);
    }
    const icons = {
      'fastest': Icons.bolt_rounded,
      'easiest': Icons.airline_seat_recline_normal_rounded,
      'shortest': Icons.straighten_rounded,
    };
    const labelKeys = {
      'fastest': 'fastestRoute',
      'easiest': 'easiestRoute',
      'shortest': 'shortestRoute',
    };
    String metric(String kind, _TransitOption o) => switch (kind) {
          'fastest' => o.eta,
          'easiest' => AppStrings.transfersLabel(_lang, o.transfers),
          _ => o.dist,
        };
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _routeChoices.length; i++)
          OptionChip(
            icon: icons[_routeChoices[i].kinds.first]!,
            label: '${_routeChoices[i].kinds.map((k) => AppStrings.t(_lang, labelKeys[k]!)).join('·')}'
                ' · ${metric(_routeChoices[i].kinds.first, _routeChoices[i].option)}',
            selected: i == _selectedChoice,
            onTap: () => _chooseRouteOption(i),
          ),
      ],
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

// ─── Widgets ──────────────────────────────────────────────────────────────────

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
    final isTrip = result.tripDays > 0;
    final detail = [
      if (isTrip) AppStrings.frequentTripLabel(lang, result.tripDays),
      if (secondaryName.isNotEmpty) secondaryName,
      if (!isTrip && secondaryName.isEmpty) result.displayName,
    ].join(' · ');

    return ListRow(
      leading: Icon(isTrip ? Icons.history_rounded : Icons.place_outlined,
          size: 20,
          color: isTrip ? AppPalette.accent : AppPalette.textSecondary),
      title: Text(primaryName),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: const Icon(Icons.north_west_rounded,
          color: AppPalette.textTertiary, size: 16),
      divider: !isLast,
      onTap: onTap,
    );
  }
}

class _VoiceMicButton extends StatelessWidget {
  final bool isListening;
  final AnimationController pulse;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const _VoiceMicButton({
    required this.isListening,
    required this.pulse,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldEnd,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isListening)
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t = pulse.value;
                  return Container(
                    width: 52 * (1 + t * 0.7),
                    height: 52 * (1 + t * 0.7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.red.withValues(alpha: (1 - t) * 0.35),
                    ),
                  );
                },
              ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening ? AppPalette.danger : AppPalette.elevated,
                border: Border.all(
                    color: isListening
                        ? AppPalette.danger
                        : AppPalette.elevatedEdge),
                boxShadow: AppShadow.floating,
              ),
              child: Icon(
                isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: isListening ? Colors.white : AppPalette.accent,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Language switch inside the search bar: shows the current language.
class _LangToggle extends StatelessWidget {
  final AppLanguage lang;
  final VoidCallback onTap;
  const _LangToggle({required this.lang, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppStrings.t(lang, 'switchLanguage'),
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(
              lang == AppLanguage.zh ? '中' : 'EN',
              style: AppText.label.copyWith(
                  color: AppPalette.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Route stop marker icon ─────────────────────────────────────────────────

/// Draws a coloured dot with a white outline, [size] logical pixels wide.
/// Rendered at 3x so it stays crisp on high-density screens.
Future<BitmapDescriptor> _createStopDotIcon(double size,
    {Color color = AppColors.blue}) async {
  const scale = 3.0;
  final px = size * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(px / 2, px / 2);
  final radius = px / 2;

  canvas.drawCircle(center, radius, Paint()..color = Colors.white);
  canvas.drawCircle(center, radius * 0.72, Paint()..color = color);

  final image =
      await recorder.endRecording().toImage(px.round(), px.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: size,
    height: size,
  );
}

// ─── Route leg icons ─────────────────────────────────────────────────────────

/// One footprint, toes pointing up (north), drawn to the left or right of the
/// icon's centre so alternating feet form a natural two-track trail. Placed as
/// a flat marker rotated to the walking direction.
Future<BitmapDescriptor> _createFootprintIcon({required bool left}) async {
  const scale = 3.0;
  const w = 14.0, h = 18.0; // logical px
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);

  final cx = left ? w / 2 - 2.6 : w / 2 + 2.6;
  // Toes splay slightly outward, like a real step
  canvas.translate(cx, h / 2);
  canvas.rotate((left ? -7 : 7) * math.pi / 180);
  canvas.translate(-cx, -h / 2);

  final sole = Path()
    ..addOval(Rect.fromLTRB(cx - 2.4, 1, cx + 2.4, 9.6)) // ball of the foot
    ..addOval(Rect.fromLTRB(cx - 1.8, 10.6, cx + 1.8, 16.6)); // heel
  canvas.drawPath(
      sole,
      Paint()
        ..color = AppPalette.canvas.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
  canvas.drawPath(sole, Paint()..color = _walkColor);

  final image = await recorder
      .endRecording()
      .toImage((w * scale).round(), (h * scale).round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
      width: w, height: h);
}

/// Pill with a bus glyph and the route number, marking where to board.
Future<BitmapDescriptor> _createBusBadgeIcon(String line) async {
  const scale = 3.0;
  const height = 22.0, padX = 7.0, glyph = 13.0, gap = 3.0, border = 1.5;
  const icon = Icons.directions_bus_rounded;

  final glyphPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: glyph,
        color: AppPalette.onAccent,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final textPainter = TextPainter(
    text: TextSpan(
      text: line,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: AppPalette.onAccent,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final width = padX * 2 + glyphPainter.width + gap + textPainter.width;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height), const Radius.circular(height / 2));
  canvas.drawRRect(pill, Paint()..color = AppPalette.onAccent);
  canvas.drawRRect(pill.deflate(border), Paint()..color = AppPalette.accent);
  glyphPainter.paint(canvas, Offset(padX, (height - glyphPainter.height) / 2));
  textPainter.paint(
      canvas,
      Offset(
          padX + glyphPainter.width + gap, (height - textPainter.height) / 2));

  final image = await recorder
      .endRecording()
      .toImage((width * scale).ceil(), (height * scale).ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
      width: (width * scale).ceil() / scale, height: height);
}
