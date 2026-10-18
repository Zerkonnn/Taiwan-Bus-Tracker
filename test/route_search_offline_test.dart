import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taiwan_bus_tracker/services/ptx_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('route search works from the bundled list without network', () async {
    SharedPreferences.setMockInitialValues({});
    for (final n in ['54', '45', '37', '79']) {
      final routes = await PtxApi.instance.searchRoutes(n, 'Taichung');
      expect(routes.first.routeName.zhTw, n);
      expect(routes.first.destinationStopNameZh, isNotEmpty);
    }
  });
}
