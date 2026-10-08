import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taiwan_bus_tracker/services/trip_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> trip(DateTime day, {double lat = 24.1800, double oLat = 24.1500}) =>
      TripHistory.instance.record(
        name: 'Feng Chia University',
        lat: lat,
        lon: 120.6445,
        originLat: oLat,
        originLon: 120.6500,
        now: day,
      );

  test('a trip becomes frequent only after being made on 2 different days',
      () async {
    final h = TripHistory.instance;
    await trip(DateTime(2026, 10, 1, 8));
    await trip(DateTime(2026, 10, 1, 18)); // same day again
    expect(await h.frequentTrips(), isEmpty);

    await trip(DateTime(2026, 10, 2, 8));
    final frequent = await h.frequentTrips(originLat: 24.1502, originLon: 120.6501);
    expect(frequent, hasLength(1));
    expect(frequent.first.dayCount, 2);
  });

  test('frequent trips from a far-away origin are not suggested', () async {
    await trip(DateTime(2026, 10, 1));
    await trip(DateTime(2026, 10, 2));
    final far = await TripHistory.instance
        .frequentTrips(originLat: 25.0330, originLon: 121.5654); // Taipei
    expect(far, isEmpty);
  });
}
