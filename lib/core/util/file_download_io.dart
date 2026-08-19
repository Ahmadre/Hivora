import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_download_types.dart';

/// Native: write the bytes to a temporary file and present the OS share sheet so
/// the user chooses where the download goes — iOS "Save to Files", Android's
/// Downloads/Files, AirDrop, mail, etc. This replaces the old behaviour of
/// silently dropping the file in a hidden app directory and echoing the raw
/// container path (unusable, confusing UX).
///
/// [sharePositionOrigin] anchors the popover on iPad (ignored elsewhere); pass
/// the global bounds of the widget that triggered the download.
Future<DownloadOutcome> downloadBytes(
  String filename,
  Uint8List bytes,
  String mimeType, {
  Rect? sharePositionOrigin,
}) async {
  final safe = filename.replaceAll(RegExp(r'[\\/\x00]'), '_').trim();
  final name = safe.isEmpty ? 'download' : safe;
  try {
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
        ? DownloadOutcome.dismissed
        : DownloadOutcome.shared;
  } catch (error, stack) {
    // The outcome is what the caller acts on, but it says nothing about the
    // cause — and the causes here are genuinely different problems: a missing
    // path_provider plugin, a full disk, a sandbox refusal, no share handler.
    // Reported in debug so a failed download is diagnosable at all, which
    // HIN-18 recorded as missing.
    if (kDebugMode) {
      debugPrint('[download] $name failed: $error\n$stack');
    }
    return DownloadOutcome.failed;
  }
}
