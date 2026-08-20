import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
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
  final safe = filename.replaceAll(RegExp(r'[\\/\x00]'), '_').trim();
  final name = safe.isEmpty ? 'download' : safe;
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
  // XDG_DOWNLOAD_DIR when the user-dirs config names one, ~/Downloads
  // otherwise; the home directory if even that cannot be resolved, because a
  // file the user can find beats a failure.
  final directory =
      await getDownloadsDirectory() ??
      Directory('${Platform.environment['HOME'] ?? '.'}/Downloads');
  await directory.create(recursive: true);
  final file = File('${directory.path}/${_freeName(directory, name)}');
  await file.writeAsBytes(bytes, flush: true);
  return DownloadResult(
    DownloadOutcome.saved,
    fileName: file.uri.pathSegments.last,
  );
}

/// [name], or `name (2).ext` — the first spelling nothing in [directory] uses.
String _freeName(Directory directory, String name) {
  if (!File('${directory.path}/$name').existsSync()) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  // Bounded: a directory holding a thousand copies of one name is a loop
  // nobody wants a download to run, and a timestamped fallback still lands.
  for (var i = 2; i < 1000; i++) {
    final candidate = '$stem ($i)$extension';
    if (!File('${directory.path}/$candidate').existsSync()) return candidate;
  }
  return '$stem-${DateTime.now().millisecondsSinceEpoch}$extension';
}
