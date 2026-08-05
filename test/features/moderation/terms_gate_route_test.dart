import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The content-terms acceptance record.
///
/// Google's UGC policy wants users to accept the terms before they can create
/// content, and its moderation guidance says the step must not be skippable —
/// which in this app is a router gate that fires while this record says "no".
/// So what the record answers, and who it answers for, IS the gate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStorage> storageFor(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    FlutterSecureStorage.setMockInitialValues({});
    return AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  }

  test('a fresh user on a known server has not accepted', () async {
    final storage = await storageFor({'server_url': 'https://a.test'});
    expect(storage.termsAcceptedBy('user-1'), isFalse);
  });

  test('acceptance is remembered for that user', () async {
    final storage = await storageFor({'server_url': 'https://a.test'});
    await storage.setTermsAccepted('user-1');
    expect(storage.termsAcceptedBy('user-1'), isTrue);
  });

  test('acceptance does not carry to another user on the same device', () async {
    // A shared tablet: the next colleague to sign in has agreed to nothing.
    final storage = await storageFor({'server_url': 'https://a.test'});
    await storage.setTermsAccepted('user-1');
    expect(storage.termsAcceptedBy('user-2'), isFalse);
  });

  test('acceptance does not carry to another server', () async {
    // Self-hosted: agreeing to one instance's rules says nothing about another's.
    final storage = await storageFor({'server_url': 'https://a.test'});
    await storage.setTermsAccepted('user-1');
    await storage.setCurrentServer('https://b.test');
    expect(storage.termsAcceptedBy('user-1'), isFalse);
  });

  test('is suppressed before a server is chosen', () async {
    // Mid-boot there is nothing to agree to yet; the gate must not fire into a
    // screen that has no server to name.
    final storage = await storageFor({});
    expect(storage.termsAcceptedBy('user-1'), isTrue);
  });
}
