import 'dart:io' show Platform;

import 'secret_store_environment_types.dart';

/// Native detection: reads the real process environment, and where the process
/// was started from.
///
/// `Platform.environment` is a snapshot of the environment the process was
/// started with, which is exactly right here — snapd sets `SNAP*` before exec
/// and nothing changes them afterwards. `Platform.resolvedExecutable` is the
/// second half: those variables are inherited by every child of a snap, so the
/// binary's own path is what says whether *this* process is the confined one.
///
/// Guarded, and that guard is not decorative. Neither of those is a plain
/// getter: `dart:io` caches an `OSError` raised while reading the environment
/// block and rethrows it on every later access. This is called from the
/// `AppStorage` constructor, which `main` awaits before `runApp` with nothing
/// to catch it — so a throw here would mean a desktop that never reaches its
/// own login screen, over a question whose answer only decides which sentence a
/// warning uses. [SecretStoreEnvironment.plain] is that "we don't know": no
/// keyring advice, no `snap connect` line, just the generic notice.
SecretStoreEnvironment detectSecretStoreEnvironment() {
  try {
    return resolveSecretStoreEnvironment(
      isLinux: Platform.isLinux,
      environment: Platform.environment,
      executablePath: Platform.resolvedExecutable,
    );
  } catch (_) {
    return SecretStoreEnvironment.plain;
  }
}
