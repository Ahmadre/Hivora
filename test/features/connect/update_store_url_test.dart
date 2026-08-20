import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/connect/update_required_screen.dart';

/// Which store link the update gate offers, per platform.
///
/// This is the screen a user is trapped on when their client is too old: the
/// only way forward is that button. A platform the resolver does not know about
/// gets a dead end — which is exactly what Windows and Linux had before they
/// were given a field of their own.
void main() {
  const meta = ServerMeta(
    serverVersion: '1.0.0',
    minAppVersion: '2.0.0',
    setupCompleted: true,
    iosStoreUrl: 'https://apps.apple.com/app/id6781889251',
    androidStoreUrl: 'https://play.google.com/store/apps/details?id=com.example',
    macosStoreUrl: 'https://apps.apple.com/app/id6781889251',
    windowsStoreUrl: 'https://apps.microsoft.com/detail/9N5NVNPKBBLR',
    linuxStoreUrl: 'https://flathub.org/apps/com.example.app',
  );

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('every platform that has a storefront resolves its own listing', () {
    final expected = {
      TargetPlatform.iOS: meta.iosStoreUrl,
      TargetPlatform.android: meta.androidStoreUrl,
      TargetPlatform.macOS: meta.macosStoreUrl,
      TargetPlatform.windows: meta.windowsStoreUrl,
      TargetPlatform.linux: meta.linuxStoreUrl,
    };
    for (final entry in expected.entries) {
      debugDefaultTargetPlatformOverride = entry.key;
      expect(
        storeUrlForPlatform(meta),
        entry.value,
        reason: 'wrong listing for ${entry.key}',
      );
    }
  });

  test('a platform with no configured listing offers no link', () {
    // Blank is how an operator says "I do not publish there". The gate then
    // shows its explanation without a button that would go nowhere.
    const blank = ServerMeta(
      serverVersion: '1.0.0',
      minAppVersion: '2.0.0',
      setupCompleted: true,
    );
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(storeUrlForPlatform(blank), isNull, reason: '$platform');
    }
    expect(storeUrlForPlatform(null), isNull);
  });

  test('whitespace is not a link', () {
    const padded = ServerMeta(
      serverVersion: '1.0.0',
      minAppVersion: '2.0.0',
      setupCompleted: true,
      windowsStoreUrl: '   ',
      linuxStoreUrl: '\n',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(storeUrlForPlatform(padded), isNull);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(storeUrlForPlatform(padded), isNull);
  });

  test('a surrounding-space URL is still used, trimmed', () {
    const padded = ServerMeta(
      serverVersion: '1.0.0',
      minAppVersion: '2.0.0',
      setupCompleted: true,
      linuxStoreUrl: '  https://flathub.org/apps/com.example.app  ',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      storeUrlForPlatform(padded),
      'https://flathub.org/apps/com.example.app',
    );
  });
}
