import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'voice_platform.dart' as platform;

/// A finished recording, ready to upload. [peaks] are normalised 0–100 waveform
/// amplitudes sampled live during capture (so the sent bubble matches what the
/// recorder showed); [durationMs] is wall-clock capture time.
class VoiceRecording {
  const VoiceRecording({
    required this.bytes,
    required this.mime,
    required this.durationMs,
    required this.peaks,
  });

  final Uint8List bytes;
  final String mime;
  final int durationMs;
  final List<int> peaks;
}

/// Capture could not start because a program the recorder drives is missing.
///
/// Linux records by piping `parecord` into `ffmpeg`; a desktop without them
/// fails in a way that looks exactly like a denied microphone unless it is told
/// apart, so the caller can name the missing program instead of blaming the
/// permission the user already granted.
class MissingRecorderTool implements Exception {
  const MissingRecorderTool(this.executable);

  /// The program that could not be launched, e.g. `parecord` or `ffmpeg`.
  final String executable;

  @override
  String toString() => 'MissingRecorderTool($executable)';
}

/// Thin wrapper over `record` that captures a voice message while streaming a
/// live amplitude for the on-screen waveform, and returns the audio bytes +
/// pre-computed peaks + duration on stop. Cross-platform: native encodes AAC in
/// an m4a container; web records whatever the browser's MediaRecorder supports
/// (Opus/webm on Chrome/Firefox, mp4 on Safari) — the real MIME is recovered on
/// read so the upload is typed correctly.
class VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final List<double> _samples = [];
  StreamSubscription<Amplitude>? _ampSub;
  Stopwatch? _clock;

  /// Bars kept for the stored waveform (the design draws ~38–46).
  static const int _storedBars = 42;

  /// dBFS window mapped onto 0..1 — quieter than -[_floorDb] reads as silence.
  static const double _floorDb = 45;

  bool get isRecording => _clock != null;

  /// Live amplitude for the recording UI, already normalised to 0..1.
  final _liveController = StreamController<double>.broadcast();
  Stream<double> get liveAmplitude => _liveController.stream;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begins capture. Returns false if the mic permission was denied.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    _samples.clear();
    // Native: AAC/m4a — small, universally playable. Web: Opus (the recorder
    // picks the container; MIME is detected on read).
    const config = RecordConfig(
      encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
      bitRate: 96000,
      sampleRate: 44100,
      numChannels: 1,
    );
    // Before anything is opened: `record` cannot report a missing helper it
    // never waits for, and a recording that turns out to be impossible after
    // the user has finished talking is the worst moment to find out.
    final missing = platform.missingRecorderDependency();
    if (missing != null) throw MissingRecorderTool(missing);

    // Native needs a target path; web ignores it and returns a blob URL on stop.
    try {
      await _recorder.start(config, path: kIsWeb ? '' : await _tempPath());
    } catch (error) {
      final tool = platform.missingRecorderTool(error);
      if (tool != null) throw MissingRecorderTool(tool);
      rethrow;
    }
    _clock = Stopwatch()..start();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen(_onAmplitude);
    return true;
  }

  void _onAmplitude(Amplitude amp) {
    // `current` is dBFS (0 = loudest, negative = quieter). Map the [-floor, 0]
    // window onto 0..1 for both the live bar and the stored peaks.
    final norm = ((amp.current + _floorDb) / _floorDb).clamp(0.0, 1.0);
    _samples.add(norm);
    if (!_liveController.isClosed) _liveController.add(norm);
  }

  /// Stops and returns the finished recording, or null if nothing was captured.
  Future<VoiceRecording?> stop() async {
    final durationMs = _clock?.elapsedMilliseconds ?? 0;
    await _teardown();
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) return null;
    const fallbackMime = kIsWeb ? 'audio/webm' : 'audio/mp4';
    final audio = await platform.readRecordedAudio(path, fallbackMime);
    if (audio.bytes.isEmpty) return null;
    return VoiceRecording(
      bytes: audio.bytes,
      mime: _normaliseMime(audio.mime, fallbackMime),
      durationMs: durationMs,
      peaks: _downsamplePeaks(),
    );
  }

  /// Aborts the recording and discards the audio.
  Future<void> cancel() async {
    await _teardown();
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing captured yet / already stopped — safe to ignore.
    }
  }

  Future<void> _teardown() async {
    _clock?.stop();
    _clock = null;
    await _ampSub?.cancel();
    _ampSub = null;
  }

  Future<void> dispose() async {
    await _teardown();
    await _liveController.close();
    await _recorder.dispose();
  }

  /// Even, fixed-length waveform for storage. Averages the live samples into
  /// [_storedBars] buckets so a 3s and a 30s clip both yield the same bar count.
  List<int> _downsamplePeaks() {
    if (_samples.isEmpty) {
      // No amplitude data (some web browsers) — a gentle idle waveform still
      // reads as "a voice message" rather than a flat line.
      return List<int>.generate(_storedBars, (i) {
        final t = i / _storedBars;
        return (30 + 45 * (0.5 + 0.5 * (t * 6).remainder(1))).round();
      });
    }
    final out = <int>[];
    final bucket = _samples.length / _storedBars;
    for (var i = 0; i < _storedBars; i++) {
      final start = (i * bucket).floor();
      final end = ((i + 1) * bucket).ceil().clamp(start + 1, _samples.length);
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += _samples[j];
      }
      final avg = sum / (end - start);
      // Keep a visible floor so quiet bars don't vanish.
      out.add((6 + avg * 94).round().clamp(0, 100));
    }
    return out;
  }

  /// Strip any `;codecs=…` suffix so the base type matches the server allow-list.
  String _normaliseMime(String mime, String fallback) {
    final base = mime.split(';').first.trim().toLowerCase();
    return base.isEmpty ? fallback : base;
  }

  Future<String> _tempPath() async {
    // Deferred to the io helper via a temp file created by the platform layer
    // at record time; native `record` needs the path up-front, so build one.
    final dir = await _tempDir();
    return '$dir/hinata_rec_${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  Future<String> _tempDir() => platform.recorderTempDir();
}
