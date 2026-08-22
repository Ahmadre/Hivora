import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_download_types.dart';

/// Native: hand the bytes to whatever the platform offers for "the user now
/// owns this file".
///
/// On iOS, Android, macOS and Windows that is the OS share sheet — "Save to
/// Files", Downloads, AirDrop, mail — so the user picks the destination and no
/// internal path is ever shown. On Linux there is no such sheet, so the file
/// goes straight into the Downloads folder; see [_saveToDownloads].
///
/// [sharePositionOrigin] anchors the popover on iPad (ignored elsewhere); pass
/// the global bounds of the widget that triggered the download.
Future<DownloadResult> downloadBytes(
  String filename,
  Uint8List bytes,
  String mimeType, {
  Rect? sharePositionOrigin,
}) async {
  final name = _safeName(filename);
  try {
    if (Platform.isLinux) return await _saveToDownloads(name, bytes);

    // The temp dir always exists and is writable on every platform; the share
    // sheet copies the file into whatever destination the user picks, so it
    // doesn't need to live in a permanent location.
    final dir = await getTemporaryDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: mimeType.isEmpty ? null : mimeType,
            name: name,
          ),
        ],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? DownloadResult.dismissed
        : DownloadResult.shared;
  } catch (error, stack) {
    // The outcome is what the caller acts on, but it says nothing about the
    // cause — and the causes here are genuinely different problems: a missing
    // path_provider plugin, a full disk, a sandbox refusal, no share handler.
    // Reported in debug so a failed download is diagnosable at all, which
    // HIN-18 recorded as missing.
    if (kDebugMode) {
      debugPrint('[download] $name failed: $error\n$stack');
    }
    return DownloadResult.failed;
  }
}

/// Writes the file into the user's Downloads folder and reports what it is
/// called.
///
/// Linux takes this path because `share_plus` has no file sharing there: its
/// Linux implementation throws `UnimplementedError` the moment `files` is
/// non-empty, which used to make every download on Linux a silent failure. A
/// portal-based share exists on some desktops and on none of the others, so
/// the dependable answer is the folder every desktop already agrees on.
///
/// The name is made unique rather than overwriting: two exports of the same
/// issue in one session are two files, and a download that silently replaced
/// one the user still needed would be the worse surprise.
Future<DownloadResult> _saveToDownloads(String name, Uint8List bytes) async {
  final targets = await _downloadTargets();
  // Every candidate but the last is an attempt. Inside a snap the first one is
  // the user's real ~/Downloads, which is writable through the `home`
  // interface — and on Ubuntu Core, or with that interface disconnected, the
  // very same path is visible and refused by AppArmor on the first write. A
  // download that lands in the confined home directory is a worse answer than
  // one in ~/Downloads and a much better one than a failed download, so the
  // refusal falls through to the next candidate instead of surfacing. The last
  // candidate's failure is the caller's failure and travels up to
  // [downloadBytes], which reports it.
  for (final directory in targets.take(targets.length - 1)) {
    try {
      return await _saveInto(directory, name, bytes);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[download] ${directory.path} refused $name: $error');
      }
    }
  }
  return _saveInto(targets.last, name, bytes);
}

/// The folders to write into, best first — see [downloadDirectories] for why
/// the snap case does not ask the XDG user directories at all.
Future<List<Directory>> _downloadTargets() async {
  // The lookup is wrapped because it shells out to the XDG user directories,
  // which a desktop without xdg-user-dirs configured does not have at all —
  // and a download must not fail over a folder we can name ourselves.
  String? xdg;
  try {
    xdg = (await getDownloadsDirectory())?.path;
  } catch (_) {
    xdg = null;
  }
  return downloadDirectories(
    environment: Platform.environment,
    xdgDownloads: xdg,
  ).map(Directory.new).toList();
}

/// Where a download may land, in the order it should be tried.
///
/// Unconfined this is one entry: XDG_DOWNLOAD_DIR when the user-dirs config
/// names one, `~/Downloads` otherwise, and the working directory if even $HOME
/// cannot be resolved — because a file the user can find beats a failure.
///
/// Inside a snap it is two, and the XDG answer is deliberately not among them.
/// snapd repoints HOME at $SNAP_USER_DATA (`~/snap/hinata/current`), and the
/// `home` interface's AppArmor rule (`owner @{HOME}/[^s.]** rwkl`) excludes
/// every top-level dotfile — so `~/.config/user-dirs.dirs`, the file that
/// names the user's Downloads folder, cannot be read from in there.
/// `xdg-user-dir DOWNLOAD` would answer with the snap's own HOME and the
/// download would land in a data directory no file manager bookmarks: the
/// lookup does not fail, it lies. snapd exports SNAP_REAL_HOME for this exact
/// case, the `home` plug makes `$SNAP_REAL_HOME/Downloads` writable, and so
/// the snap saves where the Flatpak (`--filesystem=xdg-download:create`), the
/// AppImage and a plain `.deb` install all save.
///
/// The test is HOME against SNAP_REAL_HOME rather than "is this a snap",
/// because that is the actual question. Those variables are inherited by every
/// child of a snap — a terminal in the VS Code snap starts an unconfined app
/// with both set — and there they are *equal*, so an unconfined process keeps
/// the XDG lookup that is right for it. They differ only where HOME is not the
/// user's home, which is precisely when SNAP_REAL_HOME is the answer.
@visibleForTesting
List<String> downloadDirectories({
  required Map<String, String> environment,
  String? xdgDownloads,
}) {
  final home = environment['HOME'] ?? '';
  final realHome = environment['SNAP_REAL_HOME'] ?? '';
  // Absolute, or it is not a home directory — an empty or relative value out
  // of some build script is not something to write a user's file into.
  if (realHome.startsWith('/') && realHome != home) {
    return ['$realHome/Downloads', '${home.isEmpty ? '.' : home}/Downloads'];
  }
  if (xdgDownloads != null && xdgDownloads.isNotEmpty) return [xdgDownloads];
  return ['${home.isEmpty ? '.' : home}/Downloads'];
}

/// One attempt: create [directory], pick a free name in it and write the bytes.
Future<DownloadResult> _saveInto(
  Directory directory,
  String name,
  Uint8List bytes,
) async {
  await directory.create(recursive: true);
  final target = '${directory.path}/${_freeName(directory, name)}';

  // Written under a private name and moved into place, rather than opened at
  // [target] directly. The Downloads folder is shared ground — every other
  // program the user runs can write there — and `writeAsBytes` follows a
  // symlink it finds at the path it opens. Planting one ahead of time is
  // therefore a way to have this download land somewhere it was never meant
  // to: a shell profile, an autostart entry, an SSH config. `rename` closes
  // that: it replaces a symlink at the destination instead of writing through
  // it, and the staging name carries random bytes so nothing can be lying in
  // wait at that path either.
  final staging = File('${directory.path}/.hinata-download-${_stagingToken()}');
  try {
    await staging.writeAsBytes(bytes, flush: true);
    final saved = await staging.rename(target);
    return DownloadResult(
      DownloadOutcome.saved,
      fileName: saved.uri.pathSegments.last,
    );
  } catch (_) {
    // A half-written staging file is this function's own, created moments ago
    // under a name nothing else can hold, so cleaning it up cannot take
    // anything the user owns with it.
    try {
      if (staging.existsSync()) staging.deleteSync();
    } catch (_) {
      // Nothing more to do; the caller already reports the failure.
    }
    rethrow;
  }
}

/// Random bytes for the staging file's name, so no other program can have
/// created something at that path first. [Random.secure] rather than the
/// default generator: predicting the name is the whole attack.
String _stagingToken() {
  final random = Random.secure();
  return List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// [name], or `name (2).ext` — the first spelling nothing in [directory] uses.
String _freeName(Directory directory, String name) {
  if (_isFree(directory, name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  // Bounded: a directory holding a thousand copies of one name is a loop
  // nobody wants a download to run, and a timestamped fallback still lands.
  for (var i = 2; i < 1000; i++) {
    final candidate = '$stem ($i)$extension';
    if (_isFree(directory, candidate)) return candidate;
  }
  return '$stem-${DateTime.now().millisecondsSinceEpoch}$extension';
}

/// Whether nothing at all sits at that name — asked without following links.
///
/// `File.existsSync` resolves a symlink and answers false for one that points
/// nowhere, so it would call a dangling link a free name and hand the write
/// straight to whatever the link names. Every entry type counts as taken here,
/// which is also the honest answer for a directory or a socket sharing the
/// name.
bool _isFree(Directory directory, String name) =>
    FileSystemEntity.typeSync('${directory.path}/$name', followLinks: false) ==
    FileSystemEntityType.notFound;

/// The name a downloaded file is allowed to have, given the [filename] the
/// server reported for it.
///
/// The name is chosen by whoever uploaded the attachment, so it is data, not
/// instruction, and three separate things have to be taken out of it:
///
///  * **Path separators and NUL.** `../../.bashrc` has to stay one file name
///    rather than becoming a path, and a name made only of dots (`.`, `..`) is
///    a reference to a directory rather than a name at all.
///  * **Control characters and the bidi overrides.** They are invisible: a name
///    ending in `\u202Egnp.exe` renders as `…exe.png` in the toast that
///    announces the download and in every file manager after it, which is the
///    oldest attachment disguise there is. Stripped rather than escaped —
///    nothing legitimate puts them in a file name.
///  * **Length.** A name past the file system's limit fails the write outright,
///    which would let a server turn a download into a dead button.
/// The sanitiser, exposed for tests: it decides what a server-supplied name
/// may become on disk and in the toast, which is worth pinning directly.
@visibleForTesting
String safeDownloadName(String filename) => _safeName(filename);

String _safeName(String filename) {
  final stripped = filename.replaceAll(_unsafeNameCharacters, '_').trim();
  if (stripped.isEmpty || _onlyDots.hasMatch(stripped)) return 'download';
  return _withinNameLimit(stripped);
}

/// Separators, NUL and the rest of C0, DEL, C1, and the Unicode bidi
/// controls (LRM/RLM, the embedding + override block, the isolates).
final _unsafeNameCharacters = RegExp(
  r'[\\/\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]',
);

final _onlyDots = RegExp(r'^\.+$');

/// Linux allows 255 **bytes** per name; the uniqueness suffix `_freeName` may
/// add still has to fit next to it, hence a little under.
const _maxNameBytes = 200;

/// [name] cut to [_maxNameBytes], keeping the extension — that is the part of
/// a long name a user actually reads. Measured in encoded bytes and cut on
/// rune boundaries, because a name is UTF-8 on disk and half a character is
/// not a name.
String _withinNameLimit(String name) {
  if (utf8.encode(name).length <= _maxNameBytes) return name;
  final dot = name.lastIndexOf('.');
  // Only a plausible suffix is worth preserving: a dot far from the end of a
  // long name is as likely to be part of the text as an extension, and cutting
  // the name off there would throw away almost all of it.
  final hasExtension = dot > 0 && name.length - dot <= 16;
  final extension = hasExtension ? name.substring(dot) : '';
  final stem = hasExtension ? name.substring(0, dot) : name;
  final budget = _maxNameBytes - utf8.encode(extension).length;
  final kept = StringBuffer();
  var used = 0;
  for (final rune in stem.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > budget) break;
    kept.writeCharCode(rune);
    used += size;
  }
  return kept.isEmpty ? 'download$extension' : '$kept$extension';
}
