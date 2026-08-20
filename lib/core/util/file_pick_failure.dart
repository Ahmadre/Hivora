import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// The i18n key to show when a file dialog would not open, given the
/// [fallbackKey] that fits the calling screen.
///
/// A screen with a better message of its own passes that ("the logo could not
/// be uploaded"); everywhere else passes `errors.filePickFailed`, which says
/// the one thing that is actually known.
///
/// Linux is the platform that needs its own message. `file_picker` does not
/// open a dialog there: it shells out to `zenity`, `qarma` or `kdialog` and
/// fails with a plain exception when none of them is on the PATH. That is by
/// far the most common reason picking fails on Linux, and the only one the user
/// can act on — a distribution that ships neither gives no other hint that a
/// package is missing. Every other platform opens its own dialog, where a
/// failure says nothing more specific than the generic message already does.
String filePickFailureKey(String fallbackKey) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux
    ? 'errors.filePickerMissing'
    : fallbackKey;
