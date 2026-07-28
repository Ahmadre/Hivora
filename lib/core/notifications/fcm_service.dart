import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

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
    required void Function(String link) onDeepLink,
  }) : _api = apiClient,
       _onDeepLink = onDeepLink;

  final ApiClient _api;
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

  Future<void> start() async {
    if (_started || !_supported) return;
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
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_route);
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
      if (initial != null) _route(initial);
    } catch (e) {
      debugPrint('FCM getInitialMessage routing failed: $e');
    }
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
        await _api.delete('/api/v1/me/devices/$token');
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
      default:
        return 'other';
    }
  }
}
