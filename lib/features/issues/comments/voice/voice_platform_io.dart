import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Native: `record` writes to a file we name up-front — hand it a temp dir.
Future<String> recorderTempDir() async => (await getTemporaryDirectory()).path;

/// Native: the helper program [error] says could not be launched, or null when
/// the failure was something else.
///
/// `record_linux` does not record in-process: it pipes `parecord` (PulseAudio)
/// into `ffmpeg`, and neither is guaranteed to be installed. Missing either one
/// surfaces as a [ProcessException] that names it — which is the difference
/// between telling the user the microphone was denied (it was not) and telling
/// them which package to install.
String? missingRecorderTool(Object error) =>
    error is ProcessException ? error.executable : null;

/// Native: the recorder wrote to a real file — read it straight back. The MIME
/// type is whatever we asked the encoder for ([fallbackMime]); native encoders
/// are deterministic, so there's nothing to sniff.
Future<({Uint8List bytes, String mime})> readRecordedAudio(
  String path,
  String fallbackMime,
) async {
  final bytes = await File(path).readAsBytes();
  return (bytes: bytes, mime: fallbackMime);
}

/// Native: write the audio to a temp file `just_audio` can open by URI. `dispose`
/// deletes it once playback is torn down.
Future<({String uri, Future<void> Function() dispose})> createPlayableSource(
  Uint8List bytes,
  String mime,
) async {
  final dir = await getTemporaryDirectory();
  final ext = _extFor(mime);
  final file = File(
    '${dir.path}/hinata_voice_${DateTime.now().microsecondsSinceEpoch}$ext',
  );
  await file.writeAsBytes(bytes, flush: true);
  return (
    uri: Uri.file(file.path).toString(),
    dispose: () async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup; the OS reaps the temp dir regardless.
      }
    },
  );
}

String _extFor(String mime) {
  final base = mime.split(';').first.trim().toLowerCase();
  return switch (base) {
    'audio/mpeg' => '.mp3',
    'audio/webm' => '.webm',
    'audio/ogg' => '.ogg',
    'audio/wav' || 'audio/x-wav' => '.wav',
    _ => '.m4a', // audio/mp4, audio/aac, audio/x-m4a
  };
}
