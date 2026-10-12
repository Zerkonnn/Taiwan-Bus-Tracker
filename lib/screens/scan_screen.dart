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

      final numbers = _extractBusNumbers(recognized.text);

      if (numbers.isEmpty) {
        setState(() {
          _scanning = false;
          _errorMessage = AppStrings.t(_lang, 'noRouteNumbersFound');
        });
        return;
      }

      final routeMap = <String, List<BusRoute>>{};
      for (final num in numbers) {
        try {
          final routes = await PtxApi.instance.searchRoutes(num, defaultCity);
          if (routes.isNotEmpty) routeMap[num] = routes;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _scanning = false;
        _detectedNumbers = numbers;
        _routesByNumber = routeMap;
        if (routeMap.isEmpty) {
          _errorMessage = AppStrings.numbersDetectedNoneMatched(
              _lang, numbers.join(', '));
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

  static List<String> _extractBusNumbers(String text) {
    // Match standalone 1–3 digit numbers in range 1–500, plus BRT
    final re = RegExp(r'(?<!\d)(BRT|\d{1,3})(?!\d)');
    final found = <String>{};
    for (final m in re.allMatches(text)) {
      final val = m.group(0)!;
      if (val == 'BRT') {
        found.add(val);
      } else {
        final n = int.tryParse(val);
        if (n != null && n >= 1 && n <= 500) found.add(val);
      }
    }
    return found.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a) ?? 9999;
        final bi = int.tryParse(b) ?? 9999;
        return ai.compareTo(bi);
      });
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

    final found = _routesByNumber.keys.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a) ?? 9999;
        final bi = int.tryParse(b) ?? 9999;
        return ai.compareTo(bi);
      });
    final notFound =
        _detectedNumbers.where((n) => !_routesByNumber.containsKey(n)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          AppStrings.detectedBusRoutes(_lang, _detectedNumbers.length),
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        ...found.expand(
          (busNum) => [
            _RouteSection(
                busNumber: busNum,
                routes: _routesByNumber[busNum]!,
                lang: _lang),
            const SizedBox(height: 16),
          ],
        ),
        if (notFound.isNotEmpty) ...[
          Text(
            AppStrings.t(_lang, 'notFoundInTaichung'),
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: notFound.map((n) => BusBadge(routeName: n)).toList(),
          ),
        ],
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
