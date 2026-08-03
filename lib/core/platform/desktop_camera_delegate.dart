import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Camera capture for the desktop platforms.
///
/// `image_picker_windows` / `image_picker_macos` implement everything except
/// [ImageSource.camera]: they extend `CameraDelegatingImagePickerPlatform`,
/// which throws a `StateError` for the camera source unless a delegate is
/// installed. Mobile needs none of this — the OS ships a capture UI; on desktop
/// the app has to bring its own, which is what this file is.
///
/// Install once at startup via [installDesktopCameraDelegate]. Everything else
/// in the app keeps calling `ImagePicker().pickImage(source: …)` unchanged.
class DesktopCameraDelegate extends ImagePickerCameraDelegate {
  DesktopCameraDelegate(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;

  @override
  Future<XFile?> takePhoto({
    ImagePickerCameraDelegateOptions options =
        const ImagePickerCameraDelegateOptions(),
  }) =>
      _capture(video: false, options: options);

  @override
  Future<XFile?> takeVideo({
    ImagePickerCameraDelegateOptions options =
        const ImagePickerCameraDelegateOptions(),
  }) =>
      _capture(video: true, options: options);

  Future<XFile?> _capture({
    required bool video,
    required ImagePickerCameraDelegateOptions options,
  }) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return null;

    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      // No camera, or the capability/privacy setting denies access. Returning
      // null keeps the caller on its "user cancelled" path instead of blowing
      // up an upload flow.
      debugPrint('availableCameras failed: ${e.code} ${e.description}');
      return null;
    }
    if (cameras.isEmpty) return null;

    return navigator.push<XFile?>(
      MaterialPageRoute<XFile?>(
        fullscreenDialog: true,
        builder: (_) => _CaptureScreen(
          cameras: cameras,
          video: video,
          preferred: options.preferredCameraDevice,
        ),
      ),
    );
  }
}

/// Wires the delegate into whichever image_picker implementation is active.
///
/// No-op where the platform handles the camera itself (Android, iOS, web) — and
/// deliberately driven by [ImagePickerPlatform.instance] rather than by a
/// `Platform.isWindows` check, so it stays correct if a platform gains native
/// camera support later.
void installDesktopCameraDelegate(GlobalKey<NavigatorState> navigatorKey) {
  final platform = ImagePickerPlatform.instance;
  if (platform is CameraDelegatingImagePickerPlatform) {
    platform.cameraDelegate = DesktopCameraDelegate(navigatorKey);
  }
}

class _CaptureScreen extends StatefulWidget {
  const _CaptureScreen({
    required this.cameras,
    required this.video,
    required this.preferred,
  });

  final List<CameraDescription> cameras;
  final bool video;
  final CameraDevice preferred;

  @override
  State<_CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<_CaptureScreen> {
  CameraController? _controller;
  Future<void>? _initialized;
  int _index = 0;
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _index = widget.cameras.indexWhere(
      (c) =>
          c.lensDirection ==
          (widget.preferred == CameraDevice.front
              ? CameraLensDirection.front
              : CameraLensDirection.back),
    );
    if (_index < 0) _index = 0;
    _start(_index);
  }

  void _start(int index) {
    final previous = _controller;
    final controller = CameraController(
      widget.cameras[index],
      ResolutionPreset.high,
      // Only ask for the microphone when a video is actually being recorded —
      // a photo capture must not light up the mic indicator.
      enableAudio: widget.video,
    );
    setState(() {
      _controller = controller;
      _error = null;
      _initialized = controller.initialize().catchError((Object e) {
        if (mounted) setState(() => _error = _describe(e));
      });
    });
    previous?.dispose();
  }

  String _describe(Object e) {
    if (e is CameraException) {
      // The most likely case on Windows: Settings → Privacy → Camera is off,
      // or another app holds the device.
      return '${e.code}: ${e.description ?? ''}'.trim();
    }
    return e.toString();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      if (!widget.video) {
        final file = await controller.takePicture();
        if (mounted) Navigator.of(context).pop(file);
        return;
      }
      if (_recording) {
        final file = await controller.stopVideoRecording();
        if (mounted) Navigator.of(context).pop(file);
        return;
      }
      await controller.startVideoRecording();
      if (mounted) setState(() => _recording = true);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(LucideIcons.switchCamera),
              onPressed: _recording
                  ? null
                  : () => _start((_index + 1) % widget.cameras.length),
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : FutureBuilder<void>(
                future: _initialized,
                builder: (context, snapshot) {
                  if (controller == null ||
                      snapshot.connectionState != ConnectionState.done ||
                      !controller.value.isInitialized) {
                    return const CircularProgressIndicator();
                  }
                  return AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  );
                },
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ShutterButton(
                recording: _recording,
                video: widget.video,
                onTap: _error == null ? _shoot : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.recording,
    required this.video,
    required this.onTap,
  });

  final bool recording;
  final bool video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: video
          ? (recording ? 'Stop recording' : 'Start recording')
          : 'Take photo',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 3),
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: recording ? 26 : 56,
              height: recording ? 26 : 56,
              decoration: BoxDecoration(
                color: video ? Colors.redAccent : Colors.white,
                borderRadius: BorderRadius.circular(recording ? 6 : 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
