import 'secret_store_environment_types.dart';

/// The web has no process environment and no separate secret-store daemon —
/// `flutter_secure_storage_web` encrypts into the browser's own storage. There
/// is nothing to detect and nothing to tell the user to install.
SecretStoreEnvironment detectSecretStoreEnvironment() =>
    SecretStoreEnvironment.plain;
