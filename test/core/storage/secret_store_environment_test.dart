import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/storage/secret_store_environment.dart';

/// Which fix Hinata offers when it cannot keep a session.
///
/// The whole point of detecting this is that the two Linux failures look
/// identical from inside the app and have nothing in common outside it. A snap
/// user runs one `snap connect` line; a user on a bare window manager installs
/// a keyring. Handing either of them the other's instruction is worse than the
/// generic sentence, so the detection is pinned here rather than trusted.
void main() {
  /// Where a confined Hinata is executed from: inside its own `$SNAP` mount.
  const snapBinary = '/snap/hinata/42/bin/hinata';

  /// And where every other Linux build of it lives.
  const debBinary = '/usr/bin/hinata';

  group('resolveSecretStoreEnvironment', () {
    test('every non-Linux platform has nothing to advise', () {
      // Even with a full snap environment present: macOS/iOS/Android/Windows
      // secret stores are part of the OS, so there is no missing daemon and no
      // permission to connect. (A `SNAP*` variable can be inherited by anything
      // launched from a snap terminal — it must not turn a Mac into a snap.)
      final env = resolveSecretStoreEnvironment(
        isLinux: false,
        environment: const {
          'SNAP': '/snap/hinata/x1',
          'SNAP_NAME': 'hinata',
          'SNAP_INSTANCE_NAME': 'hinata',
        },
        executablePath: '/Applications/Hinata.app/Contents/MacOS/Hinata',
      );

      expect(env.remedy, SecretStoreRemedy.none);
      expect(env.isSnap, isFalse);
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).command,
        isNull,
        reason: 'a snap command shown outside a snap is a wrong answer',
      );
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).messageKey,
        'errors.sessionNotPersisted.generic',
      );
    });

    test('a plain Linux desktop is told about the keyring, not about snap', () {
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {'HOME': '/home/ada', 'DISPLAY': ':0'},
        executablePath: debBinary,
      );

      expect(env.remedy, SecretStoreRemedy.linuxKeyring);
      expect(env.isSnap, isFalse);
      expect(env.noticeFor(SecretStoreFailure.unreachable).command, isNull);
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).messageKey,
        'errors.sessionNotPersisted.keyring',
      );
    });

    test('inside a snap, the command names this snap', () {
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {
          'SNAP': '/snap/hinata/42',
          'SNAP_NAME': 'hinata',
          'SNAP_INSTANCE_NAME': 'hinata',
          'SNAP_REVISION': '42',
        },
        executablePath: snapBinary,
      );

      expect(env.remedy, SecretStoreRemedy.snapPermission);
      expect(env.isSnap, isTrue);
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).command,
        'snap connect hinata:password-manager-service',
      );
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).messageKey,
        'errors.sessionNotPersisted.snap',
      );
    });

    test('a parallel install gets its own instance name in the command', () {
      // `snap install --name hinata_work` — the interface is on the instance,
      // so `snap connect hinata:…` would fail with "snap not installed".
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {
          'SNAP': '/snap/hinata_work/42',
          'SNAP_NAME': 'hinata',
          'SNAP_INSTANCE_NAME': 'hinata_work',
        },
        executablePath: '/snap/hinata_work/42/bin/hinata',
      );

      expect(
        env.noticeFor(SecretStoreFailure.unreachable).command,
        'snap connect hinata_work:password-manager-service',
      );
    });

    test('SNAP alone is not evidence of confinement', () {
      // Plenty of build scripts export a variable called SNAP. Without a snap
      // name next to it this is a plain desktop, and gets the keyring advice.
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {'SNAP': '/opt/whatever'},
        executablePath: debBinary,
      );

      expect(env.remedy, SecretStoreRemedy.linuxKeyring);
    });

    test('a malformed name falls back to the published one', () {
      // Never interpolate un-vetted environment text into a command we ask
      // someone to paste into a root shell.
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {
          'SNAP': '/snap/hinata/42',
          'SNAP_INSTANCE_NAME': 'hinata; rm -rf ~',
          'SNAP_NAME': 'Hinata Desktop',
        },
        executablePath: snapBinary,
      );

      expect(env.remedy, SecretStoreRemedy.snapPermission);
      expect(env.snapInstanceName, isNull);
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).command,
        'snap connect hinata:password-manager-service',
      );
    });

    test('the instance name wins over the snap name', () {
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {
          'SNAP': '/snap/hinata_work/42',
          'SNAP_NAME': 'hinata',
          'SNAP_INSTANCE_NAME': 'hinata_work',
        },
        executablePath: '/snap/hinata_work/42/bin/hinata',
      );

      expect(env.snapInstanceName, 'hinata_work');
    });
  });

  group("someone else's snap variables", () {
    // snapd exports SNAP/SNAP_NAME/SNAP_INSTANCE_NAME and *every* descendant
    // inherits them. Launch the .deb, the AppImage, the Flatpak or
    // `flutter run -d linux` from the integrated terminal of the VS Code snap
    // and the whole set is sitting there, naming `code`. Believing it hands a
    // non-snap user `snap connect code:password-manager-service`, ready on the
    // clipboard: an instruction that cannot fix their keyring and, if it works
    // at all, grants their editor the login keyring instead.
    const codeSnap = {
      'SNAP': '/snap/code/175',
      'SNAP_NAME': 'code',
      'SNAP_INSTANCE_NAME': 'code',
    };

    test('a .deb launched from a snap terminal is not a snap', () {
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: codeSnap,
        executablePath: debBinary,
      );

      expect(env.remedy, SecretStoreRemedy.linuxKeyring);
      expect(env.snapInstanceName, isNull);
      expect(
        env.noticeFor(SecretStoreFailure.unreachable).command,
        isNull,
        reason: "never hand a user a command for someone else's snap",
      );
    });

    test('nor is a flatpak, an AppImage or a debug build', () {
      for (final binary in [
        '/app/bin/hinata', // flatpak
        '/tmp/.mount_Hinataxyz/usr/bin/hinata', // AppImage
        '/home/ada/dev/hinata-app/build/linux/x64/debug/bundle/hinata',
      ]) {
        final env = resolveSecretStoreEnvironment(
          isLinux: true,
          environment: codeSnap,
          executablePath: binary,
        );

        expect(env.remedy, SecretStoreRemedy.linuxKeyring, reason: binary);
      }
    });

    test('a sibling revision cannot claim the process', () {
      // String-prefix matching would let `/snap/hinata/4` swallow a binary out
      // of `/snap/hinata/42`. The boundary is a path component.
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {'SNAP': '/snap/hinata/4', 'SNAP_NAME': 'hinata'},
        executablePath: snapBinary,
      );

      expect(env.remedy, SecretStoreRemedy.linuxKeyring);
    });

    test('a relative SNAP proves nothing', () {
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {'SNAP': '.', 'SNAP_NAME': 'hinata'},
        executablePath: './build/hinata',
      );

      expect(env.remedy, SecretStoreRemedy.linuxKeyring);
    });

    test('a trailing slash on SNAP still matches our own binary', () {
      final env = resolveSecretStoreEnvironment(
        isLinux: true,
        environment: const {'SNAP': '/snap/hinata/42/', 'SNAP_NAME': 'hinata'},
        executablePath: snapBinary,
      );

      expect(env.remedy, SecretStoreRemedy.snapPermission);
    });
  });

  group('classifySecretStoreFailure', () {
    // The plugin distinguishes these two and the app has to keep them apart:
    // "locked" means the Secret Service answered, so no permission is missing
    // and no daemon needs installing.
    test('a locked collection is not an unreachable store', () {
      expect(
        classifySecretStoreFailure(
          PlatformException(code: 'KeyringLocked', message: 'KeyringLocked'),
        ),
        SecretStoreFailure.locked,
      );
    });

    test('a service that never answered is unreachable', () {
      expect(
        classifySecretStoreFailure(
          PlatformException(
            code: 'Libsecret error',
            message: 'secret_service_get_sync: Cannot autolaunch D-Bus',
          ),
        ),
        SecretStoreFailure.unreachable,
      );
    });

    test('anything unrecognised falls back to unreachable', () {
      // The conservative answer: it keeps the notice on the environment's own
      // remedy instead of inventing a keyring on a system that has none.
      expect(
        classifySecretStoreFailure(Exception('nope')),
        SecretStoreFailure.unreachable,
      );
      expect(
        classifySecretStoreFailure(
          PlatformException(code: 'StorageError', message: 'boom'),
        ),
        SecretStoreFailure.unreachable,
      );
    });
  });
}
