import 'package:flutter/services.dart' show PlatformException;

/// Where the OS secret store can be missing, and what the user would have to do
/// about it.
///
/// Only Linux has a secret store that can simply not be there: tokens go through
/// libsecret to the freedesktop Secret Service, which is a *separate* daemon
/// (GNOME Keyring, KWallet) rather than something the OS guarantees the way the
/// Keychain, the Android keystore and the Windows credential store do. There are
/// two shapes of "not there", and they have completely different fixes — which
/// is the whole reason this type exists. Telling a user on a bare window manager
/// to run a `snap` command is worse than saying nothing.
enum SecretStoreRemedy {
  /// A platform whose secret store is part of the OS (iOS, macOS, Android,
  /// Windows, web). If it fails here there is no user-actionable fix to name,
  /// so the notice stays generic.
  none,

  /// Linux inside a strictly confined snap. The Secret Service lives on the
  /// session bus *outside* the sandbox, and the interface that reaches it
  /// (`password-manager-service`) carries `deny-auto-connection: true` — so a
  /// fresh install has the permission declared and not connected. One command
  /// (or one toggle in App Center) fixes it, permanently.
  snapPermission,

  /// Linux outside a snap: nothing is answering on the Secret Service bus name
  /// at all. A minimal window manager, a container, an SSH session into a
  /// desktop whose login keyring was never unlocked. The fix is a keyring.
  linuxKeyring,
}

/// What the secret store said when it refused — the half of the answer the
/// environment cannot supply.
///
/// [SecretStoreRemedy] describes the system; this describes the failure. Both
/// are needed, because the same snap has two entirely different problems: the
/// interface is not connected (nothing answers), or it is connected and the
/// login keyring is locked (something answers, and says so). Advising
/// `snap connect` for the second one sends the user to App Center to look at a
/// permission that is already on.
enum SecretStoreFailure {
  /// Nothing answered on the Secret Service bus name: no keyring daemon at all,
  /// or an AppArmor denial inside an unconnected snap. The environment decides
  /// which of those it is.
  unreachable,

  /// A Secret Service answered and refused because the collection is locked.
  /// Whatever the environment is, the store is reachable — so no permission is
  /// missing and no daemon needs installing.
  locked,
}

/// Reads the failure out of what the plugin threw.
///
/// `flutter_secure_storage_linux` 3.0.2 distinguishes the two cases in the
/// `PlatformException.code` and nowhere else: `SECRET_ERROR_IS_LOCKED` (and the
/// failed `secret_service_unlock_sync`) come back as `KeyringLocked`, while a
/// `secret_service_get_sync` that found nothing to talk to comes back as
/// `Libsecret error` with the call name in the message. 3.0.1 used to throw
/// `KeyringLocked` for both, which is why this used to be considered
/// unknowable; the pinned version knows.
///
/// Anything else — another platform's Keychain/keystore error, a plain
/// exception — is [SecretStoreFailure.unreachable]: it is the conservative
/// answer, because it keeps the notice on the environment's own remedy instead
/// of inventing a keyring on a system that has none.
SecretStoreFailure classifySecretStoreFailure(Object error) =>
    error is PlatformException && error.code == 'KeyringLocked'
    ? SecretStoreFailure.locked
    : SecretStoreFailure.unreachable;

/// The name in `packaging/linux/snap/snapcraft.yaml`, and therefore the prefix
/// of the `snap connect` line. Used only when the environment does not name a
/// usable one — see [resolveSecretStoreEnvironment].
const _defaultSnapName = 'hinata';

/// Snap instance names are `[a-z0-9-]`, optionally followed by `_<instance-key>`
/// for a parallel install (`hinata_work`). Anything that does not match is not
/// something we are willing to paste into a command we ask a user to run.
final _snapInstanceName = RegExp(
  r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:_[a-z0-9]{1,10})?$',
);

/// The sentence to show when a session cannot be kept, and the command (if any)
/// that would fix it.
///
/// Produced by [SecretStoreEnvironment.noticeFor] from the system *and* the
/// error, so the two inputs are combined in one place that a unit test can
/// point at — rather than in the widget that happens to raise the toast.
class SecretStoreNotice {
  const SecretStoreNotice({required this.messageKey, this.command});

  /// Translation key of the notice itself.
  final String messageKey;

  /// The one command that grants the missing permission, or null when there is
  /// none to give. Deliberately null rather than a plausible-looking default: a
  /// `snap` command shown to someone who is not running a snap — or whose snap
  /// already has the permission — is a wrong answer dressed as a helpful one.
  final String? command;
}

/// What Hinata knows about this system's secret store *before* it fails.
///
/// Carried by `AppStorage` so the one-time "your session will not survive a
/// restart" notice can name the actual fix instead of guessing.
class SecretStoreEnvironment {
  const SecretStoreEnvironment({required this.remedy, this.snapInstanceName});

  /// Every platform that is not Linux, plus Linux before we know better.
  static const plain = SecretStoreEnvironment(remedy: SecretStoreRemedy.none);

  final SecretStoreRemedy remedy;

  /// The snap this process runs inside, when it runs inside one — `hinata`, or
  /// `hinata_work` for a parallel install. Null everywhere else.
  final String? snapInstanceName;

  bool get isSnap => remedy == SecretStoreRemedy.snapPermission;

  /// The command that would connect this snap's `password-manager-service`
  /// plug. Only ever offered through [noticeFor], which knows whether it is
  /// still the right advice.
  String? get _snapConnectCommand {
    if (!isSnap) return null;
    final name = snapInstanceName ?? _defaultSnapName;
    return 'snap connect $name:password-manager-service';
  }

  /// The notice for a store that refused with [failure].
  ///
  /// Lives here, next to the detection it depends on, so the mapping can be
  /// unit-tested without a widget tree — and so a new [SecretStoreRemedy] or
  /// [SecretStoreFailure] cannot be added without the switch failing to
  /// compile.
  SecretStoreNotice noticeFor(SecretStoreFailure failure) {
    // A store that answered "locked" is a store we can reach: the snap plug is
    // connected, the keyring daemon is installed and running. Neither Linux
    // remedy applies, and offering one is actively misleading — the user goes
    // to App Center, finds the permission already on, and is left with nothing.
    // Only where there is no keyring in the picture at all (the OS stores) does
    // the generic sentence stay right, and it already says nothing specific.
    if (failure == SecretStoreFailure.locked &&
        remedy != SecretStoreRemedy.none) {
      return const SecretStoreNotice(
        messageKey: 'errors.sessionNotPersisted.locked',
      );
    }
    return switch (remedy) {
      SecretStoreRemedy.snapPermission => SecretStoreNotice(
        messageKey: 'errors.sessionNotPersisted.snap',
        command: _snapConnectCommand,
      ),
      SecretStoreRemedy.linuxKeyring => const SecretStoreNotice(
        messageKey: 'errors.sessionNotPersisted.keyring',
      ),
      SecretStoreRemedy.none => const SecretStoreNotice(
        messageKey: 'errors.sessionNotPersisted.generic',
      ),
    };
  }
}

/// The pure half of the detection, so it can be exercised off Linux.
///
/// snapd exports a fixed set of variables into every confined app: `SNAP` (the
/// read-only mount point of the revision), `SNAP_NAME` (the snap) and
/// `SNAP_INSTANCE_NAME` (the *installed* name, which differs from `SNAP_NAME`
/// only for parallel installs). Both `SNAP` and a well-formed name are required
/// here — a lone `SNAP` is a common enough variable in build scripts that it is
/// not, on its own, evidence of confinement.
///
/// And none of them is evidence that *this* process is the confined one.
/// snapd sets them before exec and every child inherits them, so a `.deb`, an
/// AppImage, a Flatpak or `flutter run` started from the terminal of the VS Code
/// snap sees `SNAP=/snap/code/…` and `SNAP_INSTANCE_NAME=code`. Believing that
/// hands a non-snap user `snap connect code:password-manager-service` — advice
/// that cannot help them, naming a snap they did not run, which either errors or
/// grants their editor the whole login keyring. [executablePath] is what closes
/// it: a confined app is executed *out of* its own `$SNAP` mount, so a binary
/// living anywhere else is running with someone else's variables.
SecretStoreEnvironment resolveSecretStoreEnvironment({
  required bool isLinux,
  required Map<String, String> environment,
  required String executablePath,
}) {
  if (!isLinux) return SecretStoreEnvironment.plain;
  final mount = environment['SNAP'] ?? '';
  final instance = environment['SNAP_INSTANCE_NAME'] ?? '';
  final name = environment['SNAP_NAME'] ?? '';
  if (mount.isNotEmpty &&
      (name.isNotEmpty || instance.isNotEmpty) &&
      _runsFrom(mount, executablePath)) {
    // The instance name first — it is the one `snap connect` takes — and only
    // if it survives the shape check. A name that does not is dropped entirely
    // rather than passed through, so the command falls back to the name this
    // repository actually publishes under.
    String? resolved;
    for (final candidate in [instance, name]) {
      if (_snapInstanceName.hasMatch(candidate)) {
        resolved = candidate;
        break;
      }
    }
    return SecretStoreEnvironment(
      remedy: SecretStoreRemedy.snapPermission,
      snapInstanceName: resolved,
    );
  }
  return const SecretStoreEnvironment(remedy: SecretStoreRemedy.linuxKeyring);
}

/// Whether [executablePath] lives inside the snap mount [mount].
///
/// A path *component* boundary, not a string prefix: `/snap/hinata/4` must not
/// claim a binary out of `/snap/hinata/42`. The mount has to be absolute for
/// the same reason the name is shape-checked — a relative or empty `SNAP` from
/// some build script is not something to draw a conclusion from.
bool _runsFrom(String mount, String executablePath) {
  final root = mount.endsWith('/')
      ? mount.substring(0, mount.length - 1)
      : mount;
  if (!root.startsWith('/') || root.length < 2) return false;
  return executablePath == root || executablePath.startsWith('$root/');
}
