import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:just_audio/just_audio.dart';

import 'voice_platform.dart' as platform;

/// Loads a voice comment's audio bytes on demand — the [contentType] the proxy
/// reports is used to build the playable source.
typedef VoiceAudioLoader =
    Future<({List<int> bytes, String contentType})?> Function();

/// Drives playback of one voice bubble: lazily downloads the audio on first
/// play (through the authenticated API, never the object store), wraps it in a
/// platform-appropriate source (temp file on native, blob URL on web) and
/// exposes play/pause/scrub state to the widget.
///
/// [fallbackDuration] comes from the stored voice metadata so the bubble can
/// show the total length before any audio is fetched.
class VoicePlaybackController extends ChangeNotifier {
  VoicePlaybackController({
    required VoiceAudioLoader loader,
    required Duration fallbackDuration,
  }) : _loader = loader,
       _duration = fallbackDuration;

  /// The bubble whose audio is currently playing, app-wide. Starting playback
  /// on one voice comment pauses this one first, so two clips never overlap
  /// (WhatsApp / iMessage behaviour).
  static VoicePlaybackController? _current;

  final VoiceAudioLoader _loader;
  final AudioPlayer _player = AudioPlayer();

  Future<void> Function()? _disposeSource;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  String? _failureKey;
  bool _playing = false;
  bool _disposed = false;
  Duration _position = Duration.zero;
  Duration _duration;

  bool get loading => _loading;
  bool get failed => _failed;

  /// An i18n key explaining *why* playback failed, or null when there is
  /// nothing more useful to say than "it failed".
  ///
  /// Only one failure is worth spelling out: Linux plays through GStreamer, and
  /// a desktop without its base plugins cannot build a pipeline at all. That is
  /// a package the user can install in one command, and a bare retry button
  /// would never tell them so.
  String? get failureKey => _failureKey;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration =>
      _duration.inMilliseconds > 0 ? _duration : Duration.zero;

  /// 0..1 playback progress, for the amber fill + scrub head.
  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Future<void> toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (!_loaded) {
      await _load();
      if (!_loaded) return;
    }
    // Restart from the top once a clip has finished.
    if (_position >= duration && duration > Duration.zero) {
      await _player.seek(Duration.zero);
    }
    // Pause whichever other bubble is currently playing before starting this
    // one, so voices never overlap.
    final prev = _current;
    if (prev != null && !identical(prev, this) && !prev._disposed) {
      // Guard against a disposed peer: pausing a disposed just_audio player
      // throws, which would abort toggle() before play() and permanently stall
      // playback. try/catch keeps a fresh clip starting no matter what.
      try {
        await prev._player.pause();
      } catch (_) {}
    }
    _current = this;
    await _player.play();
  }

  Future<void> _load() async {
    if (_loading || _disposed) return;
    _loading = true;
    _failed = false;
    _failureKey = null;
    notifyListeners();
    try {
      final audio = await _loader();
      if (audio == null || audio.bytes.isEmpty) throw StateError('no audio');
      if (_disposed) return;
      final source = await platform.createPlayableSource(
        Uint8List.fromList(audio.bytes),
        audio.contentType,
      );
      // Disposed while the source was being built: dispose() already ran with
      // _disposeSource still null, so release the temp file / blob URL here and
      // don't touch the (now disposed) player. No await separates this check
      // from the assignment below, so dispose() can't slip in between.
      if (_disposed) {
        await source.dispose();
        return;
      }
      _disposeSource = source.dispose;
      final resolved = await _player.setAudioSource(
        AudioSource.uri(Uri.parse(source.uri)),
      );
      // Disposed during setAudioSource: the source is now owned by dispose()
      // (via _disposeSource); just stop before wiring streams on a dead player.
      if (_disposed) return;
      if (resolved != null && resolved > Duration.zero) _duration = resolved;
      _wireStreams();
      _loaded = true;
    } on PlatformException catch (e) {
      _failed = true;
      _failureKey = e.code == 'gstreamer'
          ? 'comments.voiceNeedsGstreamer'
          : null;
    } catch (_) {
      _failed = true;
      _failureKey = null;
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _wireStreams() {
    _subs.add(
      _player.positionStream.listen((p) {
        _position = p;
        if (!_disposed) notifyListeners();
      }),
    );
    _subs.add(
      _player.playerStateStream.listen((state) {
        _playing =
            state.playing && state.processingState != ProcessingState.completed;
        if (state.processingState == ProcessingState.completed) {
          // Reset to the start, paused, so the bubble is replayable.
          _position = Duration.zero;
          _player.pause();
          _player.seek(Duration.zero);
        }
        if (!_disposed) notifyListeners();
      }),
    );
  }

  /// Scrub to [fraction] (0..1) of the clip; loads the audio first if needed.
  Future<void> seekFraction(double fraction) async {
    if (!_loaded) {
      await _load();
      if (!_loaded) return;
    }
    final target = duration * fraction.clamp(0.0, 1.0);
    _position = target;
    notifyListeners();
    await _player.seek(target);
  }

  @override
  void dispose() {
    _disposed = true;
    // Clear the app-wide pointer if it referenced us, so the next bubble's
    // toggle() never dereferences a disposed controller.
    if (identical(_current, this)) _current = null;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _disposeSource?.call();
    super.dispose();
  }
}
