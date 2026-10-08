// Trip history — remembers which destinations the user travels to, and from
// where, so repeated trips (e.g. home → school every day) can be recognised.
//
// A trip counts as "frequent" once it has been made on at least two different
// days. Frequent trips are suggested first in the destination search, and
// selecting one automatically compares the fastest and shortest bus options.
//
// Persisted as JSON in SharedPreferences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart' show haversineDistance;

class SavedTrip {
  final String name;
  final String nameEn;
  final String displayName;
  final double lat;
  final double lon;
  final double? originLat;
  final double? originLon;
  // Distinct local dates ('yyyy-mm-dd') this trip was made on, oldest first.
  final List<String> days;
  final DateTime lastUsed;

  const SavedTrip({
    required this.name,
    required this.nameEn,
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.originLat,
    required this.originLon,
    required this.days,
    required this.lastUsed,
  });

  int get dayCount => days.length;
  bool get isFrequent => dayCount >= TripHistory.frequentAfterDays;

  Map<String, dynamic> toJson() => {
        'name': name,
        'nameEn': nameEn,
        'displayName': displayName,
        'lat': lat,
        'lon': lon,
        'originLat': originLat,
        'originLon': originLon,
        'days': days,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory SavedTrip.fromJson(Map<String, dynamic> json) => SavedTrip(
        name: json['name'] as String,
        nameEn: (json['nameEn'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        originLat: (json['originLat'] as num?)?.toDouble(),
        originLon: (json['originLon'] as num?)?.toDouble(),
        days: (json['days'] as List<dynamic>).cast<String>(),
        lastUsed: DateTime.parse(json['lastUsed'] as String),
      );
}

class TripHistory {
  static final TripHistory instance = TripHistory._();
  TripHistory._();

  static const _key = 'trip_history';
  static const frequentAfterDays = 2;

  // Two searches count as the same trip when both ends are this close.
  static const _sameDestinationMeters = 200.0;
  static const _sameOriginMeters = 800.0;

  static const _maxTrips = 30;
  static const _maxDaysPerTrip = 30;

  Future<List<SavedTrip>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => SavedTrip.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<SavedTrip> trips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(trips.map((t) => t.toJson()).toList()));
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool _originMatches(
      double? aLat, double? aLon, double? bLat, double? bLon) {
    // Unknown origin (no GPS) matches anything rather than splitting history.
    if (aLat == null || aLon == null || bLat == null || bLon == null) {
      return true;
    }
    return haversineDistance(aLat, aLon, bLat, bLon) <= _sameOriginMeters;
  }

  /// Records a trip to the given destination, starting from the origin.
  /// Returns the updated trip.
  Future<SavedTrip> record({
    required String name,
    String nameEn = '',
    String displayName = '',
    required double lat,
    required double lon,
    double? originLat,
    double? originLon,
    DateTime? now, // override for tests
  }) async {
    final trips = await _load();
    now ??= DateTime.now();
    final today = _dayKey(now);

    final index = trips.indexWhere((t) =>
        haversineDistance(t.lat, t.lon, lat, lon) <= _sameDestinationMeters &&
        _originMatches(t.originLat, t.originLon, originLat, originLon));

    final previousDays = index >= 0 ? trips[index].days : const <String>[];
    final days = [...previousDays.where((d) => d != today), today];
    final updated = SavedTrip(
      name: name,
      nameEn: nameEn,
      displayName: displayName,
      lat: lat,
      lon: lon,
      originLat: originLat ?? (index >= 0 ? trips[index].originLat : null),
      originLon: originLon ?? (index >= 0 ? trips[index].originLon : null),
      days: days.length > _maxDaysPerTrip
          ? days.sublist(days.length - _maxDaysPerTrip)
          : days,
      lastUsed: now,
    );

    if (index >= 0) trips.removeAt(index);
    trips.insert(0, updated);
    if (trips.length > _maxTrips) trips.removeRange(_maxTrips, trips.length);
    await _save(trips);
    return updated;
  }

  /// Frequent trips that start near [originLat]/[originLon] (or all frequent
  /// trips when the location is unknown), most-used first.
  Future<List<SavedTrip>> frequentTrips(
      {double? originLat, double? originLon}) async {
    final trips = await _load();
    final result = trips
        .where((t) =>
            t.isFrequent &&
            _originMatches(t.originLat, t.originLon, originLat, originLon))
        .toList()
      ..sort((a, b) {
        final byDays = b.dayCount.compareTo(a.dayCount);
        return byDays != 0 ? byDays : b.lastUsed.compareTo(a.lastUsed);
      });
    return result;
  }
}
