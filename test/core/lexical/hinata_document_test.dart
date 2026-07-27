/// The read-only renderer, against the same corpus the wire contract uses.
///
/// The contract test proves a stored document *opens*. This proves it reaches
/// the screen: every fixture renders without an overflow, an exception or a
/// failed layout, at the narrowest width the app ever uses.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/api/api_image.dart';
import 'package:hinata/core/lexical/hinata_document.dart';
import 'package:hinata/core/lexical/hinata_markdown_preview.dart';
import 'package:hinata/core/lexical/hinata_theme.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  /// A phone in portrait — the width where a table or a long code line
  /// overflows first.
  const narrow = Size(320, 900);

  Future<void> pumpDoc(
    WidgetTester tester,
    String doc, {
    Size size = narrow,
    double fontSize = 15,
    SmartLinkTapped? onTapSmartLink,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HinataDocument(
              doc: doc,
              fontSize: fontSize,
              onTapSmartLink: onTapSmartLink,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fixture(String name) =>
      File('test/fixtures/richtext/$name.json').readAsStringSync();

  final names =
      Directory('test/fixtures/richtext')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last.replaceAll('.json', ''))
          .toList()
        ..sort();

  group('every stored document renders', () {
    for (final name in names) {
      testWidgets('$name renders on a narrow screen without overflowing', (
        tester,
      ) async {
        await pumpDoc(tester, fixture(name));

        // takeException() returns the overflow assertion when a RenderFlex or a
        // paragraph runs past its constraints, which is exactly the failure
        // that would otherwise only be visible on a device.
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a callout is inset once', () {
    test('the block style leaves the padding to the tinted box', () {
      // Both used to declare it: 14/12 from the style, another 12/10 inside the
      // container, and a callout inset 26 px from a 320 px screen.
      final style = hinataLexicalTheme().blockStyles['callout']!;

      expect(style.padding, EdgeInsets.zero);
      expect(style.spacing, greaterThan(0));
    });

    testWidgets('its indicator is a straight rule, not a rounded crescent', (
      tester,
    ) async {
      // A one-sided `Border` under a border radius is painted as the difference
      // of two rounded rects, so it tapers to nothing at both corners. The
      // block keeps its rounding; the indicator must not have any.
      await pumpDoc(tester, fixture('callout'));

      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>();

      expect(
        decorations.any(
          (decoration) =>
              decoration.border != null && !decoration.border!.isUniform,
        ),
        isFalse,
        reason: 'the callout still draws its rule as a one-sided border',
      );
      // Drawn as its own rectangle instead, at the width it says it is.
      expect(
        tester
            .widgetList<SizedBox>(find.byType(SizedBox))
            .any((box) => box.width == 3),
        isTrue,
      );
    });
  });

  group('a callout separates the blocks it holds', () {
    Future<double> heightAt(WidgetTester tester, double blockSpacing) async {
      tester.view
        ..physicalSize = const Size(400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HinataDocument(
                doc: markdownToDocument(':::info\nEins\n\nZwei\n:::'),
                blockSpacing: blockSpacing,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(HinataDocument)).height;
    }

    testWidgets('two paragraphs inside one do not render flush', (
      tester,
    ) async {
      // The renderer applies a block style's spacing only at the top level, so
      // a callout that does not space its own children renders them touching.
      final tight = await heightAt(tester, 0);
      final loose = await heightAt(tester, 24);

      // 24 below the callout plus 24 between its two paragraphs. Without the
      // inner gap the difference is only the space below the block.
      expect(loose - tight, greaterThan(40));
    });
  });

  group('the surfaces size independently', () {
    testWidgets('a comment renders at its smaller body size', (tester) async {
      await pumpDoc(tester, fixture('paragraph'), fontSize: 13.5);

      expect(tester.takeException(), isNull);
      expect(find.byType(HinataDocument), findsOneWidget);
    });
  });

  group('degrading rather than failing', () {
    testWidgets('an unreadable document renders nothing', (tester) async {
      // A broken article must not take its page down with it.
      await pumpDoc(tester, '{ not json at all');

      expect(tester.takeException(), isNull);
    });

    testWidgets('a document of an unknown node type renders nothing', (
      tester,
    ) async {
      await pumpDoc(
        tester,
        '{"root":{"type":"root","version":1,"format":"","indent":0,'
        '"direction":null,"children":[{"type":"somethingNew","version":1}]}}',
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty document renders nothing', (tester) async {
      await pumpDoc(tester, '');

      expect(tester.takeException(), isNull);
      expect(find.byType(HinataDocument), findsOneWidget);
    });
  });

  group('the block cache survives an unrelated rebuild', () {
    testWidgets('a parent rebuilding does not rebuild every block', (
      tester,
    ) async {
      // The renderer caches one widget per top-level block and throws the whole
      // cache away when `theme` or `decoratorBuilders` is not `==` to the
      // previous one. Neither type has an `operator ==`, so building either in
      // `build()` switches the cache off entirely — invisibly, because the
      // output looks identical either way.
      final stats = LexicalRenderStats();
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);

      tester.view
        ..physicalSize = const Size(400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, value, _) => SingleChildScrollView(
                // Something unrelated to the document changing above it.
                child: Padding(
                  padding: EdgeInsets.only(top: value.toDouble()),
                  child: HinataDocument(doc: fixture('mixed'), stats: stats),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(stats.blocksBuilt, greaterThan(0));
      stats.reset();

      rebuild.value = 1;
      await tester.pumpAndSettle();

      expect(
        stats.blocksReused,
        greaterThan(0),
        reason: 'every block was rebuilt for an unrelated parent rebuild',
      );
      expect(stats.blocksBuilt, 0);
    });
  });

  group('reporting the document that is on screen', () {
    Future<List<Object?>> notifications(
      WidgetTester tester,
      List<String?> docs,
    ) async {
      final seen = <Object?>[];
      for (final doc in docs) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HinataDocument(doc: doc, onDocument: seen.add),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      return seen;
    }

    testWidgets('an unreadable document reports null, not silence', (
      tester,
    ) async {
      // Silence is what leaves the previous article's table of contents on
      // screen, pointing at node keys from a document that is gone.
      final seen = await notifications(tester, [
        fixture('headings'),
        '{ broken',
      ]);

      expect(seen, hasLength(2));
      expect(seen.first, isA<LexicalEditor>());
      expect(seen.last, isNull);
    });

    testWidgets('a null document reports null', (tester) async {
      final seen = await notifications(tester, [fixture('headings'), null]);

      expect(seen.last, isNull);
    });
  });

  group('a reader cannot edit what it is reading', () {
    testWidgets('an image offers no handles and no caption button', (
      tester,
    ) async {
      // The package's image view offers drag handles and a hardcoded-German
      // "Beschriftung hinzufügen" when it is editable. In a published article
      // or someone else's comment there is no save path at all, so a drag
      // mutates state that silently evaporates.
      await pumpDoc(tester, fixture('image'));

      final image = tester.widget<LexicalImageView>(
        find.byType(LexicalImageView),
      );
      expect(image.editable, isFalse);
      expect(image.captionsEnabled, isFalse);
      expect(find.text('Beschriftung hinzufügen'), findsNothing);
    });
  });

  group('untrusted image sources', () {
    test('an oversized data: payload draws nothing', () {
      // A document is written by whoever wrote it — a colleague, an inbound
      // e-mail, an agent — and a base64 blob is decoded into memory on render.
      final huge = base64Encode(
        List<int>.filled(hinataMaxInlineImageBytes + 1024, 0x41),
      );

      expect(hinataImageResolver('data:image/png;base64,$huge'), isNull);
    });

    test('an ordinary inline image still renders', () {
      final small = base64Encode(List<int>.filled(64, 0x41));

      expect(
        hinataImageResolver('data:image/png;base64,$small'),
        isA<MemoryImage>(),
      );
    });

    test('an image on an unknown host still renders', () {
      // hinata is a shared tracker: documents legitimately link images from
      // wikis, status pages and CI. Refusing those would blank them.
      expect(
        hinataImageResolver('https://wiki.example.org/a.png'),
        isA<NetworkImage>(),
      );
    });

    test('a file: URL is still refused', () {
      expect(hinataImageResolver('file:///etc/passwd'), isNull);
    });

    testWidgets('an uploaded image is fetched through the authenticated '
        'proxy', (tester) async {
      // An upload returns an app-relative path, not a URL: no host, and the
      // media proxy wants the bearer token. Read as an asset name — which is
      // all the default resolver can do with it — it renders as a broken box,
      // and inserting an image looks like it did nothing at all.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = ApiClient(
        AppStorage(
          await SharedPreferences.getInstance(),
          const FlutterSecureStorage(),
        ),
      );

      expect(
        hinataImageResolverFor(api)('/api/v1/media/abc'),
        isA<ApiImage>().having(
          (image) => image.path,
          'path',
          '/api/v1/media/abc',
        ),
      );
      // Everything else keeps the behaviour it had.
      expect(
        hinataImageResolverFor(api)('https://wiki.example.org/a.png'),
        isA<NetworkImage>(),
      );
    });

    test('a media path falls back to the app\'s own client', () {
      // A decorator map is memoised and an `ImageProvider` outlives the build
      // that made it, so "a client was in scope at that moment" is a condition
      // that holds almost always — and an image that almost always loads is
      // not good enough for one that was uploaded on purpose.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final previous = ApiClient.instance;
      addTearDown(() => ApiClient.instance = previous);

      expect(
        hinataImageResolverFor(null)('/api/v1/media/abc'),
        isA<ApiImage>(),
        reason: 'the app-wide client was not used',
      );
    });

    test('with no client at all the placeholder is drawn at once', () {
      // Read as an asset name — which is all the plain resolver can do with a
      // path — it produces a provider guaranteed to fail, and the failure is
      // invisible: the request that would have carried a status code was never
      // made.
      final previous = ApiClient.instance;
      ApiClient.instance = null;
      addTearDown(() => ApiClient.instance = previous);

      expect(hinataImageResolverFor(null)('/api/v1/media/abc'), isNull);
      // Everything that is not a path on this server is unaffected.
      expect(
        hinataImageResolverFor(null)('https://wiki.example.org/a.png'),
        isA<NetworkImage>(),
      );
      expect(hinataImageResolverFor(null)('bilder/a.png'), isA<AssetImage>());
    });
  });

  group('links', () {
    testWidgets('a document with no host callback still reacts to a tap', (
      tester,
    ) async {
      // Every reader in the app left `onTapLink` null, so every link in every
      // article, issue and comment was rendered blue, underlined and dead.
      await pumpDoc(tester, fixture('links'));

      final document = tester.widget<LexicalDocument>(
        find.byType(LexicalDocument),
      );

      expect(document.interaction, isNotNull);
      expect(document.interaction!.types, contains('link'));
    });

    testWidgets('a link is marked as one, not only coloured', (tester) async {
      // Colour and an underline are the whole vocabulary text styling has for
      // "this goes somewhere" — and headings, mentions and callouts are
      // coloured too, so a reader has to know the convention before a link
      // reads as one.
      await pumpDoc(tester, fixture('links'));

      expect(find.byIcon(LucideIcons.link), findsNWidgets(2));
    });

    testWidgets('the mark is drawn beside the link, not written into it', (
      tester,
    ) async {
      // It occupies a position in the laid-out text; it must not occupy one
      // in the document. A mark that reached the model would be saved, sent
      // to the web client, and exported into the markdown.
      final before = jsonDecode(fixture('links'));
      await pumpDoc(tester, fixture('links'));

      final document = tester.widget<LexicalDocument>(
        find.byType(LexicalDocument),
      );

      expect(document.editor.editorState.toJson(), before);
    });
  });

  group('smart links are tappable', () {
    testWidgets('tapping a chip reports its kind and target', (tester) async {
      final taps = <String>[];
      await pumpDoc(
        tester,
        fixture('smart-links'),
        onTapSmartLink: (kind, targetId) => taps.add('${kind.wire}:$targetId'),
      );

      // The issue chip carries a readable label, so it is findable by it —
      // and a label is what the reader sees, which is the point of storing one.
      await tester.tap(find.text('HIN-5'));
      await tester.pump();

      expect(taps, ['issue:HIN-5']);
    });
  });
}
