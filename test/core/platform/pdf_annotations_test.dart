import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/platform/pdf_annotations.dart';

/// The Apple rasterizer (`CGContext.drawPDFPage`, which `printing` uses on iOS
/// and macOS) paints the page's content stream and nothing else, so a form's
/// field boxes — and the values typed into them — were missing from the
/// attachment viewer there while every other platform showed them (HIN-58).
/// [PdfAnnotations] asks the runner to redraw the document with its annotations
/// baked in.
///
/// What these tests pin is the contract around that call, because every one of
/// its failure modes has to end with a document that still renders: the wrong
/// platform, no runner on the other end, a native error, an empty answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('hinata/pdf');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final pdf = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]); // "%PDF"

  final calls = <MethodCall>[];

  void answerWith(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'redraws the document on macOS and returns what the runner sends back',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final flattened = Uint8List.fromList(const [1, 2, 3, 4, 5]);
      answerWith((_) => flattened);

      expect(await PdfAnnotations.flatten(pdf), flattened);
      expect(calls.single.method, 'flattenAnnotations');
      expect(calls.single.arguments, pdf);
    },
  );

  test(
    'keeps the downloaded bytes when the runner has nothing to add',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // `null` is how the native side says "no annotations here" without copying
      // an identical document back over the channel.
      answerWith((_) => null);

      expect(await PdfAnnotations.flatten(pdf), same(pdf));
    },
  );

  test(
    'keeps the downloaded bytes when the runner answers with nothing at all',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      answerWith((_) => Uint8List(0));

      expect(await PdfAnnotations.flatten(pdf), same(pdf));
    },
  );

  test('keeps the downloaded bytes when the redraw fails', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    answerWith((_) => throw PlatformException(code: 'invalid-argument'));

    expect(await PdfAnnotations.flatten(pdf), same(pdf));
  });

  test('keeps the downloaded bytes when no runner is listening', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    answerWith((_) => throw MissingPluginException());

    expect(await PdfAnnotations.flatten(pdf), same(pdf));
  });

  test(
    'never reaches for the channel on platforms that render annotations',
    () async {
      answerWith((_) => Uint8List.fromList(const [9, 9, 9]));

      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          await PdfAnnotations.flatten(pdf),
          same(pdf),
          reason: '$platform',
        );
      }
      expect(calls, isEmpty);
    },
  );

  test('does not send an empty download to the runner', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    answerWith((_) => Uint8List.fromList(const [9, 9, 9]));

    final empty = Uint8List(0);
    expect(await PdfAnnotations.flatten(empty), same(empty));
    expect(calls, isEmpty);
  });
}
