/// The notification the app was launched from is followed once, not forever.
///
/// The report this comes from: the macOS build off the App Store opened on a
/// months-old comment — long since deleted, so on "this comment no longer
/// exists" — every single time it was started. The OS keeps answering "the app
/// was launched from this notification" for one that is still sitting in
/// Notification Center, whether or not that start had anything to do with it.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/notifications/fcm_service.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStorage storage;
  late List<String> opened;

  /// A fresh service over the *same* storage — one app start.
  FcmService boot() => FcmService(
    apiClient: _FakeApi(),
    storage: storage,
    onDeepLink: opened.add,
  );

  Future<void> restart() async {
    storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    opened = [];
    await restart();
  });

  const launch = RemoteMessage(
    messageId: 'msg-1',
    data: {'link': '/issues/HIN-4?comment=c1'},
  );

  test('opens the link of the notification it was launched from', () async {
    await boot().openNotification(launch);

    expect(opened, ['/issues/HIN-4?comment=c1']);
  });

  test('does not open it again on the next start', () async {
    await boot().openNotification(launch);
    opened.clear();

    // A new process, the same device — and the OS hands back the same
    // notification as the one the app was "launched from".
    await restart();
    await boot().openNotification(launch);

    expect(opened, isEmpty);
  });

  test('still opens the next, different notification', () async {
    await boot().openNotification(launch);
    opened.clear();

    await restart();
    await boot().openNotification(
      const RemoteMessage(messageId: 'msg-2', data: {'link': '/issues/HIN-9'}),
    );

    expect(opened, ['/issues/HIN-9']);
  });

  test('remembers it before following the link', () async {
    // A launch that dies on the way to the route must not be repeated by every
    // launch after it — which is the same loop, only worse.
    await boot().openNotification(launch);

    expect(storage.launchNotificationId, 'msg-1');
  });

  test('follows a notification that carries no id at all', () async {
    // Nothing to remember it by, so it cannot be deduplicated. A link that
    // arrives once too often beats a tap that does nothing.
    const anonymous = RemoteMessage(data: {'link': '/issues/HIN-7'});
    await boot().openNotification(anonymous);
    await restart();
    await boot().openNotification(anonymous);

    expect(opened, ['/issues/HIN-7', '/issues/HIN-7']);
  });

  test('a tap delivered twice by the OS only navigates once', () async {
    // The other door: on Apple platforms the same tap can arrive both as the
    // launch message and through onMessageOpenedApp. Both go through the same
    // gate, so it does not matter which one a platform repeats itself on.
    final service = boot();
    await service.openNotification(launch);
    await service.openNotification(launch);

    expect(opened, ['/issues/HIN-4?comment=c1']);
  });

  test('ignores a payload that names no route', () async {
    await boot().openNotification(
      const RemoteMessage(messageId: 'msg-3', data: {'link': '/'}),
    );
    await boot().openNotification(
      const RemoteMessage(messageId: 'msg-4', data: <String, dynamic>{}),
    );

    expect(opened, isEmpty);
  });
}

class _FakeApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
