// Which OS secret store this build is talking to, and what a user could do
// when it is not there.
//
// `detectSecretStoreEnvironment()` is the whole surface. It reads the process
// environment on native platforms and answers [SecretStoreEnvironment.plain] on
// the web, where there is no process environment to read — hence the split:
// `dart:io` cannot be imported into a library that also compiles for the web.
//
// See `AppStorage.sessionIsMemoryOnly` for what the answer is used for.
export 'secret_store_environment_types.dart';
export 'secret_store_environment_io.dart'
    if (dart.library.js_interop) 'secret_store_environment_web.dart';
