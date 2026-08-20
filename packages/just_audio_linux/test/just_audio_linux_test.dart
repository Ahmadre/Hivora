import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_linux/just_audio_linux.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// The Dart half of the plugin: which channel each call goes to, and how a
/// native event map becomes a [PlaybackEventMessage].
///
/// The GStreamer half cannot be exercised from a widget test — but the wiring
/// between them can, and the wiring is where a federated plugin usually breaks:
/// a player torn down on the Dart side while the native map still holds its
/// pipeline is a leak nobody notices until the tenth voice comment.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plugin = MethodChannel('hinata/just_audio_linux');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> pluginCalls;
  late List<MethodCall> playerCalls;

  setUp(() {
    pluginCalls = [];
    playerCalls = [];
    messenger.setMockMethodCallHandler(plugin, (call) async {
      pluginCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('hinata/just_audio_linux/methods/p1'),
      (call) async {
        playerCalls.add(call);
        return call.method == 'load' ? 4200000 : null;
      },
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('hinata/just_audio_linux/methods/p1'),
      null,
    );
  });

  test('registerWith installs itself as the platform', () {
    final original = JustAudioPlatform.instance;
    addTearDown(() => JustAudioPlatform.instance = original);
    JustAudioLinux.registerWith();
    expect(JustAudioPlatform.instance, isA<JustAudioLinux>());
  });

  test('a player is created once, and a duplicate id is refused', () async {
    final platform = JustAudioLinux();
    await platform.init(InitRequest(id: 'p1'));

    expect(pluginCalls.single.method, 'init');
    expect((pluginCalls.single.arguments as Map)['id'], 'p1');

    // just_audio reuses ids across a rebuild; creating a second pipeline under
    // the same name would leave the first one playing with nothing to stop it.
    await expectLater(
      platform.init(InitRequest(id: 'p1')),
      throwsA(isA<PlatformException>()),
    );
  });

  test('disposing a player tells the native map, not just the player', () async {
    final platform = JustAudioLinux();
    await platform.init(InitRequest(id: 'p1'));
    pluginCalls.clear();

    await platform.disposePlayer(DisposePlayerRequest(id: 'p1'));

    // The plugin channel is the only place that can drop the map entry — and
    // dropping it is what tears the pipeline and both channels down.
    expect(pluginCalls.single.method, 'disposePlayer');
    expect((pluginCalls.single.arguments as Map)['id'], 'p1');

    // The id is free again afterwards.
    await platform.init(InitRequest(id: 'p1'));
  });

  test('load passes the uri through and answers with the duration', () async {
    final platform = JustAudioLinux();
    final player = await platform.init(InitRequest(id: 'p1'));

    final response = await player.load(
      LoadRequest(
        audioSourceMessage: ProgressiveAudioSourceMessage(
          id: 's1',
          uri: 'file:///tmp/voice.m4a',
        ),
        initialPosition: const Duration(seconds: 1),
      ),
    );

    expect(playerCalls.single.method, 'load');
    final args = playerCalls.single.arguments as Map;
    expect(args['uri'], 'file:///tmp/voice.m4a');
    expect(args['initialPosition'], 1000000);
    expect(response.duration, const Duration(microseconds: 4200000));
  });

  test('a source this plugin cannot play says so instead of playing nothing', () async {
    final platform = JustAudioLinux();
    final player = await platform.init(InitRequest(id: 'p1'));

    await expectLater(
      player.load(
        LoadRequest(
          audioSourceMessage: ConcatenatingAudioSourceMessage(
            id: 'c1',
            children: [],
            useLazyPreparation: false,
            shuffleOrder: const [],
          ),
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(playerCalls, isEmpty);
  });

  test('an unknown duration stays unknown rather than becoming zero', () async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('hinata/just_audio_linux/methods/p1'),
      (call) async => call.method == 'load' ? -1 : null,
    );
    final platform = JustAudioLinux();
    final player = await platform.init(InitRequest(id: 'p1'));

    final response = await player.load(
      LoadRequest(
        audioSourceMessage: ProgressiveAudioSourceMessage(
          id: 's1',
          uri: 'file:///tmp/voice.m4a',
        ),
      ),
    );

    // A clip of length zero would draw an empty waveform and a scrub bar that
    // is already at the end; "unknown" draws neither.
    expect(response.duration, isNull);
  });

  test('native events become playback events', () async {
    final platform = JustAudioLinux();
    final player = await platform.init(InitRequest(id: 'p1'));

    final events = <PlaybackEventMessage>[];
    final subscription = player.playbackEventMessageStream.listen(events.add);
    addTearDown(subscription.cancel);

    await _sendEvent('hinata/just_audio_linux/events/p1', {
      'processingState': 3,
      'updatePosition': 1500000,
      'duration': 4200000,
    });

    expect(events.single.processingState, ProcessingStateMessage.ready);
    expect(events.single.updatePosition, const Duration(microseconds: 1500000));
    expect(events.single.duration, const Duration(microseconds: 4200000));
    // Local playback: everything the pipeline knows the length of is buffered.
    expect(events.single.bufferedPosition, events.single.duration);
  });
}

/// Pushes one event through an EventChannel the way the native side would.
Future<void> _sendEvent(String channel, Object? event) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel,
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );
}
