import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows Push Notification Services channel.
///
/// Firebase Cloud Messaging has no Windows implementation, so the Windows build
/// registers a WNS *channel URI* where Android/iOS/macOS register an FCM token.
/// The URI is minted natively by the runner (windows/runner/wns_channel.cpp)
/// and handed over this channel.
///
/// Everything here degrades to `null` rather than throwing: WNS needs package
/// identity, so a plain `flutter run` (unpackaged) legitimately has no channel,
/// and that must not look like an error.
class WnsChannel {
  const WnsChannel();

  static const MethodChannel _channel = MethodChannel('hinata/wns');

  /// Routes a notification the user clicked.
  ///
  /// Two paths, because a click either activates the running app or launches
  /// it: while running, the runner pushes the link over `onDeepLink`; on a cold
  /// start the link is buffered natively until [initialDeepLink] drains it.
  /// Same split as the FCM side (`onMessageOpenedApp` vs `getInitialMessage`).
  void listenForDeepLinks(void Function(String link) onLink) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final link = call.arguments;
        // Only in-app routes are navigable — same guard as the FCM path, so a
        // stray payload cannot throw "no routes for location".
        if (link is String && link.startsWith('/') && link.length > 1) {
          onLink(link);
        }
      }
      return null;
    });
  }

  /// The link of a notification whose click launched the app, if any.
  Future<String?> initialDeepLink() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return null;
    try {
      final link = await _channel.invokeMethod<String>('getInitialDeepLink');
      if (link == null || !link.startsWith('/') || link.length <= 1) {
        return null;
      }
      return link;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('WNS initial deep link unavailable: ${e.code}');
      return null;
    }
  }

  /// The device's channel URI, or null when unavailable.
  ///
  /// Microsoft rotates these and they expire after 30 days, so the app asks for
  /// a fresh one on every start rather than caching it.
  Future<String?> getChannelUri() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return null;
    try {
      final uri = await _channel.invokeMethod<String>('getChannelUri');
      // Whether a channel could be minted is the single most useful datum when
      // Windows push does not work — but the URI is a device-specific endpoint,
      // so it stays out of release logs (same rule as the FCM token).
      if (kDebugMode) {
        debugPrint('WNS channel: ${uri == null || uri.isEmpty ? "none" : uri}');
      }
      if (uri == null || uri.isEmpty) return null;
      // Belt and braces: the gateway enforces this too, but a channel that is
      // not on notify.windows.com must never leave the device.
      final parsed = Uri.tryParse(uri);
      if (parsed == null ||
          parsed.scheme != 'https' ||
          !parsed.host.endsWith('.notify.windows.com')) {
        debugPrint('WNS: ignoring channel with unexpected host');
        return null;
      }
      return uri;
    } on MissingPluginException {
      // Runner without the channel (e.g. an older build) — not an error.
      return null;
    } on PlatformException catch (e) {
      debugPrint('WNS channel unavailable: ${e.code}');
      return null;
    }
  }
}
