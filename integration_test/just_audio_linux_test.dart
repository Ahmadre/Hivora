@TestOn('linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

/// Plays real audio through the plugin this repository ships for Linux.
///
/// The Dart-side unit tests in `packages/just_audio_linux/test` mock the
/// channels, so they prove the wiring and nothing about GStreamer. This one
/// runs inside the actual embedder with the actual plugin registered: if the
/// pipeline cannot be built, the file cannot be decoded, or the position never
/// advances, it fails here and nowhere else.
///
/// Run it on a Linux machine (or the repo's build container under Xvfb) with:
///
///     flutter test integration_test/just_audio_linux_test.dart -d linux
///
/// It needs an audio sink to reach PLAYING — a desktop has one; a container
/// needs `pulseaudio --start` with a null sink. See docs/LINUX.md.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late File file;

  setUpAll(() async {
    file = File('${Directory.systemTemp.path}/hinata_just_audio_linux.wav');
    await file.writeAsBytes(_silentWav(seconds: 3));
  });

  tearDownAll(() async {
    if (await file.exists()) await file.delete();
  });

  testWidgets('a file loads, reports its length, and plays', (tester) async {
    final player = AudioPlayer();
    addTearDown(player.dispose);

    // The duration comes back from the pipeline's pre-roll, so a non-null answer
    // already means GStreamer opened and understood the file.
    final duration = await player.setFilePath(file.path);
    expect(duration, isNotNull);
    expect(duration!.inMilliseconds, closeTo(3000, 300));

    await player.play();
    // Long enough that a stalled pipeline is distinguishable from a slow one,
    // short enough not to wait out the whole clip.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(
      player.position.inMilliseconds,
      greaterThan(200),
      reason: 'the clock never advanced — the pipeline is not actually playing',
    );

    await player.pause();
    final atPause = player.position;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      player.position,
      atPause,
      reason: 'a paused player must not keep moving',
    );

    // Seeking is what a scrub bar does, and it has to report where it landed
    // rather than where it was.
    await player.seek(const Duration(milliseconds: 2000));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.position.inMilliseconds, greaterThan(1500));
  });

  testWidgets('playing to the end completes instead of hanging', (
    tester,
  ) async {
    final player = AudioPlayer();
    addTearDown(player.dispose);

    await player.setFilePath(file.path);
    await player.seek(const Duration(milliseconds: 2600));
    await player.play();

    // `processingStateStream` is what the voice bubble listens to for flipping
    // its button back from pause to play; without the EOS handling in the
    // plugin it would wait forever.
    await player.processingStateStream
        .firstWhere((state) => state == ProcessingState.completed)
        .timeout(const Duration(seconds: 10));
  });
}

/// A minimal 16-bit mono PCM WAV of silence.
///
/// Written by hand rather than checked in as a fixture: the point is to prove
/// the pipeline decodes and clocks a real container, and a few dozen lines of
/// header beat a binary blob in the repository. WAV because `wavparse` is in
/// gstreamer1.0-plugins-good, which the app already requires.
Uint8List _silentWav({required int seconds, int sampleRate = 8000}) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final dataBytes = byteRate * seconds;

  final bytes = BytesBuilder();
  void ascii(String s) => bytes.add(s.codeUnits);
  void u32(int v) => bytes.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => bytes.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // PCM header length
  u16(1); // PCM, uncompressed
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(channels * bitsPerSample ~/ 8); // block align
  u16(bitsPerSample);
  ascii('data');
  u32(dataBytes);
  bytes.add(Uint8List(dataBytes)); // silence

  return bytes.toBytes();
}
