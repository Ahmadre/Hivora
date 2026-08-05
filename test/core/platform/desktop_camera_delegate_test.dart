import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/platform/desktop_camera_delegate.dart';

/// Desktop has no OS capture UI, so the app brings its own via an
/// [ImagePickerCameraDelegate]. Every failure used to resolve to `null`, which
/// image_picker cannot tell apart from "user cancelled" — so on Windows the
/// "take photo/video" entry closed the menu and did nothing at all, with no
/// permission prompt either. These tests pin the failure modes to a visible,
/// actionable message.
///
/// The empty-list case is the important one: a camera that is absent or blocked
/// by Windows' privacy setting enumerates as an EMPTY LIST, not as an error
/// (MFEnumDeviceSources succeeds with a count of 0).
void main() {
  const capture = ValueKey('desktop-camera-capture');

  late CameraPlatform original;

  setUp(() => original = CameraPlatform.instance);

  tearDown(() {
    CameraPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  /// Hosts a navigator the delegate can push onto / show dialogs from.
  ///
  /// Text is scaled down because widget tests render i18n *keys* in the square
  /// test font, which makes every label far wider than the real translation —
  /// enough to overflow the fixed-width modal footer for test reasons alone.
  (Widget, GlobalKey<NavigatorState>) host() {
    final key = GlobalKey<NavigatorState>();
    return (
      MaterialApp(
        navigatorKey: key,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.6)),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
      key,
    );
  }

  testWidgets('a camera list that comes back empty explains itself', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    CameraPlatform.instance = _FakeCameraPlatform();

    final (app, key) = host();
    await tester.pumpWidget(app);

    final result = DesktopCameraDelegate(key).takePhoto();
    await tester.pumpAndSettle();

    // The user is told what happened and offered the one thing that fixes it…
    expect(find.text('camera.blockedTitle'), findsOneWidget);
    expect(find.text('camera.blockedBody'), findsOneWidget);
    expect(find.text('camera.openSettings'), findsOneWidget);
    // …and no capture screen was opened behind it.
    expect(find.byKey(capture), findsNothing);
    expect(tester.takeException(), isNull);

    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a camera the platform refuses explains itself', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    CameraPlatform.instance = _FakeCameraPlatform(
      error: CameraException('CameraAccessDenied', 'denied'),
    );

    final (app, key) = host();
    await tester.pumpWidget(app);

    final result = DesktopCameraDelegate(key).takePhoto();
    await tester.pumpAndSettle();

    expect(find.text('camera.blockedTitle'), findsOneWidget);
    expect(find.byKey(capture), findsNothing);

    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a platform without a camera implementation says so', (
    tester,
  ) async {
    // macOS ships no camera implementation at all (the `camera` package covers
    // android/ios/web, and Windows only because camera_windows is an explicit
    // dependency), so the call never reaches native code.
    CameraPlatform.instance = _FakeCameraPlatform(
      error: MissingPluginException('no implementation'),
    );

    final (app, key) = host();
    await tester.pumpWidget(app);

    final result = DesktopCameraDelegate(key).takePhoto();
    await tester.pumpAndSettle();

    // Explained, but with no settings link to offer — there is nothing here
    // the user could flip.
    expect(find.text('camera.unsupported'), findsOneWidget);
    expect(find.text('camera.openSettings'), findsNothing);
    expect(find.text('camera.close'), findsOneWidget);

    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('an available camera opens the capture screen, which reports a '
      'refused open in place', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    CameraPlatform.instance = _FakeCameraPlatform(
      cameras: const [
        CameraDescription(
          name: 'webcam',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        ),
      ],
      // Enumeration succeeds, opening the device does not — the Windows privacy
      // toggle blocks the open, not the enumeration.
      openError: CameraException('CameraAccessDenied', 'denied'),
    );

    final (app, key) = host();
    await tester.pumpWidget(app);

    DesktopCameraDelegate(key).takePhoto();
    await tester.pumpAndSettle();

    expect(find.byKey(capture), findsOneWidget);
    // No dialog fired; the screen itself carries the explanation and the way out.
    expect(find.text('camera.blockedTitle'), findsNothing);
    expect(find.text('camera.failed'), findsOneWidget);
    expect(find.text('camera.openSettings'), findsOneWidget);

    key.currentState!.pop();
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;
  });

  test('the settings deep link follows the OS, and is absent elsewhere', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(cameraPrivacySettingsUri().toString(), 'ms-settings:privacy-webcam');

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(cameraPrivacySettingsUri()?.scheme, 'x-apple.systempreferences');

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(cameraPrivacySettingsUri(), isNull);
  });
}

/// Stands in for camera_windows: enumeration plus just enough of the open path
/// for the capture screen to build and tear down a controller.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({this.cameras = const [], this.error, this.openError});

  final List<CameraDescription> cameras;
  final Object? error;
  final Object? openError;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (error != null) throw error!;
    return cameras;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? mediaSettings,
  ) async {
    if (openError != null) throw openError!;
    return 1;
  }

  @override
  Future<void> dispose(int cameraId) async {}
}
