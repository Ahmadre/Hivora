import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/app.dart' show shouldAnnounceMemoryOnlySession;
import 'package:hinata/core/blocs/auth_bloc.dart' show AuthStatus;
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/storage/secret_store_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Hinata does on a system whose secret store is not there.
///
/// Three of them, and the first two behave identically from in here: a Linux
/// desktop with no keyring daemon, and a strictly confined snap whose
/// `password-manager-service` interface has not been connected. In both,
/// libsecret does not politely answer `null` — every call *throws*. That is the
/// whole difficulty: an unguarded `read` at boot takes the app down before it
/// has drawn a frame, and an unguarded `delete` takes down sign-out and "forget
/// this server" instead. The third is a keyring that is merely *locked*, which
/// throws too but means something completely different: the store is right
/// there, and none of the fixes the other two need apply.
///
/// So these tests are mostly about things NOT happening: no throw out of the
/// boot sequence, no throw out of sign-out, no token written anywhere a
/// keyring-less system could have read it back from, no advice given to someone
/// it cannot help, and no round trip to a healthy store that nobody asked for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const server = 'https://server.test';

  /// A secret store that behaves the way libsecret does with no Secret Service
  /// on the bus: it does not return null, it raises. The plugin turns that into
  /// a [PlatformException] before Dart sees it, which is what this stands in
  /// for — with the code and message version 3.0.2 actually produces for a
  /// failed `secret_service_get_sync`.
  const dead = _DeadSecretStore();

  /// A Secret Service that answers, and refuses because the collection is
  /// locked. Reachable — which is the entire point of keeping it apart.
  const locked = _LockedSecretStore();

  /// Linux, no snap: the environment of the desktop this failure mode was
  /// reported from. Injected rather than detected, because the tests run on the
  /// developer's machine and `Platform.isLinux` is false there.
  const linuxDesktop = SecretStoreEnvironment(
    remedy: SecretStoreRemedy.linuxKeyring,
  );

  /// Linux inside a strictly confined snap.
  const confinedSnap = SecretStoreEnvironment(
    remedy: SecretStoreRemedy.snapPermission,
    snapInstanceName: 'hinata',
  );

  const snapCommand = 'snap connect hinata:password-manager-service';

  /// Prefs seeded as they look after the user has connected [server] once.
  Future<SharedPreferences> prefsWithServer() async {
    SharedPreferences.setMockInitialValues({
      'server_url': server,
      'servers.v1': '[{"url":"$server"}]',
    });
    return SharedPreferences.getInstance();
  }

  Future<SharedPreferences> emptyPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  /// Prefs as a build from before multi-server left them: one `server_url` and
  /// two tokens in cleartext, no server list.
  Future<SharedPreferences> legacyPrefs() async {
    SharedPreferences.setMockInitialValues({
      'server_url': server,
      'access_token': 'legacy-access',
      'refresh_token': 'legacy-refresh',
    });
    return SharedPreferences.getInstance();
  }

  /// Everything currently in SharedPreferences, as one searchable blob.
  String plaintext(SharedPreferences prefs) =>
      prefs.getKeys().map((k) => '$k=${prefs.get(k)}').join(' ');

  group('boot', () {
    test('a launch with nothing saved never touches the store', () async {
      // There is no availability probe, on any platform, and this is the test
      // that keeps it that way. A read is not free on Linux: the plugin unlocks
      // a locked collection before every lookup, which raises the desktop's
      // keyring-password dialog. A probe therefore put a password box on screen
      // the moment the app opened — for snap users whose permission was granted
      // and whose keyring was simply locked at login, i.e. people with nothing
      // wrong with their setup, every single launch.
      for (final environment in [
        confinedSnap,
        linuxDesktop,
        SecretStoreEnvironment.plain,
      ]) {
        final store = _WorkingSecretStore();
        final storage = AppStorage(
          await emptyPrefs(),
          store,
          secretStore: environment,
        );

        await expectLater(storage.restore(), completes);

        expect(store.reads, 0, reason: '${environment.remedy}');
        expect(store.writes, 0, reason: '${environment.remedy}');
        expect(storage.sessionIsMemoryOnly, isFalse);
        expect(storage.secretStoreNotice, isNull);
      }
    });

    test('a healthy snap is never told to connect anything', () async {
      // The snap this app actually ships: the interface is connected, the
      // keyring answers. Nothing about being a snap may produce a notice on its
      // own — only a store that refused can.
      final store = _WorkingSecretStore({
        'access_token::$server': 'access-1',
        'refresh_token::$server': 'refresh-1',
      });
      final storage = AppStorage(
        await prefsWithServer(),
        store,
        secretStore: confinedSnap,
      );

      await storage.restore();

      expect(storage.accessToken, 'access-1');
      expect(storage.sessionIsMemoryOnly, isFalse);
      expect(storage.secretStoreNotice, isNull);
      expect(store.writes, 0, reason: 'reading a session must not write one');
    });

    test('a returning user is signed out, not crashed', () async {
      // The reported symptom: tokens were written on a previous run, the reads
      // throw, and the app lands on the login screen. It must land there rather
      // than die on the way, and it must know why it landed there.
      final storage = AppStorage(
        await prefsWithServer(),
        dead,
        secretStore: linuxDesktop,
      );

      await expectLater(storage.restore(), completes);
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
      expect(storage.sessionIsMemoryOnly, isTrue);
      expect(
        storage.secretStoreNotice!.messageKey,
        'errors.sessionNotPersisted.keyring',
      );
      expect(storage.secretStoreNotice!.command, isNull);
    });

    test('a returning snap user gets the one command that fixes it', () async {
      final storage = AppStorage(
        await prefsWithServer(),
        dead,
        secretStore: confinedSnap,
      );

      await expectLater(storage.restore(), completes);
      expect(storage.accessToken, isNull);
      expect(storage.sessionIsMemoryOnly, isTrue);
      expect(
        storage.secretStoreNotice!.messageKey,
        'errors.sessionNotPersisted.snap',
      );
      expect(storage.secretStoreNotice!.command, snapCommand);
    });

    test('a locked keyring in a snap is not a missing permission', () async {
      // The permission is granted — that is *why* the store could answer at all
      // — and the login keyring is simply locked. Advising `snap connect` here
      // sends the user to App Center to look at a switch that is already on,
      // and leaves them with no working instruction at the exact moment the
      // message was supposed to help.
      final storage = AppStorage(
        await prefsWithServer(),
        locked,
        secretStore: confinedSnap,
      );

      await storage.restore();

      expect(storage.sessionIsMemoryOnly, isTrue);
      expect(
        storage.secretStoreNotice!.messageKey,
        'errors.sessionNotPersisted.locked',
      );
      expect(
        storage.secretStoreNotice!.command,
        isNull,
        reason: 'never offer a command for a permission that is already there',
      );
    });

    test('a locked keyring on a bare desktop says the same', () async {
      // Nothing to install either: the daemon is running, it is locked.
      final storage = AppStorage(
        await prefsWithServer(),
        locked,
        secretStore: linuxDesktop,
      );

      await storage.restore();

      expect(
        storage.secretStoreNotice!.messageKey,
        'errors.sessionNotPersisted.locked',
      );
    });
  });

  group('signing in without a secret store', () {
    test('the session works for this run only', () async {
      final storage = AppStorage(
        await prefsWithServer(),
        dead,
        secretStore: linuxDesktop,
      );
      await storage.restore();

      await expectLater(
        storage.setTokens(access: 'access-2', refresh: 'refresh-2'),
        completes,
      );

      // Sign-in worked: the app can make authenticated requests all session.
      expect(storage.accessToken, 'access-2');
      expect(storage.refreshToken, 'refresh-2');
      // And it knows the session is memory-deep only.
      expect(storage.sessionIsMemoryOnly, isTrue);
    });

    test('a first run inside a snap finds out at the first write', () async {
      // Nothing saved, so boot has nothing to fail on and stays quiet. The
      // answer arrives at the write, which is the moment it becomes true — and
      // the moment the error is in hand to say *why*.
      final storage = AppStorage(
        await emptyPrefs(),
        dead,
        secretStore: confinedSnap,
      );
      await storage.restore();
      expect(storage.sessionIsMemoryOnly, isFalse);

      await storage.setServerUrl(server);
      await storage.setTokens(access: 'access-6', refresh: 'refresh-6');

      expect(storage.accessToken, 'access-6');
      expect(storage.sessionIsMemoryOnly, isTrue);
      expect(
        storage.secretStoreNotice!.messageKey,
        'errors.sessionNotPersisted.snap',
      );
      expect(storage.secretStoreNotice!.command, snapCommand);
    });

    test('nothing lands in plaintext as a consolation prize', () async {
      // The tempting "fallback" is SharedPreferences, and it is the one thing
      // that must never happen: a refresh token in a world-readable file, on
      // exactly the systems that just said they have nowhere safe to put it.
      final prefs = await prefsWithServer();
      final storage = AppStorage(prefs, dead, secretStore: linuxDesktop);
      await storage.restore();

      await storage.setTokens(access: 'access-3', refresh: 'refresh-3');

      expect(plaintext(prefs), isNot(contains('access-3')));
      expect(plaintext(prefs), isNot(contains('refresh-3')));
    });

    test('a store that comes back clears the flag', () async {
      // The user connects the snap interface (or starts a keyring) and signs in
      // again without restarting. The next successful write is the evidence.
      final storage = AppStorage(
        await prefsWithServer(),
        _WorkingSecretStore(),
        secretStore: linuxDesktop,
      );
      await storage.restore();
      expect(storage.sessionIsMemoryOnly, isFalse);

      await storage.setTokens(access: 'access-4', refresh: 'refresh-4');

      expect(storage.sessionIsMemoryOnly, isFalse);
      expect(storage.secretStoreNotice, isNull);
    });
  });

  group('upgrading from a build that stored tokens in plaintext', () {
    test('a healthy store ends the plaintext copy on the spot', () async {
      // The tokens used to be parked in the *per-server* prefs keys and lifted
      // a moment later, which meant this run wrote a refresh token into
      // cleartext even on a desktop whose keyring was working perfectly — and a
      // crash in the window between the two steps left it there for good. They
      // now go straight to the store.
      final prefs = await legacyPrefs();
      final store = _WorkingSecretStore();
      final storage = AppStorage(prefs, store, secretStore: linuxDesktop);

      await storage.restore();

      expect(storage.accessToken, 'legacy-access');
      expect(storage.refreshToken, 'legacy-refresh');
      expect(store.items['refresh_token::$server'], 'legacy-refresh');
      expect(plaintext(prefs), isNot(contains('legacy-')));
      expect(
        store.writes,
        2,
        reason: 'one write per token, with no detour through prefs',
      );
    });

    test('an unreachable store keeps the copy that already existed', () async {
      // This is the honest version of the guarantee. The copy under the old
      // global key was written by an *older build of this app*, on a system
      // that had a working store at the time; deleting it would sign the user
      // out of a session that a keyring unlocked tomorrow would have kept. So
      // it is re-keyed to the server it belongs to and retried — never
      // duplicated, and never created where none existed.
      final prefs = await legacyPrefs();
      final storage = AppStorage(prefs, dead, secretStore: linuxDesktop);

      await storage.restore();

      expect(prefs.getString('refresh_token'), isNull);
      expect(prefs.getString('refresh_token::$server'), 'legacy-refresh');
      expect(
        'legacy-refresh'.allMatches(plaintext(prefs)).length,
        1,
        reason: 'one copy, not two',
      );
      expect(storage.sessionIsMemoryOnly, isTrue);
    });

    test('and it is gone the first launch the store works', () async {
      // The retry that justifies keeping it: same prefs, next launch, keyring
      // unlocked.
      final prefs = await legacyPrefs();
      await AppStorage(prefs, dead, secretStore: linuxDesktop).restore();
      expect(plaintext(prefs), contains('legacy-refresh'));

      final store = _WorkingSecretStore();
      final storage = AppStorage(prefs, store, secretStore: linuxDesktop);
      await storage.restore();

      expect(plaintext(prefs), isNot(contains('legacy-')));
      expect(store.items['access_token::$server'], 'legacy-access');
      expect(storage.refreshToken, 'legacy-refresh');
      expect(storage.sessionIsMemoryOnly, isFalse);
    });
  });

  group('leaving', () {
    test('signing out does not throw when delete fails', () async {
      // This used to escape straight past the `emit(unauthenticated)` that
      // follows it, stranding the user inside the authenticated shell with a
      // session that had already been dropped from memory.
      final storage = AppStorage(
        await prefsWithServer(),
        dead,
        secretStore: linuxDesktop,
      );
      await storage.restore();
      await storage.setTokens(access: 'access-5', refresh: 'refresh-5');

      await expectLater(storage.clearTokens(), completes);

      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    });

    test('forgetting a server does not throw either', () async {
      // Same unguarded delete, one screen over — and worse here, because the
      // server list is rewritten *before* it, so an exception left the app
      // pointed at a server it no longer listed.
      final prefs = await prefsWithServer();
      final storage = AppStorage(prefs, dead, secretStore: linuxDesktop);
      await storage.restore();

      await expectLater(storage.removeServer(server), completes);

      expect(storage.servers, isEmpty);
      expect(storage.serverUrl, isNull);
    });
  });

  group('when the notice is raised', () {
    // The bug this rule fixes is one of omission. The notice used to hang off
    // the *authenticated* branch alone, so the person it helps most — signed
    // out at boot because the saved tokens could not be read — got a login
    // screen and no reason for it, every single morning.
    bool announce(AuthStatus status, {bool already = false}) =>
        shouldAnnounceMemoryOnlySession(
          status: status,
          sessionIsMemoryOnly: true,
          alreadyAnnounced: already,
        );

    test('both settled outcomes get the explanation', () {
      expect(announce(AuthStatus.authenticated), isTrue);
      expect(announce(AuthStatus.unauthenticated), isTrue);
    });

    test('nothing is said mid-flight', () {
      // A spinner or a disabled form, with no settled route to raise a toast
      // over — and, for the 2FA challenge, the worst possible moment to
      // interrupt with storage advice.
      expect(announce(AuthStatus.unknown), isFalse);
      expect(announce(AuthStatus.authenticating), isFalse);
      expect(announce(AuthStatus.twoFactorRequired), isFalse);
    });

    test('a healthy store is never mentioned at all', () {
      expect(
        shouldAnnounceMemoryOnlySession(
          status: AuthStatus.authenticated,
          sessionIsMemoryOnly: false,
          alreadyAnnounced: false,
        ),
        isFalse,
      );
    });

    test('it is said once per launch, not once per sign-in', () {
      expect(announce(AuthStatus.authenticated, already: true), isFalse);
      expect(announce(AuthStatus.unauthenticated, already: true), isFalse);
    });
  });
}

/// A store that refuses every call, the way libsecret does.
abstract class _RefusingSecretStore extends FlutterSecureStorage {
  const _RefusingSecretStore();

  /// The [PlatformException] the plugin would raise.
  Never refuse();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => refuse();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => refuse();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => refuse();
}

/// libsecret with nothing on the other end of the bus.
///
/// `flutter_secure_storage_linux` 3.0.2 reports this as `Libsecret error` with
/// the failed call in the message — no keyring daemon at all, or the bus name
/// denied by AppArmor inside an unconnected snap. Which of those two it is, the
/// error cannot say; the *environment* can, and that is the split the app
/// relies on.
class _DeadSecretStore extends _RefusingSecretStore {
  const _DeadSecretStore();

  @override
  Never refuse() => throw PlatformException(
    code: 'Libsecret error',
    message: 'secret_service_get_sync: Cannot autolaunch D-Bus session',
  );
}

/// A Secret Service that answered and said no: the default collection is
/// locked, or the unlock was declined. `KeyringLocked` is reserved for exactly
/// this, so nothing is missing and nothing needs connecting.
class _LockedSecretStore extends _RefusingSecretStore {
  const _LockedSecretStore();

  @override
  Never refuse() =>
      throw PlatformException(code: 'KeyringLocked', message: 'KeyringLocked');
}

/// A store that works — and counts what it was asked to do, so a test can say
/// "and it was never called".
class _WorkingSecretStore extends FlutterSecureStorage {
  _WorkingSecretStore([Map<String, String>? initial]) : _items = {...?initial};

  final Map<String, String> _items;
  int reads = 0;
  int writes = 0;

  Map<String, String> get items => Map.unmodifiable(_items);

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    return _items[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    if (value == null) {
      _items.remove(key);
    } else {
      _items[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _items.remove(key);
  }
}
