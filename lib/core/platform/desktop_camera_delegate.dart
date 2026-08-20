import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/sprint/modals/glass_modal.dart' show showGlassConfirm;
import '../i18n/i18n.dart';

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
  }) => _capture(video: false, options: options);

  @override
  Future<XFile?> takeVideo({
    ImagePickerCameraDelegateOptions options =
        const ImagePickerCameraDelegateOptions(),
  }) => _capture(video: true, options: options);

  Future<XFile?> _capture({
    required bool video,
    required ImagePickerCameraDelegateOptions options,
  }) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return null;

    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on MissingPluginException catch (e) {
      // No camera implementation is registered for this platform at all — the
      // `camera` package ships android/ios/web, and Windows is only covered
      // because we depend on camera_windows explicitly. macOS has no
      // implementation, so the call never reaches native code.
      debugPrint('availableCameras unimplemented: $e');
      await _report(navigator, _CaptureProblem.unsupported);
      return null;
    } on UnimplementedError catch (e) {
      debugPrint('availableCameras unimplemented: $e');
      await _report(navigator, _CaptureProblem.unsupported);
      return null;
    } catch (e) {
      // CameraException (the platform said no) or anything else the plugin
      // throws. Either way the user gets told instead of watching the menu
      // close on nothing.
      debugPrint('availableCameras failed: $e');
      await _report(navigator, _CaptureProblem.blocked);
      return null;
    }

    // A blocked or absent camera is an EMPTY LIST on Windows, not an error:
    // MFEnumDeviceSources succeeds with a count of 0 when "Camera access" is
    // off for the app, and Media Foundation raises no consent prompt of its
    // own. Silently returning null here is what made the menu entry look dead.
    if (cameras.isEmpty) {
      await _report(navigator, _CaptureProblem.blocked);
      return null;
    }

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

  /// Tells the user why no capture UI opened, and offers the one action that
  /// can fix it. Without this the delegate's null return is indistinguishable
  /// from "user cancelled", so the caller quietly does nothing.
  Future<void> _report(
    NavigatorState navigator,
    _CaptureProblem problem,
  ) async {
    // The navigator's own context: `Navigator.of` resolves it directly, which
    // is what a dialog needs. A toast would not work here — `Overlay.of` only
    // walks ancestors, and the navigator's overlay is a descendant of it.
    final context = navigator.context;
    if (!context.mounted) return;

    final settings = problem == _CaptureProblem.blocked
        ? cameraPrivacySettingsUri()
        : null;

    final open = await showGlassConfirm(
      context,
      icon: LucideIcons.cameraOff,
      title: context.t('camera.blockedTitle'),
      message: problem == _CaptureProblem.unsupported
          ? context.t('camera.unsupported')
          : context.t('camera.blockedBody'),
      // Nothing actionable to offer on an unsupported platform, or on an OS
      // without a known settings deep link — the dialog just closes.
      confirmLabel: settings == null
          ? context.t('camera.close')
          : context.t('camera.openSettings'),
      confirmIcon: settings == null
          ? LucideIcons.check
          : LucideIcons.externalLink,
    );
    if (settings != null && (open ?? false)) {
      await launchUrl(settings);
    }
  }
}

/// Why a capture never started. The two cases need different words: a blocked
/// camera is a setting the user can flip, a missing implementation is not.
enum _CaptureProblem { blocked, unsupported }

/// Deep link to the OS page that grants camera access, or null where we have no
/// stable one.
///
/// This *is* a platform switch, unlike [installDesktopCameraDelegate]: which
/// settings page exists is a property of the OS, not of the registered plugin.
@visibleForTesting
Uri? cameraPrivacySettingsUri() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => Uri.parse('ms-settings:privacy-webcam'),
    TargetPlatform.macOS => Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Camera',
    ),
    _ => null,
  };
}

/// Wires the delegate into whichever image_picker implementation is active.
///
/// No-op where the platform handles the camera itself (Android, iOS, web), and
/// otherwise driven by [ImagePickerPlatform.instance] rather than by a
/// `Platform.isWindows` check, so it stays correct if a desktop platform gains
/// native camera support later.
///
/// Linux is the exception, and deliberately a platform check. `image_picker_
/// linux` extends `CameraDelegatingImagePickerPlatform` exactly like the
/// Windows and macOS ones, so it *would* take a delegate — but no camera
/// implementation exists for Linux at all: `camera` ships android, iOS and web,
/// Windows is only covered because the app depends on `camera_windows`, and
/// there is no third package we trust for Linux. Taking the delegate makes
/// `supportsImageSource(ImageSource.camera)` true, which puts a camera entry in
/// the composer that can only ever open a dialog saying there is no camera —
/// and on Linux that dialog cannot even offer a settings link, because no
/// desktop environment has a stable one ([cameraPrivacySettingsUri] returns
/// null). Not offering the entry is the honest answer.
void installDesktopCameraDelegate(GlobalKey<NavigatorState> navigatorKey) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) return;
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

  /// Technical detail for the error state. The headline is localized; this line
  /// carries the platform's own wording, which is what makes "another app is
  /// using the camera" distinguishable from "access denied" in a bug report.
  String _describe(Object e) {
    if (e is CameraException) {
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
      key: const ValueKey('desktop-camera-capture'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: context.t('camera.close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(LucideIcons.switchCamera),
              tooltip: context.t('camera.switchCamera'),
              onPressed: _recording
                  ? null
                  : () => _start((_index + 1) % widget.cameras.length),
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? _CaptureError(detail: _error!)
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

/// Error state of the capture screen: a localized headline, the platform's own
/// wording underneath, and — where the OS has one — a jump to the settings page
/// that grants camera access. The privacy toggle blocks opening a device even
/// when it enumerated fine, so this is reachable with a camera present.
class _CaptureError extends StatelessWidget {
  const _CaptureError({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final settings = cameraPrivacySettingsUri();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.t('camera.failed'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          if (settings != null) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => launchUrl(settings),
              icon: const Icon(LucideIcons.externalLink, size: 16),
              label: Text(context.t('camera.openSettings')),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        ],
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
          ? context.t(
              recording ? 'camera.stopRecording' : 'camera.startRecording',
            )
          : context.t('camera.takePhoto'),
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
