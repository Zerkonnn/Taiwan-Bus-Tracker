// Crash recovery — replaces Flutter's red error screen with an automatic
// in-app restart.
//
// When a widget throws while building (e.g. after a burst of interactions hits
// the API rate limit and a screen receives data it can't handle), Flutter
// normally paints the red "ErrorWidget" screen and the app is stuck until it
// is re-run manually. Instead, we show a short "Restarting…" overlay and then
// rebuild the whole app from scratch (fresh ProviderScope, fresh navigator).
//
// The PtxApi singleton is NOT reset, so its response cache survives the
// restart — the app comes back showing cached data instead of immediately
// re-hitting the API.
//
// Screens record what the user is doing (selected destination, open route,
// sheet tab…) in [CrashRecovery.session]. After an automatic restart they read
// it back with [CrashRecovery.takeRestored] so the user lands where
// they were instead of on a blank start screen.
//
// To avoid an endless crash → restart → crash loop, restarts are rate limited:
// if the app crashes too often in a short window, auto-restart stops and a
// manual "Restart" button is shown instead.

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

class CrashRecovery {
  CrashRecovery._();

  // Delay before restarting, so the "Restarting…" message is visible.
  static const _restartDelay = Duration(milliseconds: 1200);

  // Crash-loop guard: at most [_maxRestarts] auto-restarts per [_window].
  static const _maxRestarts = 3;
  static const _window = Duration(seconds: 30);
  static final _recentRestarts = <DateTime>[];

  static bool _restartScheduled = false;

  /// What the user is currently doing, kept up to date by the screens.
  /// Lives outside the widget tree, so it survives an in-app restart.
  static final Map<String, Object?> session = {};

  static Map<String, Object?>? _restored;

  /// Returns (once) the value saved under [key] before the last automatic
  /// restart, or null on a normal start / after a manual restart.
  static Object? takeRestored(String key) => _restored?.remove(key);

  /// Runs the app with global error handlers installed.
  static void run(Widget app) {
    runZonedGuarded(() {
      WidgetsFlutterBinding.ensureInitialized();

      // Log framework errors as usual (build/layout/paint errors). The visible
      // recovery is driven by ErrorWidget.builder below, so non-fatal errors
      // such as a failed image load don't trigger a restart.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };

      // Replace the red error screen with an auto-restarting placeholder.
      ErrorWidget.builder = buildErrorWidget;

      // Uncaught async errors (e.g. a failed HTTP call nobody awaited).
      // Log and swallow — they don't break the UI on their own.
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught async error: $error\n$stack');
        return true;
      };

      runApp(AppRestarter(child: app));
    }, (error, stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
    });
  }

  /// Used as [ErrorWidget.builder]: shows a recovery placeholder and
  /// schedules a restart.
  static Widget buildErrorWidget(FlutterErrorDetails details) {
    final willRestart = _scheduleRestart();
    return _RecoveringView(autoRestart: willRestart);
  }

  static bool _canAutoRestart() {
    final now = DateTime.now();
    _recentRestarts.removeWhere((t) => now.difference(t) > _window);
    return _recentRestarts.length < _maxRestarts;
  }

  /// Returns true if an automatic restart is (or already was) scheduled.
  static bool _scheduleRestart() {
    // Several widgets can fail in the same frame — restart only once.
    if (_restartScheduled) return true;
    if (!_canAutoRestart()) return false;
    _restartScheduled = true;
    _recentRestarts.add(DateTime.now());
    Timer(_restartDelay, () => restartNow(restoreSession: true));
    return true;
  }

  /// Rebuilds the whole app immediately. With [restoreSession], screens get
  /// the pre-crash session back. The manual "Restart" button (shown after
  /// repeated crashes) starts clean, in case the saved state is what crashes.
  static void restartNow({bool restoreSession = false}) {
    _restartScheduled = false;
    _restored = restoreSession ? Map.of(session) : null;
    session.clear();
    AppRestarter._instance?._restart();
  }
}

// ─── Restart wrapper ─────────────────────────────────────────────────────────

/// Wraps the app; swapping its key throws away the entire widget tree
/// (including ProviderScope state) and builds it again from scratch.
class AppRestarter extends StatefulWidget {
  final Widget child;
  const AppRestarter({super.key, required this.child});

  static _AppRestarterState? _instance;

  @override
  State<AppRestarter> createState() => _AppRestarterState();
}

class _AppRestarterState extends State<AppRestarter> {
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
    AppRestarter._instance = this;
  }

  @override
  void dispose() {
    if (AppRestarter._instance == this) AppRestarter._instance = null;
    super.dispose();
  }

  void _restart() {
    if (!mounted) return;
    debugPrint('CrashRecovery: restarting app');
    setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

// ─── Placeholder shown instead of the red screen ─────────────────────────────

class _RecoveringView extends StatelessWidget {
  final bool autoRestart;
  const _RecoveringView({required this.autoRestart});

  @override
  Widget build(BuildContext context) {
    // May be built outside MaterialApp, so supply Directionality ourselves
    // and avoid widgets that need Material ancestors.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (autoRestart) ...[
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '發生錯誤，正在重新啟動…\nSomething went wrong. Restarting…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ] else ...[
                  const Text(
                    '發生錯誤，請稍後再試\nSomething went wrong. Please wait a moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => CrashRecovery.restartNow(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '重新啟動 / Restart',
                        style: TextStyle(
                          color: Color(0xFF0A1628),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
