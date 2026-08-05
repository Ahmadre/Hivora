import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:hinata/core/widgets/markdown_toolbar.dart';
import 'package:hinata/features/issues/comments/glass_comment_composer.dart';
import 'package:hinata/features/issues/comments/voice/voice_recorder.dart';
import 'package:hinata/features/knowledge/markdown/mention_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A voice message cannot be retyped. The recorder's file is consumed when it
/// stops, so the bytes handed to the composer are the only copy of what the
/// person just said — and every reason an upload fails (no signal, a 500, a
/// moderation refusal) used to take them with it.
///
/// These tests hold the rule the text composers already follow: nothing but a
/// successful send or a deliberate discard may drop what the user made.
void main() {
  final recording = VoiceRecording(
    bytes: Uint8List.fromList(const [1, 2, 3, 4]),
    mime: 'audio/mp4',
    durationMs: 4200,
    peaks: List<int>.generate(42, (i) => 10 + i),
  );

  setUp(() => voiceRecorderFactory = () => _FakeRecorder(recording));
  tearDown(() => voiceRecorderFactory = VoiceRecorder.new);

  /// A composer whose upload answers [accepted], recording what it was given.
  Widget host(
    List<VoiceRecording> delivered, {
    required bool accepted,
    Size size = const Size(390, 800),
  }) {
    final controller = TextEditingController();
    final focus = FocusNode();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassCommentComposer(
              controller: controller,
              focusNode: focus,
              actions: MarkdownEditingActions(controller, focus),
              onSubmitText: () {},
              onSendVoice: (r) async {
                delivered.add(r);
                return accepted;
              },
              onAttach: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  /// Records, then presses send. Pumped in fixed steps rather than settled: the
  /// recording bar animates a pulsing dot forever, so `pumpAndSettle` would
  /// never return while it is on screen.
  Future<void> recordAndSend(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.mic));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(LucideIcons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('a refused upload keeps the recording and offers it again', (
    tester,
  ) async {
    final delivered = <VoiceRecording>[];
    await tester.pumpWidget(host(delivered, accepted: false));
    await tester.pump();

    await recordAndSend(tester);

    expect(delivered, hasLength(1));
    // Still on screen, with both of the only two things left to do with it.
    expect(find.byIcon(LucideIcons.send), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
    // Not back to the idle row: an empty comment field in place of the bar is
    // the composer saying "there is nothing of yours in here".
    expect(find.byType(MentionField), findsNothing);
    expect(tester.takeException(), isNull);

    // Retrying sends the same bytes, not a fresh empty recording.
    await tester.tap(find.byIcon(LucideIcons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(delivered, hasLength(2));
    expect(identical(delivered.first, delivered.last), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an accepted upload returns the composer to idle', (
    tester,
  ) async {
    final delivered = <VoiceRecording>[];
    await tester.pumpWidget(host(delivered, accepted: true));
    await tester.pump();

    await recordAndSend(tester);

    expect(delivered, hasLength(1));
    // The message is posted, so the recording is spent: back to [+] · field ·
    // mic, with nothing left to discard.
    expect(find.byType(MentionField), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discarding is the one path that throws the recording away', (
    tester,
  ) async {
    final delivered = <VoiceRecording>[];
    await tester.pumpWidget(host(delivered, accepted: false));
    await tester.pump();

    await recordAndSend(tester);
    await tester.tap(find.byIcon(LucideIcons.trash2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(MentionField), findsOneWidget);
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
    // Nothing was posted — the audio was thrown away because the user said so.
    expect(delivered, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 390, 1440]) {
    testWidgets('the kept-recording bar fits ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final delivered = <VoiceRecording>[];
      await tester.pumpWidget(
        host(delivered, accepted: false, size: Size(width, 900)),
      );
      await tester.pump();
      await recordAndSend(tester);

      expect(tester.takeException(), isNull);
    });
  }
}

/// A recorder that never touches a microphone and hands back a finished
/// recording on stop. Implemented rather than extended so no platform recorder
/// is constructed; `noSuchMethod` covers the rest of the surface.
class _FakeRecorder implements VoiceRecorder {
  _FakeRecorder(this.recording);

  final VoiceRecording? recording;

  @override
  Future<bool> start() async => true;

  @override
  Future<VoiceRecording?> stop() async => recording;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  bool get isRecording => true;

  @override
  Stream<double> get liveAmplitude => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
