/// The full-screen attachment viewer: which files it renders, how it zooms,
/// and what it refuses to put on screen.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/issues/attachments/attachment_kind.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/issues/attachments/attachment_viewer.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  // ── What counts as previewable ──────────────────────────────────────────
  group('preview kinds', () {
    test('text is recognised by MIME, by extension, and without one', () {
      expect(isTextPreviewable('notes.txt', 'text/plain'), isTrue);
      expect(isTextPreviewable('notes.md'), isTrue);
      expect(
        isTextPreviewable('server.log', 'application/octet-stream'),
        isTrue,
      );
      expect(isTextPreviewable('main.dart'), isTrue);
      expect(isTextPreviewable('Dockerfile'), isTrue);
      expect(isTextPreviewable('feed.atom', 'application/rss+xml'), isTrue);
      expect(
        isTextPreviewable('report.txt', 'text/plain; charset=utf-8'),
        isTrue,
      );

      expect(isTextPreviewable('photo.png', 'image/png'), isFalse);
      expect(isTextPreviewable('bundle.zip', 'application/zip'), isFalse);
      expect(isTextPreviewable('sheet.xlsx'), isFalse);
    });

    test('renderer per file, with the size caps applied', () {
      AttachmentPreviewKind kindOf(String name, int size, [String? mime]) =>
          previewKindFor(
            kind: kindFromName(name, mime),
            name: name,
            size: size,
            mime: mime,
          );

      expect(kindOf('shot.png', 900, 'image/png'), AttachmentPreviewKind.image);
      expect(kindOf('spec.pdf', 900), AttachmentPreviewKind.pdf);
      expect(kindOf('notes.md', 900), AttachmentPreviewKind.text);
      // Unknown type, small enough to look at.
      expect(kindOf('receipt', 900), AttachmentPreviewKind.maybeText);
      // Unknown type, too big to spend a download on a guess.
      expect(
        kindOf('receipt', kMaxTextSniffBytes + 1),
        AttachmentPreviewKind.none,
      );
      // Known text, but past what we will hold in memory.
      expect(
        kindOf('huge.log', kMaxTextPreviewBytes + 1),
        AttachmentPreviewKind.none,
      );
      expect(kindOf('bundle.zip', 900), AttachmentPreviewKind.none);
    });

    test('binary bytes never pass for text', () {
      expect(
        looksLikeText(Uint8List.fromList(utf8.encode('hello\nworld'))),
        isTrue,
      );
      expect(
        looksLikeText(Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x08])),
        isFalse, // a ZIP header — the NUL gives it away
      );
      expect(looksLikeText(Uint8List(0)), isFalse);
    });
  });

  // ── The viewer itself ───────────────────────────────────────────────────
  group('viewer', () {
    late _FakeApi api;

    setUp(() => api = _FakeApi());

    Future<void> openViewer(
      WidgetTester tester,
      List<ViewerItem> items, {
      int initialIndex = 0,
    }) async {
      tester.view
        ..physicalSize = const Size(900, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepositoryProvider<ApiClient>.value(
          value: api,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showAttachmentViewer(
                      context,
                      items: items,
                      initialIndex: initialIndex,
                      onDownload: (_) async {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Pumps — letting real async work (the decode isolate) run — until
    /// [finder] matches. Never `pumpAndSettle`: the loader spins forever.
    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    ViewerItem textItem({
      String id = 'a',
      String name = 'notes.md',
      String path = '/dl/notes',
      int size = 64,
    }) => ViewerItem(
      id: id,
      name: name,
      kind: kindFromName(name),
      size: size,
      url: path,
      mime: 'text/plain',
    );

    testWidgets('the stage fills the screen', (tester) async {
      api.serve('/dl/fills', 'alpha\nbeta');
      await openViewer(tester, [textItem(path: '/dl/fills')]);

      expect(tester.getSize(find.byType(PageView)), const Size(900, 700));
    });

    testWidgets('a text file is rendered as selectable numbered rows', (
      tester,
    ) async {
      api.serve('/dl/rows', 'alpha\nbeta\ngamma');
      await openViewer(tester, [textItem(path: '/dl/rows')]);
      await pumpUntil(tester, find.text('alpha'));

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('gamma'), findsOneWidget);
      // Gutter line numbers.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // One selection region spanning every row, so a drag crosses lines.
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('JSON is pretty-printed', (tester) async {
      api.serve('/dl/data', '{"a":1}');
      await openViewer(tester, [
        textItem(name: 'data.json', path: '/dl/data', size: 7),
      ]);
      await pumpUntil(tester, find.text('{'));

      expect(find.text('{'), findsOneWidget);
      expect(find.text('  "a": 1'), findsOneWidget);
    });

    testWidgets('copy puts the whole file on the clipboard', (tester) async {
      const content = 'alpha\nbeta';
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      api.serve('/dl/copy', content);
      await openViewer(tester, [textItem(path: '/dl/copy')]);
      await pumpUntil(tester, find.text('alpha'));

      await tester.tap(find.byIcon(LucideIcons.copy));
      await tester.pump();

      expect(copied, [content]);
    });

    testWidgets('zoom buttons scale the type and report the level', (
      tester,
    ) async {
      api.serve('/dl/zoom', 'alpha');
      await openViewer(tester, [textItem(path: '/dl/zoom')]);
      await pumpUntil(tester, find.text('alpha'));

      expect(find.text('100%'), findsOneWidget);
      final before = tester.getSize(find.text('alpha'));

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('115%'), findsOneWidget);
      expect(
        tester.getSize(find.text('alpha')).height,
        greaterThan(before.height),
      );
    });

    testWidgets('wrap and line numbers toggle without tearing down the text', (
      tester,
    ) async {
      api.serve('/dl/wrap', 'alpha\nbeta');
      await openViewer(tester, [textItem(path: '/dl/wrap')]);
      await pumpUntil(tester, find.text('alpha'));

      // Wrap off — the rows gain a horizontal scroller.
      await tester.tap(find.byIcon(LucideIcons.wrapText));
      await tester.pump();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // …and back on.
      await tester.tap(find.byIcon(LucideIcons.wrapText));
      await tester.pump();
      expect(find.text('alpha'), findsOneWidget);

      // The gutter toggle reshapes every row the same way.
      await tester.tap(find.byIcon(LucideIcons.listOrdered));
      await tester.pump();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('wrap off lays a long line out on one scrollable row', (
      tester,
    ) async {
      final long = 'x' * 400;
      api.serve('/dl/long', long);
      await openViewer(tester, [textItem(path: '/dl/long', size: 400)]);
      await pumpUntil(tester, find.text(long));

      // Wrapped: the line is folded over several visual lines.
      final wrapped = tester.getSize(find.text(long));
      expect(wrapped.height, greaterThan(30));

      await tester.tap(find.byIcon(LucideIcons.wrapText));
      await tester.pump();

      // Unwrapped: one row, and the paper scrolls sideways to reach its end.
      final flat = tester.getSize(find.text(long));
      expect(flat.height, lessThan(wrapped.height));
      final sideways = tester.widget<SingleChildScrollView>(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      final h = sideways.controller!;
      expect(h.position.maxScrollExtent, greaterThan(0));

      // Wrapping again must not leave the text parked off to the left.
      h.jumpTo(200);
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.wrapText));
      await tester.pump();
      await tester.pump();

      expect(h.offset, 0);
      expect(h.position.maxScrollExtent, 0);
    });

    testWidgets('toggling wrap keeps the reading position', (tester) async {
      api.serve('/dl/keep', List.generate(400, (i) => 'line $i').join('\n'));
      await openViewer(tester, [textItem(path: '/dl/keep', size: 4000)]);
      await pumpUntil(tester, find.text('line 0'));

      final list = find.byType(ListView);
      final vertical = tester.widget<ListView>(list).controller!;
      vertical.jumpTo(600);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.wrapText));
      await tester.pump();

      // Same list element, same offset — not a fresh list back at line 1.
      expect(tester.widget<ListView>(list).controller, same(vertical));
      expect(vertical.offset, 600);
    });

    testWidgets('an active toolbar toggle keeps its glyph legible on dark', (
      tester,
    ) async {
      AppColors.brightness = Brightness.dark;
      addTearDown(() => AppColors.brightness = Brightness.light);

      api.serve('/dl/dark', 'alpha');
      await openViewer(tester, [textItem(path: '/dl/dark')]);
      await pumpUntil(tester, find.text('alpha'));

      // Wrap starts on, so its button is the one in the active state.
      final button = find.byIcon(LucideIcons.wrapText);
      final glyph = tester.widget<Icon>(button).color!;
      final fill = tester
          .widget<Material>(
            find.ancestor(of: button, matching: find.byType(Material)).first,
          )
          .color!;

      // The fill keeps the token's own translucency instead of forcing it to
      // near-solid amber…
      expect(fill, AppColors.accentSoft);
      // …so the glyph on it clears the 3:1 bar WCAG sets for icons.
      expect(
        _contrast(glyph, _composite(fill, AppColors.canvas)),
        greaterThan(3),
      );
    });

    testWidgets('an unknown file that turns out to be binary shows the card', (
      tester,
    ) async {
      api.serveBytes('/dl/blob', Uint8List.fromList([0x00, 0x01, 0x02, 0x03]));
      await openViewer(tester, [
        const ViewerItem(
          id: 'b',
          name: 'receipt',
          kind: 'file',
          size: 4,
          url: '/dl/blob',
        ),
      ]);
      await pumpUntil(tester, find.text('FILE · 4 B'));

      expect(find.text('FILE · 4 B'), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);
    });

    testWidgets('a type we cannot preview is never downloaded', (tester) async {
      await openViewer(tester, [
        const ViewerItem(
          id: 'c',
          name: 'bundle.zip',
          kind: 'zip',
          size: 4096,
          url: '/dl/zip',
        ),
      ]);

      expect(find.text('ZIP · 4.0 KB'), findsOneWidget);
      expect(api.requested, isEmpty);
    });

    testWidgets('every attachment is in the pager, whatever its type', (
      tester,
    ) async {
      api.serve('/dl/pager', 'alpha');
      await openViewer(tester, [
        textItem(path: '/dl/pager'),
        const ViewerItem(
          id: 'z',
          name: 'bundle.zip',
          kind: 'zip',
          size: 4096,
          url: '/dl/zip',
        ),
      ], initialIndex: 0);

      expect(find.text('notes.md'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.chevronRight));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('notes.md'), findsNothing);
      expect(find.text('ZIP · 4.0 KB'), findsOneWidget);
    });

    testWidgets('a picture zooms from the toolbar and then owns its drags', (
      tester,
    ) async {
      api.serveBytes('/dl/shot', base64Decode(_png8x8));
      await openViewer(tester, [
        const ViewerItem(
          id: 'i',
          name: 'shot.png',
          kind: 'image',
          size: 128,
          url: '/dl/shot',
          mime: 'image/png',
        ),
      ]);
      await pumpUntil(tester, find.byType(InteractiveViewer));

      double scale() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis();

      expect(scale(), 1);
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(scale(), closeTo(1.5, 0.001));
      expect(find.text('150%'), findsOneWidget);
      // A zoomed picture must keep its horizontal drags instead of paging.
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );

      await tester.tap(find.byIcon(LucideIcons.maximize));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(scale(), closeTo(1, 0.001));
    });

    testWidgets('the keyboard zooms and pages, with or without ⌘/Ctrl', (
      tester,
    ) async {
      api.serve('/dl/keys', 'alpha');
      await openViewer(tester, [
        textItem(path: '/dl/keys'),
        textItem(id: 'b', name: 'second.md', path: '/dl/keys2'),
      ]);
      await pumpUntil(tester, find.text('alpha'));

      // Bare +, because on the web the browser keeps ⌘+ for its own zoom.
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(find.text('115%'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('second.md'), findsOneWidget);
    });

    testWidgets('Escape closes the viewer', (tester) async {
      api.serve('/dl/escape', 'alpha');
      await openViewer(tester, [textItem(path: '/dl/escape')]);
      expect(find.byType(PageView), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PageView), findsNothing);
    });
  });
}

/// [top] painted over [bottom] — what a translucent fill really looks like
/// once it sits on the surface behind it.
Color _composite(Color top, Color bottom) => Color.from(
  alpha: 1,
  red: top.r * top.a + bottom.r * (1 - top.a),
  green: top.g * top.a + bottom.g * (1 - top.a),
  blue: top.b * top.a + bottom.b * (1 - top.a),
);

/// WCAG contrast ratio between two opaque colours, 1 (identical) to 21.
double _contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final (hi, lo) = (luminance(a), luminance(b));
  return hi > lo ? (hi + 0.05) / (lo + 0.05) : (lo + 0.05) / (hi + 0.05);
}

/// An 8×8 red PNG — a real, decodable picture, small enough to inline.
const _png8x8 =
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQS'
    'ACj/P8Fu7N9hAAAAAElFTkSuQmCC';

class _FakeApi implements ApiClient {
  final Map<String, Uint8List> _files = {};
  final List<String> requested = [];

  void serve(String path, String content) =>
      serveBytes(path, Uint8List.fromList(utf8.encode(content)));

  void serveBytes(String path, Uint8List bytes) => _files[path] = bytes;

  @override
  Future<({List<int> bytes, String contentType})?> getBytes(String path) async {
    requested.add(path);
    final bytes = _files[path];
    if (bytes == null) return null;
    return (bytes: bytes, contentType: 'text/plain');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
