import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../storage/app_storage.dart';
import 'wns_channel.dart';

/// Background isolate handler. Notification messages are rendered by the OS when
/// the app is backgrounded/terminated; this entry point exists so data payloads
/// don't crash and so FCM keeps delivering. Must be a top-level/static function
/// annotated for the AOT tree-shaker.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: the deep link is carried in message.data and handled when the user
  // taps the notification (onMessageOpenedApp / getInitialMessage).
}

/// Owns the device's FCM lifecycle: request permission, fetch + register the
/// token with the server (re-registering on refresh), and route notification
/// taps to the in-app deep link. Started when the user signs in, stopped on
/// sign-out. A no-op on web (no web Firebase app is configured).
class FcmService {
  FcmService({
    required ApiClient apiClient,
    required AppStorage storage,
    required void Function(String link) onDeepLink,
  }) : _api = apiClient,
       _storage = storage,
       _onDeepLink = onDeepLink;

  final ApiClient _api;
  final AppStorage _storage;
  final void Function(String link) _onDeepLink;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _currentToken;
  bool _started = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Windows has no Firebase implementation, so it registers a WNS channel URI
  /// instead of an FCM token. The gateway routes on the shape of that value, so
  /// nothing else in the pipeline changes.
  bool get _usesWns =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> start() async {
    if (_started) return;
    if (_usesWns) {
      _started = true;
      final uri = await const WnsChannel().getChannelUri();
      // Unpackaged builds have no package identity and therefore no channel —
      // that is expected, not a failure.
      if (uri != null) await _register(uri);
      return;
    }
    if (!_supported) return;
    _started = true;
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // Apple platforms must have an APNs token before an FCM token resolves.
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        await messaging.getAPNSToken();
      }
      // Let a tapped notification show its banner/alert even while the app is
      // already in the foreground on iOS/macOS (Android never surfaces FCM
      // notification-type messages in the foreground regardless of this flag).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await messaging.getToken();
      if (token != null) await _register(token);
      _tokenRefreshSub = messaging.onTokenRefresh.listen(_register);
    } catch (e) {
      debugPrint('FCM start failed: $e');
    }

    // Wire up background-tap routing independently of the block above: a failure
    // fetching a token or registering a device must never skip this — otherwise
    // every later background-tap for the rest of this app session would silently
    // stop routing too.
    //
    // The cold-start tap (getInitialMessage) is deliberately NOT handled here.
    // It is consumed once, early, via handleInitialMessage() from app start —
    // independent of sign-in and of the slow token handshake above — so a
    // slow/hanging APNs+token resolution can't defer (or drop) the launch deep
    // link, which used to land the user on /dashboard instead of the target.
    try {
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(openNotification(message)),
      );
    } catch (e) {
      debugPrint('FCM onMessageOpenedApp subscription failed: $e');
    }
  }

  /// Routes a notification tap that launched the app from a fully terminated
  /// state (cold start). Call this once, as early as possible at app start —
  /// NOT gated behind sign-in or the token registration in [start] — so the
  /// launch deep link is read the instant Firebase is ready, before the slow
  /// APNs + token handshake. The router's gate-parking then holds the link and
  /// restores it once the app finishes connecting/authenticating; a warm
  /// background tap is delivered via onMessageOpenedApp in [start] instead.
  Future<void> handleInitialMessage() async {
    if (!_supported) return;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) await openNotification(initial);
    } catch (e) {
      debugPrint('FCM getInitialMessage routing failed: $e');
    }
  }

  /// Follows [message]'s deep link — once per notification, ever.
  ///
  /// **Why once.** A tap is a single instruction to go somewhere, and the OS
  /// is entitled to keep repeating it. On macOS a notification that is still
  /// sitting in Notification Center comes back as the one the app was
  /// "launched from" on every later start, whether or not that start had
  /// anything to do with it: the App Store build opened on a months-old
  /// comment — long since deleted, so on "this comment no longer exists" —
  /// instead of on the dashboard, every time it was started. Both doors the
  /// OS can deliver a tap through go through here, so it does not matter
  /// which one a given platform repeats itself on.
  ///
  /// A second *genuine* tap on the same notification is not a thing to lose:
  /// tapping one takes it out of Notification Center.
  ///
  /// The id is recorded *before* the link is followed, so a launch that dies
  /// on the way to the route is not repeated by every launch after it — the
  /// same loop, only harder to get out of. A message with no id is followed
  /// every time it arrives: there is nothing to recognize it by, and a link
  /// that arrives once too often is a smaller failure than a notification tap
  /// that does nothing.
  ///
  /// Called by [handleInitialMessage] and by the `onMessageOpenedApp`
  /// subscription in [start]; visible so a test can drive it, since the OS
  /// half of both is exactly what a test cannot.
  @visibleForTesting
  Future<void> openNotification(RemoteMessage message) async {
    final id = message.messageId;
    if (id != null && id.isNotEmpty) {
      if (_storage.launchNotificationId == id) return;
      await _storage.setLaunchNotificationId(id);
    }
    _route(message);
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _openedSub?.cancel();
    _openedSub = null;
    final token = _currentToken;
    _currentToken = null;
    if (token != null) {
      try {
        // Body, not a path segment: a Windows registration is a WNS channel URI
        // (an https URL with `:`, `/` and `?`), which cannot be a path segment.
        await _api.delete('/api/v1/me/devices', body: {'token': token});
      } catch (_) {
        // Best-effort: the server prunes dead tokens on send anyway.
      }
    }
  }

  Future<void> _register(String token) async {
    _currentToken = token;
    if (kDebugMode) debugPrint('FCM token: $token');
    try {
      await _api.post(
        '/api/v1/me/devices',
        body: {'token': token, 'platform': _platform()},
      );
    } catch (e) {
      debugPrint('FCM token register failed: $e');
    }
  }

  void _route(RemoteMessage message) {
    final link = message.data['link'];
    // Only in-app routes (relative paths) are navigable; guard like the other
    // deep-link call sites so a stray/legacy payload (e.g. a bare "/") can't
    // throw `no routes for location` instead of resolving to a real screen.
    if (link is String && link.startsWith('/') && link.length > 1) {
      _onDeepLink(link);
    }
  }

  String _platform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      default:
        return 'other';
    }
  }
}
