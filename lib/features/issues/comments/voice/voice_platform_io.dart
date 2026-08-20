import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Native: `record` writes to a file we name up-front — hand it a temp dir.
Future<String> recorderTempDir() async => (await _scratchDir()).path;

/// A directory only this user can read, for audio on its way in or out.
///
/// Everywhere but Linux the temporary directory is already per-app and private.
/// On Linux it is `/tmp`, which the whole machine shares: a voice comment
/// written there with the default umask is readable by every other account on
/// the box, under a name that is a timestamp away from being guessable. The
/// cache directory is `XDG_CACHE_HOME`, which lives inside the user's own home
/// (and inside the sandbox under Flatpak), so it is private without having to
/// chmod anything.
///
/// These files are short-lived either way — the recorder's is uploaded and
/// dropped, the player's is deleted when the bubble is torn down — but "short"
/// is not "unreadable".
Future<Directory> _scratchDir() =>
    Platform.isLinux ? getApplicationCacheDirectory() : getTemporaryDirectory();

/// Native: a program the recorder needs that is not installed, or null when
/// everything it shells out to is there.
///
/// Checked *before* capture starts, because only the first of the two programs
/// `record_linux` uses is awaited: it pipes `parecord` into `ffmpeg` and does
/// not wait on the second, so a desktop with PulseAudio but no FFmpeg records
/// for as long as the user cares to talk and then produces nothing, with the
/// failure arriving far away from its cause. Looking both up first turns that
/// into a sentence naming the package.
///
/// Read off PATH rather than by running `which`: this is on the path of a tap
/// on the record button, and spawning two processes to find out whether we can
/// spawn two processes is the wrong shape.
String? missingRecorderDependency() {
  if (!Platform.isLinux) return null;
  for (final tool in const ['parecord', 'ffmpeg']) {
    if (!_onPath(tool)) return tool;
  }
  return null;
}

bool _onPath(String name) {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    if (File('$dir/$name').existsSync()) return true;
  }
  return false;
}

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
  final dir = await _scratchDir();
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
