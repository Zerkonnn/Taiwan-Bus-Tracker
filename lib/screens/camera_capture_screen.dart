// CameraCaptureScreen — takes the sign photo inside the app.
//
// image_picker hands the camera off to the phone's camera app. While it is
// open our app sits in the background with Google Maps loaded, and low-memory
// phones kill it — the user comes back to a restarted app on the map screen,
// which looks exactly like a crash. Capturing in-process avoids that.
//
// Pops with the captured photo's path, or null if the user backs out.
// If the camera can't start it pops with a [CameraCaptureError] instead.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

enum CameraCaptureError { permissionDenied, unavailable }

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _taking = false;
  // The permission prompt sends the app through inactive → resumed while
  // initialize() is still running — don't start a second controller then.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // The camera must be released when the app is backgrounded and reopened
  // when it returns, or other apps (and Android) can't use it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller == null || !controller.value.isInitialized) return;
      _controller = null;
      setState(() {});
      controller.dispose();
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        !_starting) {
      _start();
    }
  }

  Future<void> _start() async {
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return _fail(CameraCaptureError.unavailable);
      final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      // 1080p keeps sign text sharp for OCR without the memory cost of a
      // full-resolution 50 MP photo.
      final controller = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      debugPrint('Camera init failed: ${e.code} ${e.description}');
      _fail(e.code.contains('AccessDenied') || e.code.contains('Permission')
          ? CameraCaptureError.permissionDenied
          : CameraCaptureError.unavailable);
    } catch (e) {
      debugPrint('Camera init failed: $e');
      _fail(CameraCaptureError.unavailable);
    } finally {
      _starting = false;
    }
  }

  void _fail(CameraCaptureError error) {
    if (mounted) Navigator.pop(context, error);
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (_taking || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() => _taking = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.pop(context, photo.path);
    } catch (e) {
      debugPrint('Take picture failed: $e');
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ready
                  ? CameraPreview(controller)
                  : const CircularProgressIndicator(color: AppColors.blue),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: GestureDetector(
                  onTap: ready ? _takePicture : null,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _taking || !ready
                            ? Colors.white38
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
