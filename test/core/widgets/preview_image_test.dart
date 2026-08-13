import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart' show BlurHashImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/repositories/media_repository.dart';
import 'package:hinata/core/widgets/preview_image.dart';

void main() {
  // The canonical example hash from blurha.sh (4×3 components).
  const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

  Future<void> pumpIn(WidgetTester tester, Widget child, Size size) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('HivePreviewImage', () {
    testWidgets('paints the blur placeholder before any image exists', (
      tester,
    ) async {
      await pumpIn(
        tester,
        const HivePreviewImage(blurHash: hash),
        const Size(160, 100),
      );
      await tester.pump();

      final image = tester.widget<Image>(
        find.byWidgetPredicate((w) => w is Image && w.image is BlurHashImage),
      );
      expect((image.image as BlurHashImage).blurHash, hash);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to the given widget without a hash', (
      tester,
    ) async {
      await pumpIn(
        tester,
        const HivePreviewImage(fallback: Icon(Icons.attachment)),
        const Size(160, 100),
      );

      expect(find.byIcon(Icons.attachment), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a malformed hash is not an error, it is just no blur', (
      tester,
    ) async {
      await pumpIn(
        tester,
        const HivePreviewImage(
          blurHash: 'not-a-hash',
          fallback: ColoredBox(color: Color(0xFF102030)),
        ),
        const Size(160, 100),
      );
      // Let the decode fail and the error builder take over.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ColoredBox), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits any box it is given — including a very small one', (
      tester,
    ) async {
      // Overflow is reported as an exception in tests, so a clean pump at a
      // hostile size is the assertion.
      for (final size in const [Size(320, 200), Size(24, 12), Size(600, 40)]) {
        await pumpIn(
          tester,
          const HivePreviewImage(
            blurHash: hash,
            fallback: ColoredBox(color: Color(0xFF102030)),
          ),
          size,
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'at $size');
      }
    });
  });

  group('FadeInOver', () {
    const under = ColoredBox(color: Color(0xFF102030));
    const over = ColoredBox(color: Color(0xFFAABBCC));

    double opacityOf(WidgetTester tester) => tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .last;

    testWidgets('starts invisible and ends fully opaque', (tester) async {
      await pumpIn(
        tester,
        const FadeInOver(under: under, child: over),
        const Size(80, 80),
      );

      expect(opacityOf(tester), 0);
      await tester.pump(const Duration(milliseconds: 130));
      expect(opacityOf(tester), greaterThan(0));
      expect(opacityOf(tester), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacityOf(tester), 1);
    });

    testWidgets('keeps what is underneath at full opacity throughout', (
      tester,
    ) async {
      await pumpIn(
        tester,
        const FadeInOver(under: under, child: over),
        const Size(80, 80),
      );
      await tester.pump(const Duration(milliseconds: 130));

      // Mid-fade both layers are on screen, and only the arriving one is
      // transparent — otherwise the page behind them shows through as a flash.
      expect(find.byWidget(under), findsOneWidget);
      expect(
        tester.widgetList<Opacity>(find.byType(Opacity)).length,
        1,
        reason: 'only the incoming layer is faded',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('mediaThumbnailPath', () {
    test('derives the preview path of an inline media image', () {
      expect(
        mediaThumbnailPath(
          '/api/v1/media/1b4e28ba-2fa1-11d2-883f-0016d3cca427',
        ),
        '/api/v1/media/1b4e28ba-2fa1-11d2-883f-0016d3cca427/thumbnail',
      );
    });

    test('leaves anything that is not an inline media path alone', () {
      // External URLs, assets and data: URIs have no server-side preview, and
      // asking for one would turn a working image into a failed request.
      expect(mediaThumbnailPath('https://example.com/cat.png'), isNull);
      expect(mediaThumbnailPath('assets/branding/logo.png'), isNull);
      expect(mediaThumbnailPath('data:image/png;base64,AAA'), isNull);
      expect(mediaThumbnailPath('/api/v1/media/not-a-uuid'), isNull);
      // Already a thumbnail path — deriving a second one would 404.
      expect(
        mediaThumbnailPath(
          '/api/v1/media/1b4e28ba-2fa1-11d2-883f-0016d3cca427/thumbnail',
        ),
        isNull,
      );
    });
  });
}
