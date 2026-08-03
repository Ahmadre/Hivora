import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/repositories/repositories.dart';
import 'core/notifications/fcm_service.dart';
import 'core/platform/desktop_camera_delegate.dart';
import 'core/router/app_router.dart' show rootNavigatorKey;
import 'core/storage/app_storage.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const screenshotMode = bool.fromEnvironment('SCREENSHOT_MODE');

  // High refresh rate. Android renders the Flutter surface at the panel's
  // *default* mode (usually 60 Hz) unless the app explicitly opts into the
  // highest supported mode — which is why static screens (e.g. the dashboard)
  // sit at 60 Hz while continuous glass animations opportunistically boost to
  // 120. Requesting `setHighRefreshRate` pins the surface to the fastest mode
  // at the current resolution so the whole app runs at 120 Hz uniformly. iOS/
  // macOS are already covered by CADisableMinimumFrameDurationOnPhone in
  // Info.plist. Guarded: never let this block startup on any device.
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }

  // Warm up the Lucide icon module on this shallow call stack. On Flutter web's
  // dev compiler (DDC) the first access to a symbol in this ~1600-icon library
  // triggers a deep `initializeAndLinkLibrary` link step. If that first access
  // happens deep inside the cold widget-mount stack (the login screen's very
  // first Icon, in ServerSelectorButton) the link recursion overflows the JS
  // stack — throwing a StackOverflowError that the widgets error boundary paints
  // as a red box. Linking the module here, before runApp, makes every later
  // access a cheap cache hit. Release builds (dart2js/wasm) have no such lazy
  // linker, so this is a no-op there; the read keeps it from being tree-shaken.
  // Only web DDC (debug) has the lazy icon-module linker this works around; gate
  // it so it doesn't run on native/release startup where it's dead code.
  if (kIsWeb && kDebugMode && LucideIcons.server.codePoint == 0) {
    debugPrint('lucide warm-up');
  }

  // Firebase (push). Skipped on web — no web Firebase app is configured — and
  // guarded so a misconfiguration never blocks app startup. The background
  // handler must be registered at the top level before runApp.
  // Store-screenshot builds (`--dart-define=SCREENSHOT_MODE=true`) skip Firebase
  // entirely so the OS never raises the notification-permission prompt over the
  // screen being captured. No effect on normal/release builds.
  if (!kIsWeb && !screenshotMode) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }

  // Clean path-based URLs on the web (e.g. /invite instead of /#/invite). No-op
  // off the web. Email deep links and SSO callbacks rely on this.
  usePathUrlStrategy();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            (await getApplicationDocumentsDirectory()).path,
          ),
  );

  // Pre-warm the liquid-glass shaders so the first frame of the bottom nav
  // doesn't flash. Guarded: a failure here must never block app startup.
  // initialize() also pre-warms the ProgressiveBlur shader (the app bar's
  // single-pass graduated backdrop blur), so no separate preload is needed.
  try {
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  } catch (_) {}

  final storage = await AppStorage.create();

  // Store-screenshot tablet captures (iPad, Android 10") are taken in LANDSCAPE.
  // A simulator/emulator can't be rotated reliably, so the harness sets a
  // `screenshot_landscape` pref and the app pins the orientation itself. No-op
  // in normal use (the pref is absent).
  if (screenshotMode && storage.screenshotLandscape) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // Desktop has no OS-provided capture UI, so image_picker's desktop
  // implementations refuse ImageSource.camera unless we hand them one. No-op on
  // Android/iOS/web, where the platform handles the camera itself.
  installDesktopCameraDelegate(rootNavigatorKey);

  final apiClient = ApiClient(storage);
  final repositories = HinataRepositories(apiClient);

  runApp(
    HinataApp(
      storage: storage,
      apiClient: apiClient,
      repositories: repositories,
    ),
  );
}
