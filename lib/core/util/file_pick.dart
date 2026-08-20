/// One way to ask the user for a file, and one shape to hand back.
///
/// Every upload in the app — attachments, comment attachments, the editor's
/// image button, avatars, the organisation logo, e-mail replies, and on Linux
/// the comment composer's gallery entry too — goes through
/// [pickFilesToUpload]. It exists because Linux needs a *different picker*, and
/// no upload surface should have to know that.
///
/// `grep -rn 'pickFilesToUpload(' lib` lists them; deliberately not a count,
/// because a count in a comment is wrong one commit after it is written.
///
/// See [defaultFilePickBackend] for which platform gets which one and why.
library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSelectorPlatform, XTypeGroup;
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        immutable,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext;

import '../i18n/i18n.dart';

/// A file the user picked, flattened out of whichever picker produced it.
///
/// This is deliberately the *whole* of what the app knows about a picked file:
/// a name, a size, and then either a path (native) or bytes (web). Callers that
/// need more read it off disk themselves.
///
/// Named `ChosenFile` rather than the obvious `PickedFile` because
/// `image_picker` exports a deprecated class by that name, and two of the
/// screens using this seam import `image_picker` for the camera and the photo
/// library. One good name beats two `hide` clauses and a trap for the third
/// screen.
@immutable
class ChosenFile {
  const ChosenFile({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
  });

  /// The file's own name — never a path. It is what gets uploaded as the
  /// filename and what an upload chip shows while the transfer runs.
  ///
  /// On Linux this survives the document portal: a file handed over by
  /// `xdg-desktop-portal` is re-exposed under
  /// `/run/user/<uid>/doc/<hash>/<original name>`, so [path] is not the path
  /// the user browsed to, but the last segment of it still is the name they
  /// picked. Nothing in the app derives a *name* from a directory, which is
  /// why that remapping is invisible everywhere but here.
  final String name;

  /// Size in bytes, or `0` when the file could not be measured. Zero is not an
  /// error signal — it is what a picker reports for a file that vanished
  /// between the dialog closing and the read, and the upload fails on its own
  /// terms a moment later with a message that fits.
  final int size;

  /// Absolute path on disk, or null on web, which has no filesystem. Reading
  /// `PlatformFile.path` on web *throws*, so that landmine is defused here
  /// once instead of at every call site.
  final String? path;

  /// The file's contents, present only when the caller asked for them with
  /// `withData` (always the case on web, where there is no path to stream).
  final Uint8List? bytes;
}

/// What the dialog should offer: anything, or pictures only.
enum FilePickKind { any, image }

/// The two strings a file dialog shows that are ours rather than the desktop's.
///
/// They are resolved from a [BuildContext] *before* the dialog opens, so no
/// picker implementation ever holds a context across its async gap.
@immutable
class FilePickLabels {
  const FilePickLabels({required this.images, required this.confirm});

  /// Names the image filter in the dialog's file-type dropdown.
  final String images;

  /// The dialog's accept button. Without it GTK falls back to a hard-coded
  /// English `_Open`, on a desktop that may well be running in German.
  final String confirm;

  static FilePickLabels of(BuildContext context) => FilePickLabels(
    images: context.t('filePicker.images'),
    confirm: context.t('filePicker.confirm'),
  );
}

/// The thing that actually opens a dialog.
///
/// Two implementations, one per platform family — and a third, in tests, that
/// opens nothing.
abstract interface class FilePickBackend {
  /// Opens a dialog and resolves with what the user chose.
  ///
  /// An empty list means *cancelled*, which is never an error and never worth
  /// a message. A dialog that could not be opened at all **throws**; callers
  /// catch that and say so.
  Future<List<ChosenFile>> pick({
    required FilePickKind kind,
    required bool allowMultiple,
    required bool withData,
    required FilePickLabels labels,
  });
}

/// `file_picker`, for every platform except Linux.
class FilePickerPluginBackend implements FilePickBackend {
  const FilePickerPluginBackend();

  @override
  Future<List<ChosenFile>> pick({
    required FilePickKind kind,
    required bool allowMultiple,
    required bool withData,
    required FilePickLabels labels,
  }) async {
    // `labels` goes unused: on Android, iOS, macOS, Windows and web the dialog
    // is the system's own and is localised by the system.
    final result = await fp.FilePicker.platform.pickFiles(
      type: kind == FilePickKind.image ? fp.FileType.image : fp.FileType.any,
      allowMultiple: allowMultiple,
      withData: withData,
    );
    if (result == null) return const [];
    return [
      for (final f in result.files)
        ChosenFile(
          name: f.name,
          size: f.size,
          path: kIsWeb ? null : f.path,
          bytes: f.bytes,
        ),
    ];
  }
}

/// `file_selector`, for Linux.
///
/// Talks to [FileSelectorPlatform.instance], which `file_selector_linux`
/// registers at startup through the generated Dart plugin registrant.
class FileSelectorBackend implements FilePickBackend {
  FileSelectorBackend([FileSelectorPlatform? selector])
    : _selector = selector ?? FileSelectorPlatform.instance;

  final FileSelectorPlatform _selector;

  @override
  Future<List<ChosenFile>> pick({
    required FilePickKind kind,
    required bool allowMultiple,
    required bool withData,
    required FilePickLabels labels,
  }) async {
    // null, not `[]`: an empty list of type groups is an empty filter dropdown,
    // whereas null means "no filtering", which is what `any` asks for.
    final groups = kind == FilePickKind.image
        ? [imageTypeGroup(labels.images)]
        : null;

    final List<XFile> files;
    if (allowMultiple) {
      files = await _selector.openFiles(
        acceptedTypeGroups: groups,
        confirmButtonText: labels.confirm,
      );
    } else {
      final one = await _selector.openFile(
        acceptedTypeGroups: groups,
        confirmButtonText: labels.confirm,
      );
      files = one == null ? const [] : [one];
    }
    return Future.wait(files.map((f) => describeChosenFile(f, withData)));
  }
}

/// Turns an [XFile] into a [ChosenFile], reading only as much as was asked for.
///
/// Mirrors what `file_picker` does on its own native paths — name from the
/// basename, size from a stat that degrades to `0`, bytes only under
/// `withData` — so moving a platform between backends changes the dialog and
/// nothing else.
///
/// Also the adapter for the other things that hand out [XFile]s: `image_picker`
/// (gallery and camera) and, on web, anything at all — where `XFile.path` is a
/// blob URL rather than a file, and so is dropped.
///
/// A failed *read* is not swallowed: a `withData` pick that cannot be read has
/// produced nothing, and pretending otherwise would upload an empty file. A
/// failed *measure* is, because a size is only ever compared against the upload
/// limit, and `0` lets the file through to fail with a message about the upload
/// instead of collapsing the whole pick.
Future<ChosenFile> describeChosenFile(XFile file, bool withData) async {
  final bytes = withData ? await file.readAsBytes() : null;
  return ChosenFile(
    name: file.name,
    size: bytes?.length ?? await _measure(file),
    path: kIsWeb ? null : file.path,
    bytes: bytes,
  );
}

Future<int> _measure(XFile file) async {
  try {
    return await file.length();
  } on Exception {
    return 0;
  }
}

/// The image filter the Linux dialog offers.
///
/// Extensions *and* MIME types, because the two halves cover different files.
/// `gtk_file_filter_add_pattern` matches case-sensitively, so `*.jpg` alone
/// hides `HOLIDAY.JPG`; `gtk_file_filter_add_mime_type` resolves the type from
/// the name through `g_content_type`, which does not care about case. Listing
/// both is how a GTK filter ends up matching what a user would call "an image".
///
/// The set is what the server accepts — PNG/JPEG/GIF/WebP for media and
/// attachments, plus BMP, which avatars and the organisation logo also take.
/// SVG is deliberately absent: the server rejects it (a stored-XSS vector), so
/// offering it in the dialog would only produce a failed upload.
@visibleForTesting
XTypeGroup imageTypeGroup(String label) => XTypeGroup(
  label: label,
  extensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  mimeTypes: const [
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/bmp',
  ],
);

/// Which picker a platform gets.
///
/// Linux is the odd one out and the whole reason this seam exists.
/// `file_picker` has no Linux plugin: its Linux implementation is pure Dart and
/// shells out to `zenity`, `qarma` or `kdialog`. Under a snap's strict
/// confinement none of those is on `$PATH`, so the dialog never opened and
/// nothing said why — the attachment button was simply dead. In a Flatpak they
/// run *inside* the sandbox and can only show the sandbox's view of the
/// filesystem, which is why that manifest had to hand out real read access to
/// the user's folders.
///
/// `file_selector_linux` is a real plugin calling `gtk_file_chooser_native_new`.
/// GTK hands that to the XDG FileChooser portal whenever the app is sandboxed
/// (unconditionally inside Flatpak, and via `GTK_USE_PORTAL=1` in a snap), so
/// the dialog is drawn by the *host*, sees the host's filesystem, and the
/// chosen file arrives through the document portal — no filesystem grant, no
/// staged helper program.
///
/// Everywhere else keeps `file_picker`. It is the only one of the two with an
/// Android implementation, and on iOS, macOS, Windows and web both packages end
/// up in the same system dialog, so swapping there would be churn without a
/// difference.
FilePickBackend defaultFilePickBackend({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) => !isWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.linux
    ? FileSelectorBackend()
    : const FilePickerPluginBackend();

/// Whether this platform's "photo library" is really just a file dialog.
///
/// `image_picker_linux` has no gallery to open: `ImageSource.gallery` forwards
/// straight to `file_selector_linux`, i.e. the same GTK chooser this seam opens
/// on Linux — but with a hard-coded English `Images` filter and no
/// `confirmButtonText`, so GTK labels its accept button `_Open` on a desktop
/// that may well be running in German. A surface offering both a gallery entry
/// and an attachment entry would show one dialog in each language.
///
/// Surfaces that offer a gallery ask this and route through [pickFilesToUpload]
/// instead, which is the identical dialog with [FilePickLabels] on it. Nothing
/// else is lost by the detour: that backend ignores `imageQuality` and
/// `maxWidth` too.
bool galleryIsAFileDialog({bool isWeb = kIsWeb, TargetPlatform? platform}) =>
    !isWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.linux;

/// Replaces the backend for a test. Set back to null when the test is done.
@visibleForTesting
FilePickBackend? debugFilePickBackend;

/// Opens the platform's file dialog and returns what the user chose.
///
/// An empty list means the user cancelled — say nothing. A dialog that would
/// not open throws, and the caller shows the message that fits its screen.
///
/// [withData] loads the file's contents into memory. It is required on web
/// (there is no path there) and is otherwise only worth asking for when the
/// bytes are what gets used: it doubles the memory a picked file costs, and on
/// Linux it is a whole extra read, because `file_selector` hands back a path
/// and nothing else — a caller that uploads from that path pays twice for
/// bytes it never looks at.
Future<List<ChosenFile>> pickFilesToUpload(
  BuildContext context, {
  FilePickKind kind = FilePickKind.any,
  bool allowMultiple = false,
  bool withData = kIsWeb,
}) {
  // Resolved synchronously, here, so no picker holds a BuildContext across the
  // gap where the dialog is open.
  final labels = FilePickLabels.of(context);
  return (debugFilePickBackend ?? defaultFilePickBackend()).pick(
    kind: kind,
    allowMultiple: allowMultiple,
    withData: withData,
    labels: labels,
  );
}
