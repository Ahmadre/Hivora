import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Directory, Platform;

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

/// [args] are the process arguments the embedder hands to the Dart entrypoint.
/// Only Linux puts anything there we care about — see [_launchDeepLink].
Future<void> main(List<String> args) async {
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
        : HydratedStorageDirectory((await _stateDirectory()).path),
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
      initialLink: _launchDeepLink(args),
    ),
  );
}

/// Where HydratedBloc keeps its state.
///
/// The documents directory on every platform that has had it: that is where
/// this app's hydrated state has always lived, and moving it would silently
/// reset every stored filter and preference for everyone already using it.
///
/// Linux is the exception, and always uses the application-support directory,
/// because "the documents folder" is the wrong answer there twice over. It is
/// resolved through the XDG user directories, so a desktop without
/// xdg-user-dirs configured — a minimal window manager, a container, a freshly
/// created account — has none at all and the lookup throws before the app has
/// drawn a frame. And under Flatpak the app is only granted the user's
/// documents *read-only*, so even where the lookup succeeds the first write
/// would not. Application support is XDG_DATA_HOME, which path_provider creates
/// if it is missing and the sandbox always makes writable; Linux is new enough
/// that there is nothing there to migrate.
///
/// The catch stays for the platforms that do use documents: none of them is
/// expected to fail, and falling back beats refusing to start.
Future<Directory> _stateDirectory() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return getApplicationSupportDirectory();
  }
  try {
    return await getApplicationDocumentsDirectory();
  } on MissingPlatformDirectoryException {
    return await getApplicationSupportDirectory();
  }
}

/// The `hinata://` link the app was launched with, if there is one.
///
/// Linux only, and it exists because of how deep links arrive there: the
/// `.desktop` file claims `x-scheme-handler/hinata`, so opening a link runs
/// `hinata hinata://auth-callback?…` and GApplication forwards that argv to the
/// instance already running. `app_links` learns of it through the resulting
/// `::command-line` signal — which is emitted *before* the plugins of a
/// cold-started process are registered, so the very first launch's link reaches
/// nothing. It is still in the process arguments, which is where this reads it.
///
/// Matched by scheme rather than by position: the same argument list carries
/// whatever the tooling passed (`flutter run` adds several), and https deep
/// links are handled by the browser on Linux, never by the app.
Uri? _launchDeepLink(List<String> args) {
  for (final arg in args) {
    final uri = Uri.tryParse(arg);
    if (uri != null && uri.scheme == 'hinata') return uri;
  }
  return null;
}
