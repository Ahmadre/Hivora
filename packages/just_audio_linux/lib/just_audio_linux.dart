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
/// Only what a voice bubble needs is implemented — load of a single `file://`
/// source, play, pause, seek, volume, speed, and the `off`/`none` cases of
/// `setLoopMode` and `setShuffleMode`, which `just_audio` calls on the way into
/// every load. Everything else keeps the platform interface's default, which
/// throws a clear `UnimplementedError` rather than silently doing nothing; a
/// feature this app does not use should say so if it is ever reached.
///
/// The channel names, and the shape of every message that crosses them, are in
/// this package's README — one place, so neither half of the plugin has to be
/// read to understand the other.
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
    // The event channel is let go first, and the order is the point: the
    // native player's destructor unregisters both of its channels, so a
    // listener given up afterwards would be cancelling a name nothing answers
    // on any more.
    await _players.remove(request.id)?.close();
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
    final players = _players.values.toList(growable: false);
    _players.clear();
    for (final player in players) {
      await player.close();
    }
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

  StreamController<PlaybackEventMessage>? _eventController;
  StreamSubscription<dynamic>? _nativeEvents;
  bool _closed = false;

  /// The native events, subscribed to once here and fanned out from a
  /// controller this player owns.
  ///
  /// The subscription has to be ours. Handing `receiveBroadcastStream()`
  /// straight out leaves the only subscription in `just_audio`'s hands, and
  /// `just_audio` disposes the platform player *before* it cancels — so the
  /// cancel would reach the event channel after the native side had already
  /// unregistered that name, and `EventChannel` reports the resulting
  /// MissingPluginException through `FlutterError` every time a voice bubble
  /// closes. Owning it means [close] can give it up while the native side is
  /// still there to hear it — which is also the only thing that ever drops the
  /// messenger's handler for this channel. Wrapping in `asBroadcastStream`,
  /// which is what this used to do, hid the first problem by never cancelling
  /// at all, and so kept that handler (and everything it retains) alive for
  /// the rest of the session, once per voice bubble ever played.
  ///
  /// Synchronous, like the controller `asBroadcastStream` would have built
  /// here: it forwards an event a stream callback has already delivered, so
  /// there is nothing to reorder.
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream {
    if (_closed) return const Stream<PlaybackEventMessage>.empty();
    final controller =
        _eventController ??= StreamController<PlaybackEventMessage>.broadcast(
          sync: true,
        );
    _nativeEvents ??= _events.receiveBroadcastStream().listen(
      (event) => controller.add(_eventFrom(event as Map<Object?, Object?>)),
      onError: controller.addError,
    );
    return controller.stream;
  }

  /// Lets go of the native event channel, while it still exists to be let go
  /// of. Called from `disposePlayer` before the pipeline is torn down.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _nativeEvents?.cancel();
    } on Object {
      // Best-effort, for the same reason as [_invokeQuietly]: this runs from
      // dispose(), where the engine may already be taking the channel down,
      // and a throwing teardown would take the caller's own cleanup with it.
    }
    _nativeEvents = null;
    await _eventController?.close();
    _eventController = null;
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final source = _singleUri(request.audioSourceMessage);
    if (source == null) {
      // Clipping, looping sources and real playlists are features this app
      // never asks for; saying so beats pretending to load something and
      // playing silence.
      throw PlatformException(
        code: 'unsupported',
        message: 'just_audio_linux plays a single URI; got '
            '${request.audioSourceMessage.runtimeType}',
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

  /// Answered rather than left to the platform interface's throwing default.
  ///
  /// `just_audio` calls this on the way into *every* load, and — unlike
  /// `setPitch` and `setSkipSilence`, which it wraps in a try/catch — it does
  /// not catch what comes back. An `UnimplementedError` here therefore took the
  /// whole `load()` down with it, which is every voice comment on Linux. There
  /// is nothing to do for it either way: this player holds a single URI and
  /// plays it once, which is exactly [LoopModeMessage.off].
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    if (request.loopMode != LoopModeMessage.off) {
      throw PlatformException(
        code: 'unsupported',
        message: 'just_audio_linux plays a single URI once, without looping',
      );
    }
    return SetLoopModeResponse();
  }

  /// The same unconditional path into `load()` as [setLoopMode], and the same
  /// answer: one item cannot be shuffled, so [ShuffleModeMessage.none] is the
  /// only mode that means anything here.
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    if (request.shuffleMode != ShuffleModeMessage.none) {
      throw PlatformException(
        code: 'unsupported',
        message: 'just_audio_linux plays a single URI; there is nothing to '
            'shuffle',
      );
    }
    return SetShuffleModeResponse();
  }

  /// The single URI behind whatever `just_audio` wrapped it in, or null when
  /// there is more than one thing in there.
  ///
  /// Every `AudioPlayer` keeps a playlist internally since just_audio 0.10, so
  /// even `setFilePath` — one file, no playlist anywhere in sight — arrives
  /// here as a [ConcatenatingAudioSourceMessage] holding a single child.
  /// Matching only on [UriAudioSourceMessage], as this did, therefore refused
  /// *every* load, which is every voice comment on Linux.
  static UriAudioSourceMessage? _singleUri(AudioSourceMessage message) {
    if (message is UriAudioSourceMessage) return message;
    if (message is ConcatenatingAudioSourceMessage &&
        message.children.length == 1) {
      return _singleUri(message.children.first);
    }
    return null;
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
