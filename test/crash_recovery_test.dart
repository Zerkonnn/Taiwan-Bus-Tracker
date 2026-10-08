import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwan_bus_tracker/utils/crash_recovery.dart';

bool shouldThrow = true;
int builds = 0;

class _Flaky extends StatelessWidget {
  const _Flaky();
  @override
  Widget build(BuildContext context) {
    builds++;
    if (shouldThrow) throw Exception('boom');
    return const Text('ok', textDirection: TextDirection.ltr);
  }
}

void main() {
  testWidgets('build error shows restarting view, then app rebuilds',
      (tester) async {
    final originalBuilder = ErrorWidget.builder;
    ErrorWidget.builder = CrashRecovery.buildErrorWidget;
    await tester.pumpWidget(const AppRestarter(child: _Flaky()));
    tester.takeException();
    expect(find.textContaining('Restarting'), findsOneWidget);

    shouldThrow = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('ok'), findsOneWidget);
    ErrorWidget.builder = originalBuilder;
  });

  test('auto restart restores the saved session once; manual restart does not',
      () {
    CrashRecovery.session['route'] = {'name': '351', 'dir': 1};
    CrashRecovery.restartNow(restoreSession: true);
    expect(CrashRecovery.takeRestored('route'), {'name': '351', 'dir': 1});
    expect(CrashRecovery.takeRestored('route'), isNull); // only once

    CrashRecovery.session['route'] = {'name': '35', 'dir': 0};
    CrashRecovery.restartNow(); // manual "Restart" button
    expect(CrashRecovery.takeRestored('route'), isNull);
  });
}
