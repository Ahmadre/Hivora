import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// The Linux playback implementation of `just_audio`, backed by GStreamer.
///
/// `just_audio` ships android, iOS, macOS and web. Windows is covered in this
/// app by depending on `just_audio_windows`; Linux had nothing, so every voice
/// comment failed to play there. This is the same shape as that package — a
/// federated implementation that registers itself and needs no change anywhere
/// in the app — with a `playbin` behind it instead of WinRT's MediaPlayer.
///
/// GStreamer rather than a bundled decoder: it is what GTK desktops already
/// have, it is what every Flatpak runtime already ships, and its `playbin`
/// picks the demuxer and decoder for whatever the recorder produced without
/// this plugin having to know the container.
///
/// Only what a player needs is implemented — load, play, pause, seek, volume,
/// speed. Everything else keeps the platform interface's default, which throws
/// a clear `UnimplementedError` rather than silently doing nothing; a feature
/// this app does not use should say so if it is ever reached.
class JustAudioLinux extends JustAudioPlatform {
  static const MethodChannel _channel = MethodChannel('hinata/just_audio_linux');

  /// Registers this implementation. Named by the `dartPluginClass` entry in
  /// the pubspec, so Flutter calls it during plugin registration and nothing
  /// in the app has to.
  static void registerWith() {
    JustAudioPlatform.instance = JustAudioLinux();
  }

  final Map<String, _LinuxAudioPlayer> _players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_players.containsKey(request.id)) {
      throw PlatformException(
        code: 'error',
        message: 'Platform player ${request.id} already exists',
      );
    }
    await _channel.invokeMethod<void>('init', {'id': request.id});
    final player = _LinuxAudioPlayer(request.id);
    _players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    _players.remove(request.id);
    // Through the plugin channel rather than the player's own: the native side
    // keeps the players in a map, and only it can drop the entry — leaving it
    // there would keep a pipeline and two channel registrations alive for every
    // voice bubble the user has ever opened.
    await _invokeQuietly('disposePlayer', {'id': request.id});
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    _players.clear();
    await _invokeQuietly('disposeAllPlayers');
    return DisposeAllPlayersResponse();
  }

  /// Teardown is best-effort: it runs from `dispose()`, where the engine may
  /// already be taking the channel down, and a throwing dispose would take the
  /// caller's own cleanup with it.
  static Future<void> _invokeQuietly(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // Already gone.
    } on MissingPluginException {
      // The engine is tearing down; there is nothing left to release.
    }
  }
}

/// One `playbin`, addressed over its own pair of channels.
///
/// A channel pair per player rather than one shared pair with an id argument:
/// two voice bubbles can exist at once, and routing by id in Dart would mean
/// every event waking every player.
class _LinuxAudioPlayer extends AudioPlayerPlatform {
  _LinuxAudioPlayer(super.id)
    : _methods = MethodChannel('hinata/just_audio_linux/methods/$id'),
      _events = EventChannel('hinata/just_audio_linux/events/$id');

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<PlaybackEventMessage>? _eventStream;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream {
    // Built once and broadcast: just_audio subscribes several times (position,
    // player state, duration), and a fresh EventChannel stream per listener
    // would open a fresh native sink for each of them.
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map((event) => _eventFrom(event as Map<Object?, Object?>))
        .asBroadcastStream();
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final source = request.audioSourceMessage;
    if (source is! UriAudioSourceMessage) {
      // Playlists, clipping and concatenation are features this app never asks
      // for; saying so beats pretending to load something and playing silence.
      throw PlatformException(
        code: 'unsupported',
        message:
            'just_audio_linux plays a single URI; got ${source.runtimeType}',
      );
    }
    final microseconds = await _methods.invokeMethod<int>('load', {
      'uri': source.uri,
      'initialPosition': request.initialPosition?.inMicroseconds ?? 0,
    });
    return LoadResponse(
      duration: microseconds == null || microseconds < 0
          ? null
          : Duration(microseconds: microseconds),
    );
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    await _methods.invokeMethod<void>('play');
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    await _methods.invokeMethod<void>('pause');
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    await _methods.invokeMethod<void>('seek', {
      // A null position means "seek to the start of the given index"; there is
      // only ever one item here, so that is the start.
      'position': request.position?.inMicroseconds ?? 0,
    });
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    await _methods.invokeMethod<void>('setVolume', {'volume': request.volume});
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await _methods.invokeMethod<void>('setSpeed', {'speed': request.speed});
    return SetSpeedResponse();
  }


  PlaybackEventMessage _eventFrom(Map<Object?, Object?> event) {
    final duration = event['duration'] as int?;
    return PlaybackEventMessage(
      processingState:
          ProcessingStateMessage.values[(event['processingState'] as int?) ?? 0],
      updateTime: DateTime.now(),
      updatePosition: Duration(
        microseconds: (event['updatePosition'] as int?) ?? 0,
      ),
      // GStreamer decodes as it goes and this plugin plays local files, so
      // "buffered" is the whole clip once its duration is known.
      bufferedPosition: Duration(microseconds: duration ?? 0),
      duration: duration == null || duration < 0
          ? null
          : Duration(microseconds: duration),
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    );
  }
}
