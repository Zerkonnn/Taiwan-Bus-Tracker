// ScanScreen — OCR a bus stop sign to get route previews for each detected number

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bus_models.dart';
import '../providers/bus_providers.dart';
import '../services/ptx_api.dart';
import '../utils/app_strings.dart';
import '../utils/theme.dart';
import '../widgets/bus_badge.dart';
import 'camera_capture_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  File? _image;
  bool _scanning = false;
  List<String> _detectedNumbers = [];
  Map<String, List<BusRoute>> _routesByNumber = {};
  String? _errorMessage;

  // Cached each build from languageProvider so _capture (an async event
  // handler running outside the build phase) can read the current language.
  AppLanguage _lang = AppLanguage.zh;

  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
  }

  // Low-memory phones may kill the app while the camera app is open. Android
  // then restarts us without the photo — pick it back up here.
  Future<void> _recoverLostPhoto() async {
    if (!Platform.isAndroid) return;
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (lost.isEmpty || lost.file == null || !mounted) return;
      await _scan(File(lost.file!.path));
    } catch (_) {}
  }

  // In-app camera rather than image_picker's camera, which leaves the app in
  // the background where Android may kill it (see CameraCaptureScreen).
  Future<void> _takePhoto() async {
    final result = await Navigator.push<Object?>(context,
        MaterialPageRoute(builder: (_) => const CameraCaptureScreen()));
    if (!mounted || result == null) return;
    if (result is CameraCaptureError) {
      setState(() => _errorMessage = AppStrings.t(
          _lang,
          result == CameraCaptureError.permissionDenied
              ? 'cameraPermissionDenied'
              : 'cameraUnavailable'));
      return;
    }
    await _scan(File(result as String));
  }

  Future<void> _capture(ImageSource source) async {
    final XFile? picked;
    try {
      // Cap the size: full-res 50 MP photos can run the phone out of memory,
      // and sign text is still easily readable at 1920 px.
      picked = await ImagePicker().pickImage(
          source: source, maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
    } catch (e) {
      debugPrint('Image pick failed: $e');
      setState(() => _errorMessage = AppStrings.t(_lang, 'couldNotProcessImage'));
      return;
    }
    if (picked == null || !mounted) return;
    await _scan(File(picked.path));
  }

  Future<void> _scan(File imageFile) async {
    try {
      setState(() {
        _image = imageFile;
        _scanning = true;
        _detectedNumbers = [];
        _routesByNumber = {};
        _errorMessage = null;
      });

      final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final recognized =
          await recognizer.processImage(InputImage.fromFile(imageFile));
      await recognizer.close();

      final candidates = _extractRouteCandidates(recognized.text);

      if (candidates.isEmpty) {
        setState(() {
          _scanning = false;
          _errorMessage = AppStrings.t(_lang, 'noRouteNumbersFound');
        });
        return;
      }

      // Signs also carry times, phone numbers and stop codes — keep only the
      // numbers that are exactly a route name, so a sign listing 5 routes
      // gives those 5 (and "5" shows route 5, not 50, 51, 52…).
      final routeMap = <String, List<BusRoute>>{};
      try {
        for (final token in candidates) {
          final routes = await PtxApi.instance.searchRoutes(token, defaultCity);
          final exact = routes
              .where((r) =>
                  r.routeName.zhTw.toUpperCase() == token ||
                  r.routeName.en.toUpperCase() == token)
              .toList();
          if (exact.isNotEmpty) routeMap[token] = exact;
        }
      } catch (e) {
        // Route list not downloaded yet and no connection
        debugPrint('Scan route lookup failed: $e');
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _errorMessage = AppStrings.t(_lang, 'searchFailedTryAgain');
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _detectedNumbers = routeMap.keys.toList()..sort(_compareRouteNames);
        _routesByNumber = routeMap;
        if (routeMap.isEmpty) {
          _errorMessage = AppStrings.numbersDetectedNoneMatched(
              _lang, candidates.join(', '));
        }
      });
    } catch (e) {
      debugPrint('OCR failed: $e');
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _errorMessage = AppStrings.t(_lang, 'couldNotProcessImage');
      });
    }
  }

  // Anything on the sign shaped like a Taichung route name: 1–3 digits with an
  // optional colour prefix or letter suffix (52, 305W, 70A, 黃1, 綠2) and BRT.
  // Whether it's really a route is checked against the route list afterwards.
  static List<String> _extractRouteCandidates(String text) {
    // Digits touching ':' or '-' belong to a time (22:30) or phone number
    final re = RegExp(r'(?<![\dA-Z:\-])(BRT|[黃綠]?\d{1,3}[A-Z]?)(?![\dA-Z:\-])');
    final found = <String>{};
    for (final m in re.allMatches(text.toUpperCase())) {
      final val = m.group(1)!;
      // "06" from "06:00" is never a route name
      if (RegExp(r'^[黃綠]?0').hasMatch(val)) continue;
      found.add(val);
    }
    return found.toList()..sort(_compareRouteNames);
  }

  // Numeric order (5, 52, 305W, 811), colour routes and BRT after plain ones
  static int _compareRouteNames(String a, String b) {
    int key(String s) => RegExp(r'^\d+').hasMatch(s)
        ? int.parse(RegExp(r'^\d+').firstMatch(s)!.group(0)!)
        : 100000;
    final byNumber = key(a).compareTo(key(b));
    return byNumber != 0 ? byNumber : a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    _lang = ref.watch(languageProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    AppStrings.t(_lang, 'scanBusStopTitle'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // ── Capture buttons ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _ActionBtn(
                    icon: Icons.camera_alt_rounded,
                    label: AppStrings.t(_lang, 'camera'),
                    enabled: !_scanning,
                    onTap: _takePhoto,
                  ),
                  const SizedBox(width: 12),
                  _ActionBtn(
                    icon: Icons.photo_library_rounded,
                    label: AppStrings.t(_lang, 'gallery'),
                    enabled: !_scanning,
                    onTap: () => _capture(ImageSource.gallery),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Captured image thumbnail ─────────────────────────────────────
            if (_image != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.file(
                    _image!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    // Decoding the full 1080p photo just for a 110 px strip
                    // wastes memory the OCR step needs
                    cacheWidth: 800,
                  ),
                ),
              ),

            // ── Results / placeholder ────────────────────────────────────────
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.blue),
            const SizedBox(height: 16),
            Text(AppStrings.t(_lang, 'readingSign'),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 14)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.document_scanner_outlined,
                  color: AppColors.textMuted, size: 42),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_image == null || _detectedNumbers.isEmpty) {
      return _Placeholder(lang: _lang);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          AppStrings.detectedBusRoutes(_lang, _detectedNumbers.length),
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        ..._detectedNumbers.expand(
          (busNum) => [
            _RouteSection(
                busNumber: busNum,
                routes: _routesByNumber[busNum]!,
                lang: _lang),
            const SizedBox(height: 16),
          ],
        ),
      ],
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.blue.withValues(alpha: 0.12)
                : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  enabled ? AppColors.blue.withValues(alpha: 0.3) : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: enabled ? AppColors.blue : AppColors.textMuted,
                  size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                    color: enabled ? AppColors.blue : AppColors.textMuted,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final AppLanguage lang;
  const _Placeholder({required this.lang});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.document_scanner_outlined,
                color: AppColors.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              AppStrings.t(lang, 'pointCameraAtSign'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.t(lang, 'appWillReadRouteNumbers'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSection extends StatelessWidget {
  final String busNumber;
  final List<BusRoute> routes;
  final AppLanguage lang;

  const _RouteSection(
      {required this.busNumber, required this.routes, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BusBadge(routeName: busNumber),
            const SizedBox(width: 10),
            Text(
              AppStrings.route(lang, busNumber),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...routes.map((r) => _RoutePreviewCard(route: r, lang: lang)),
      ],
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  final BusRoute route;
  final AppLanguage lang;
  const _RoutePreviewCard({required this.route, required this.lang});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/route_detail',
        arguments: {
          'routeName': route.routeName.zhTw,
          'routeUID': route.routeUID,
        },
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DirectionRow(
              isOutbound: true,
              from: route.departureStopNameZh,
              to: route.destinationStopNameZh,
              lang: lang,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(color: AppColors.border, height: 1),
            ),
            _DirectionRow(
              isOutbound: false,
              from: route.destinationStopNameZh,
              to: route.departureStopNameZh,
              lang: lang,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cityLabel(lang, route.city),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppStrings.t(lang, 'tapForStopsEtas'),
                    style: const TextStyle(
                        color: AppColors.blue, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionRow extends StatelessWidget {
  final bool isOutbound;
  final String from;
  final String to;
  final AppLanguage lang;

  const _DirectionRow(
      {required this.isOutbound,
      required this.from,
      required this.to,
      required this.lang});

  @override
  Widget build(BuildContext context) {
    final isOut = isOutbound;
    final label = AppStrings.t(lang, isOut ? 'outbound' : 'inbound');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isOut
                ? AppColors.blue.withValues(alpha: 0.15)
                : AppColors.textSecondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isOut ? AppColors.blue : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$from  →  $to',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
