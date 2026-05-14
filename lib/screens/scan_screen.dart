// ScanScreen — OCR a bus stop sign to get route previews for each detected number

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/bus_models.dart';
import '../services/ptx_api.dart';
import '../utils/theme.dart';
import '../widgets/bus_badge.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  File? _image;
  bool _scanning = false;
  List<String> _detectedNumbers = [];
  Map<String, List<BusRoute>> _routesByNumber = {};
  String? _errorMessage;

  Future<void> _capture(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;

      final imageFile = File(picked.path);
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
          _errorMessage =
              'No bus route numbers found in this image.\nMake sure the sign is clear and well-lit.';
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

      setState(() {
        _scanning = false;
        _detectedNumbers = numbers;
        _routesByNumber = routeMap;
        if (routeMap.isEmpty) {
          _errorMessage =
              'Numbers detected (${numbers.join(', ')}) but none matched Taichung bus routes.';
        }
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _errorMessage = 'Could not process image. Please try again.';
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
                  const Text(
                    'Scan Bus Stop',
                    style: TextStyle(
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
                    label: 'Camera',
                    enabled: !_scanning,
                    onTap: () => _capture(ImageSource.camera),
                  ),
                  const SizedBox(width: 12),
                  _ActionBtn(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.blue),
            SizedBox(height: 16),
            Text('Reading sign…',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
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

    if (_image == null || _detectedNumbers.isEmpty) return const _Placeholder();

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
          'DETECTED ${_detectedNumbers.length} BUS ROUTE${_detectedNumbers.length == 1 ? '' : 'S'}',
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 11, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        ...found.expand(
          (busNum) => [
            _RouteSection(busNumber: busNum, routes: _routesByNumber[busNum]!),
            const SizedBox(height: 16),
          ],
        ),
        if (notFound.isNotEmpty) ...[
          const Text(
            'NOT FOUND IN TAICHUNG',
            style: TextStyle(
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
                ? AppColors.blue.withOpacity(0.12)
                : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  enabled ? AppColors.blue.withOpacity(0.3) : AppColors.border,
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
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.document_scanner_outlined,
                color: AppColors.textMuted, size: 48),
            SizedBox(height: 16),
            Text(
              'Point your camera at a bus stop sign',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
            SizedBox(height: 8),
            Text(
              'The app will read the route numbers and show each bus\'s schedule',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
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

  const _RouteSection({required this.busNumber, required this.routes});

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
              'Route $busNumber',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...routes.map((r) => _RoutePreviewCard(route: r)),
      ],
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  final BusRoute route;
  const _RoutePreviewCard({required this.route});

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
              direction: 'Outbound',
              from: route.departureStopNameZh,
              to: route.destinationStopNameZh,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(color: AppColors.border, height: 1),
            ),
            _DirectionRow(
              direction: 'Inbound',
              from: route.destinationStopNameZh,
              to: route.departureStopNameZh,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    route.city,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Tap for stops & ETAs ›',
                    style: TextStyle(color: AppColors.blue, fontSize: 11),
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
  final String direction;
  final String from;
  final String to;

  const _DirectionRow(
      {required this.direction, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final isOut = direction == 'Outbound';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isOut
                ? AppColors.blue.withOpacity(0.15)
                : AppColors.textSecondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            direction,
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
