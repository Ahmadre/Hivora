/// Result of a [downloadBytes] call, so the caller can give the right feedback
/// without ever surfacing an internal file-system path to the user.
enum DownloadOutcome {
  /// Native: the OS share sheet was presented and the user picked a target
  /// (e.g. iOS "Save to Files", Android Downloads) or an action completed.
  shared,

  /// Native: the user dismissed the share sheet without saving. No feedback
  /// needed — it was a deliberate cancel.
  dismissed,

  /// Web: a browser download was triggered (the browser owns the save dialog).
  browser,

  /// The file was written straight into the user's Downloads folder, because
  /// the platform has no share sheet to offer instead.
  ///
  /// Unlike [shared] this one *needs* saying out loud: nobody watched a dialog
  /// go by, so without a message the download is indistinguishable from
  /// nothing happening at all. [DownloadResult.fileName] carries what to say.
  saved,

  /// Something went wrong writing/sharing the file.
  failed,
}

/// What a download did, and — when it landed somewhere the user has to be told
/// about — what it is called.
///
/// The name, never the path: an absolute path is noise in a toast, and on a
/// sandboxed platform it is a container location that means nothing to anyone.
class DownloadResult {
  const DownloadResult(this.outcome, {this.fileName});

  final DownloadOutcome outcome;

  /// The saved file's name, set only for [DownloadOutcome.saved].
  final String? fileName;

  static const DownloadResult shared = DownloadResult(DownloadOutcome.shared);
  static const DownloadResult dismissed = DownloadResult(
    DownloadOutcome.dismissed,
  );
  static const DownloadResult browser = DownloadResult(DownloadOutcome.browser);
  static const DownloadResult failed = DownloadResult(DownloadOutcome.failed);
}
