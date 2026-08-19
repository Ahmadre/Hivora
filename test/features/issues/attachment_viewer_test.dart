/// The full-screen attachment viewer: which files it renders, how it zooms,
/// and what it refuses to put on screen.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/features/issues/attachments/attachment_kind.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:hinata/features/issues/attachments/attachment_viewer.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer;
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

    /// HIN-48. The minus button used to grey out at 100 % for pictures and
    /// PDFs, so a whole PDF page never fit on a wide window and the control
    /// looked broken. These pin the picture half; the PDF half is the same
    /// `_zoomRange` floor and is verified on screen.
    testWidgets('a picture zooms out below 100 % and stays centred', (
      tester,
    ) async {
      api.serveBytes('/dl/out', base64Decode(_png8x8));
      await openViewer(tester, [
        const ViewerItem(
          id: 'i',
          name: 'shot.png',
          kind: 'image',
          size: 128,
          url: '/dl/out',
          mime: 'image/png',
        ),
      ]);
      await pumpUntil(tester, find.byType(InteractiveViewer));

      Matrix4 matrix() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value;
      double scale() => matrix().getMaxScaleOnAxis();

      expect(scale(), 1);

      // The button being live at 100 % is the bug report. Tapping it must also
      // not throw: below 1× the old clamp passed a lower limit above its upper
      // one, which num.clamp rejects outright.
      await tester.tap(find.byIcon(LucideIcons.minus));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(scale(), lessThan(1));
      expect(tester.takeException(), isNull);

      // Centred, not parked in a corner: the shrunken child's span has to sit
      // symmetrically inside the viewport.
      final stage = tester.getSize(find.byType(InteractiveViewer));
      final translation = matrix().getTranslation();
      expect(
        translation.x,
        closeTo((stage.width - scale() * stage.width) / 2, 0.5),
      );
      expect(
        translation.y,
        closeTo((stage.height - scale() * stage.height) / 2, 0.5),
      );
    });

    testWidgets('zooming out reaches the floor and the readout stays legible', (
      tester,
    ) async {
      api.serveBytes('/dl/floor', base64Decode(_png8x8));
      api.serveBytes('/dl/floor2', base64Decode(_png8x8));
      // Two items on purpose: paging is only ever enabled when there is
      // somewhere to page to, so a single-item viewer could not tell us whether
      // zooming out took the swipe away.
      await openViewer(tester, [
        const ViewerItem(
          id: 'i',
          name: 'shot.png',
          kind: 'image',
          size: 128,
          url: '/dl/floor',
          mime: 'image/png',
        ),
        const ViewerItem(
          id: 'j',
          name: 'other.png',
          kind: 'image',
          size: 128,
          url: '/dl/floor2',
          mime: 'image/png',
        ),
      ]);
      await pumpUntil(tester, find.byType(InteractiveViewer));

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer).first,
      );
      // One source of truth: the stage's own floor is the same number the
      // toolbar clamps to, so a change to _zoomRange cannot ship half-applied.
      expect(viewer.minScale, 0.5);

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byIcon(LucideIcons.minus));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(tester.takeException(), isNull);

      // 0.5 → "50%", two digits in a 58px box.
      expect(find.text('50%'), findsOneWidget);

      // Below 100 % the picture still fits, so the gestures that belong to the
      // viewer keep the drag: swipe-to-close and paging must stay live.
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
      );

      await tester.tap(find.byIcon(LucideIcons.maximize));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        closeTo(1, 0.001),
      );
    });

    testWidgets('a double tap toggles fit and close-up, never the floor', (
      tester,
    ) async {
      api.serveBytes('/dl/tap', base64Decode(_png8x8));
      await openViewer(tester, [
        const ViewerItem(
          id: 'i',
          name: 'shot.png',
          kind: 'image',
          size: 128,
          url: '/dl/tap',
          mime: 'image/png',
        ),
      ]);
      await pumpUntil(tester, find.byType(InteractiveViewer));

      double scale() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis();

      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(scale(), closeTo(2.5, 0.001));

      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      // Back to "fits the window", not down to the new floor.
      expect(scale(), closeTo(1, 0.001));
    });

    testWidgets('a pinch takes a picture below 100 %, and it stays centred', (
      tester,
    ) async {
      api.serveBytes('/dl/pinch', base64Decode(_png8x8));
      await openViewer(tester, [
        const ViewerItem(
          id: 'i',
          name: 'shot.png',
          kind: 'image',
          size: 128,
          url: '/dl/pinch',
          mime: 'image/png',
        ),
      ]);
      await pumpUntil(tester, find.byType(InteractiveViewer));

      Matrix4 matrix() => tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value;
      double scale() => matrix().getMaxScaleOnAxis();

      // Off to one side on purpose: the fingers are nowhere near the middle,
      // which is what turns a plain zoom-out into a slide.
      const at = Offset(200, 350);
      final left = await tester.startGesture(at - const Offset(90, 0));
      final right = await tester.startGesture(at + const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 20));
      for (var step = 0; step < 6; step++) {
        await left.moveBy(const Offset(12, 0));
        await right.moveBy(const Offset(-12, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }

      // The toolbar could always do this; a pinch only can because the boundary
      // is widened below 1× — InteractiveViewer's own floor is otherwise
      // max(viewport / boundary), which is exactly 1 with the default boundary.
      expect(scale(), lessThan(1));

      // Now shove the shrunken picture sideways, still pinching. panEnabled is
      // off, but the scale gesture translates anyway — this is the drag that
      // used to leave a picture that *fits* parked half outside the window,
      // with no way to bring it back.
      for (var step = 0; step < 6; step++) {
        await left.moveBy(const Offset(50, 0));
        await right.moveBy(const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await left.up();
      await right.up();
      await tester.pump();

      final stage = tester.getSize(find.byType(InteractiveViewer));
      final translation = matrix().getTranslation();
      expect(scale(), lessThan(1));
      expect(
        translation.x,
        closeTo((stage.width - scale() * stage.width) / 2, 1),
      );
      expect(
        translation.y,
        closeTo((stage.height - scale() * stage.height) / 2, 1),
      );
      expect(tester.takeException(), isNull);
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

    // ── PDF stage (HIN-48) ──────────────────────────────────────────────
    //
    // Rasterizing a real PDF needs the `printing` plugin's platform channel,
    // which a widget test does not have. What it *does* have is the channel
    // itself: [_FakePrinting] answers `printingInfo`/`rasterPdf` and pushes the
    // package's own `onPageRasterized` callbacks back, so everything above the
    // rasterizer — our page layout, both scroll axes, the zoom anchoring and the
    // failure path — runs exactly as it does on a device.
    group('pdf', () {
      late _FakePrinting printing;

      setUp(() => printing = _FakePrinting());

      ViewerItem pdfItem({String path = '/dl/spec'}) => ViewerItem(
        id: 'p',
        name: 'spec.pdf',
        kind: 'pdf',
        size: 4096,
        url: path,
        mime: 'application/pdf',
      );

      /// Our own page sheets — the ones the package no longer draws.
      final sheets = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_PdfSheet',
      );

      final sideways = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );

      /// How many pages the document has, whether or not they are on screen.
      int? pageCount(WidgetTester tester) =>
          (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
                  as SliverChildBuilderDelegate)
              .estimatedChildCount;

      /// [pumpUntil] stops at the first match, which for a lazy page list is
      /// the first page — the rest of the raster stream is still in flight.
      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      /// [path] per test on purpose: the byte cache is a module global that
      /// outlives a single viewer (and a single test), so two tests sharing a
      /// download path would hand each other their bytes.
      Future<void> openPdf(
        WidgetTester tester, {
        String path = '/dl/spec',
        bool serve = true,
      }) async {
        printing.install(tester);
        if (serve) api.serveBytes(path, Uint8List.fromList([1, 2, 3, 4]));
        await openViewer(tester, [pdfItem(path: path)]);
      }

      testWidgets('the pages are ours, and the package cannot take them back', (
        tester,
      ) async {
        await openPdf(tester);
        await pumpUntil(tester, sheets);
        await settle(tester);

        // The list is lazy — a page is nearly twice the stage tall, so only
        // the first is built. The document's length is in the delegate.
        expect(sheets, findsWidgets);
        expect(pageCount(tester), 2);

        // The bug: the package wraps every page in a double-tap detector that
        // swaps the document for one page inside its own InteractiveViewer,
        // after which our zoom (which widens the pages) and its transform fight
        // over the same document and slide it off to the side. Supplying a
        // pagesBuilder is what makes that mode unreachable — there must be no
        // second zoom system on this stage, no matter how often it is tapped.
        final centre = tester.getCenter(find.byType(PageView));
        await tester.tapAt(centre);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(centre);
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(InteractiveViewer), findsNothing);
        expect(sheets, findsWidgets);
        expect(pageCount(tester), 2);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'zoom lays the pages out wider, and only then scrolls sideways',
        (tester) async {
          await openPdf(tester);
          await pumpUntil(tester, sheets);

          // Sheet width includes the page's own margin, so at 1× it is the whole
          // stage — the paper inside it is that minus the margin.
          final atOne = tester.getSize(sheets.first).width;
          expect(atOne, closeTo(900, 1));
          expect(
            tester.widget<SingleChildScrollView>(sideways).physics,
            isA<NeverScrollableScrollPhysics>(),
          );

          await tester.tap(find.byIcon(LucideIcons.plus));
          await tester.pump();
          await tester.pump();

          expect(tester.getSize(sheets.first).width, closeTo(atOne * 1.4, 1));
          final scroller = tester.widget<SingleChildScrollView>(sideways);
          expect(scroller.physics, isA<ClampingScrollPhysics>());
          expect(scroller.controller!.position.maxScrollExtent, greaterThan(0));

          // …and below 100 % the page is narrower than the window, so there is
          // nothing to scroll and the sheet is centred rather than pinned left.
          await tester.tap(find.byIcon(LucideIcons.maximize));
          await tester.pump();
          await tester.tap(find.byIcon(LucideIcons.minus));
          await tester.pump();
          await tester.pump();

          expect(find.text('71%'), findsOneWidget);
          expect(tester.getSize(sheets.first).width, lessThan(900));
          final page = tester.getRect(sheets.first);
          expect(page.center.dx, closeTo(450, 1));
        },
      );

      testWidgets('the toolbar zooms around the middle of the window', (
        tester,
      ) async {
        await openPdf(tester);
        await pumpUntil(tester, sheets);
        await settle(tester);

        final vertical = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        vertical.jumpTo(500);
        await tester.pump();

        final before = vertical.offset;
        await tester.tap(find.byIcon(LucideIcons.plus));
        await tester.pump();
        await tester.pump();

        // 350 = half of the 700-tall stage: what was in the middle stays there.
        expect(
          vertical.offset,
          closeTo(
            zoomAnchoredOffset(
              offset: before,
              focal: 350,
              factor: 1.4,
              maxExtent: vertical.position.maxScrollExtent,
            ),
            2,
          ),
        );
      });

      testWidgets('a pinch zooms around the fingers, not the corner', (
        tester,
      ) async {
        await openPdf(tester);
        await pumpUntil(tester, sheets);
        await settle(tester);

        final vertical = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        vertical.jumpTo(500);
        await tester.pump();
        final before = vertical.offset;

        // Two fingers 100px apart, high up the window, spread to 200px — 2×,
        // around a focal point far from the middle of the stage.
        const focal = Offset(450, 160);
        final left = await tester.startGesture(focal - const Offset(50, 0));
        final right = await tester.startGesture(focal + const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 20));
        for (var step = 0; step < 5; step++) {
          await left.moveBy(const Offset(-10, 0));
          await right.moveBy(const Offset(10, 0));
          await tester.pump(const Duration(milliseconds: 20));
        }
        await left.up();
        await right.up();
        await tester.pump();
        await tester.pump();

        final zoom = double.parse(
          tester
              .widget<Text>(
                find.byWidgetPredicate(
                  (w) => w is Text && (w.data?.endsWith('%') ?? false),
                ),
              )
              .data!
              .replaceAll('%', ''),
        );
        expect(zoom, greaterThan(100));

        final factor = zoom / 100;
        final anchored = zoomAnchoredOffset(
          offset: before,
          focal: focal.dy,
          factor: factor,
          maxExtent: vertical.position.maxScrollExtent,
        );
        final centred = zoomAnchoredOffset(
          offset: before,
          focal: 350,
          factor: factor,
          maxExtent: vertical.position.maxScrollExtent,
        );
        // Both are far from "did nothing" and far from each other, so this
        // really does pin the point under the fingers rather than the middle.
        expect(centred, isNot(closeTo(anchored, 20)));
        expect(vertical.offset, closeTo(anchored, 2));
      });

      testWidgets('a render failure is offered a second chance', (
        tester,
      ) async {
        // Nothing served: the fetch comes back empty, the rasterizer reports an
        // error, and the stage falls to the card.
        await openPdf(tester, path: '/dl/broken', serve: false);
        await pumpUntil(tester, find.byIcon(LucideIcons.rotateCcw));
        await settle(tester);

        expect(find.byIcon(LucideIcons.rotateCcw), findsOneWidget);
        expect(sheets, findsNothing);
        // The rasterizer reports its failure to the framework as well.
        expect(tester.takeException(), isNotNull);
        expect(printing.rasterCalls, greaterThan(0));

        // Retry re-fetches instead of replaying the memoized empty download…
        api.serveBytes('/dl/broken', Uint8List.fromList([1, 2, 3, 4]));
        final fetches = api.requested.length;
        await tester.tap(find.byIcon(LucideIcons.rotateCcw));
        await tester.pump();
        await pumpUntil(tester, sheets);
        await settle(tester);

        expect(api.requested.length, greaterThan(fetches));
        expect(sheets, findsWidgets);
        expect(pageCount(tester), 2);
        expect(find.byIcon(LucideIcons.rotateCcw), findsNothing);
      });
    });

    // ── Chrome in light mode (HIN-52) ───────────────────────────────────
    //
    // The viewer's backdrop is near-black in *both* app themes, so its chrome
    // is pinned to a dark palette instead of following the app. In light mode
    // it used to follow: the glass resolved its light tokens, carried the
    // near-black stage through as a dull mid-grey, and then put dark violet ink
    // on it — the header line and the zoom bar measured 1.3:1, which is
    // "legible" only if you already know what they say.
    //
    // Measuring that honestly is the difficulty. The background behind a glyph
    // is not a token anyone can look up: it is the lens's fill composited over
    // the backdrop, which is itself composited over the page behind the viewer.
    // Everything below is computed that way, from the fill the widget really
    // handed the lens (`GlassContainer.settings.glassColor`) and the backdrop
    // the viewer really painted ([viewerStageColor]) — never from a constant
    // copied into the test, which would only ever prove the copy right.
    //
    // What the model leaves out is the lens: refraction, blur and the 4 %
    // specular frost are per-pixel effects no static composite captures. The
    // frost lifts the pill slightly, which for light ink can only cost
    // contrast — so these assert with headroom over the WCAG AA floors (4.5:1
    // for text, 3:1 for glyphs and other non-text) rather than sitting on them.
    group('chrome', () {
      /// Matches the viewer itself, so "the chrome" never accidentally means
      /// the page it was opened from — that one *does* follow the app theme.
      final viewer = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ViewerScaffold',
      );
      Finder inViewer(Finder matching) =>
          find.descendant(of: viewer, matching: matching);

      /// The page the backdrop is translucent over.
      Color pageBehind(Brightness brightness) =>
          (brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light())
              .scaffoldBackgroundColor;

      /// What the chrome really floats on, at rest, in an app set to
      /// [brightness].
      Color stage(Brightness brightness) =>
          _composite(viewerStageColor(brightness), pageBehind(brightness));

      /// Opens the viewer inside the app as `app.dart` assembles it — the real
      /// [AppTheme]s *and* the `AppColors.brightness` global they drive, which
      /// is the part no local `Theme` can reach. Returns the notifier that
      /// switches the app underneath the open viewer.
      Future<ValueNotifier<ThemeMode>> open(
        WidgetTester tester,
        ThemeMode initial, {
        List<ViewerItem>? items,
      }) async {
        tester.view
          ..physicalSize = const Size(900, 700)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(() => AppColors.brightness = Brightness.light);

        final mode = ValueNotifier<ThemeMode>(initial);
        addTearDown(mode.dispose);
        await tester.pumpWidget(
          // Keyed per call: pumping a second app of the same shape would
          // otherwise *update* the first one — Navigator included — and the
          // viewer already on its stack would still be there, over the button
          // this is about to tap.
          KeyedSubtree(
            key: UniqueKey(),
            child: RepositoryProvider<ApiClient>.value(
              value: api,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: mode,
                builder: (context, themeMode, _) => MaterialApp(
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: themeMode,
                  builder: (context, child) {
                    // What app.dart does once per frame — and the reason the
                    // viewer cannot fix its ink with a local Theme alone.
                    AppColors.brightness = themeMode == ThemeMode.dark
                        ? Brightness.dark
                        : Brightness.light;
                    return child!;
                  },
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () => showAttachmentViewer(
                            context,
                            items:
                                items ??
                                [
                                  textItem(path: '/dl/chrome'),
                                  textItem(
                                    id: 'b',
                                    name: 'second.md',
                                    path: '/dl/chrome2',
                                  ),
                                ],
                            initialIndex: 0,
                            onDownload: (_) async {},
                          ),
                          child: const Text('open'),
                        ),
                      ),
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
        return mode;
      }

      /// Every colour the viewer resolved for its chrome, in tree order: the
      /// fill each surface handed the glass lens, then the glyphs, the labels
      /// and the fills they sit on.
      ///
      /// The translucent backdrop is deliberately left out — it is the one
      /// colour still allowed to follow the app, and it has its own test.
      List<Color?> chromeColors(WidgetTester tester) {
        final colors = <Color?>[];
        for (final glass in tester.widgetList<GlassContainer>(
          inViewer(find.byType(GlassContainer)),
        )) {
          colors.add(glass.settings?.glassColor);
        }
        for (final icon in tester.widgetList<Icon>(
          inViewer(find.byType(Icon)),
        )) {
          colors.add(icon.color);
        }
        for (final text in tester.widgetList<Text>(
          inViewer(find.byType(Text)),
        )) {
          colors.add(text.style?.color);
        }
        for (final material in tester.widgetList<Material>(
          inViewer(find.byType(Material)),
        )) {
          colors.add(material.color);
        }
        for (final box in tester.widgetList<ColoredBox>(
          inViewer(find.byType(ColoredBox)),
        )) {
          if (box.color.a == 1) colors.add(box.color);
        }
        for (final box in tester.widgetList<DecoratedBox>(
          inViewer(find.byType(DecoratedBox)),
        )) {
          final decoration = box.decoration;
          if (decoration is! BoxDecoration) continue;
          colors.add(decoration.color);
          final border = decoration.border;
          colors.add(border is Border ? border.top.color : null);
        }
        return colors;
      }

      testWidgets('resolves the same colours in either app theme', (
        tester,
      ) async {
        api.serve('/dl/chrome', 'alpha');
        api.serve('/dl/chrome2', 'beta');

        await open(tester, ThemeMode.light);
        await pumpUntil(tester, find.text('alpha'));
        expect(viewer, findsOneWidget);
        final light = chromeColors(tester);

        // A second, independent viewer — built from scratch under a dark app,
        // not the first one repainted.
        await open(tester, ThemeMode.dark);
        await pumpUntil(tester, find.text('alpha'));
        expect(viewer, findsOneWidget);
        final dark = chromeColors(tester);

        // Enough of them that this cannot quietly degrade into comparing two
        // empty lists.
        expect(light.whereType<Color>().length, greaterThan(10));
        expect(light, dark);
      });

      testWidgets('does not move when the app theme is switched under it', (
        tester,
      ) async {
        api.serve('/dl/chrome', 'alpha');
        api.serve('/dl/chrome2', 'beta');
        final mode = await open(tester, ThemeMode.light);
        await pumpUntil(tester, find.text('alpha'));
        final before = chromeColors(tester);

        mode.value = ThemeMode.dark;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(chromeColors(tester), before);
      });

      testWidgets('every glyph and label clears AA over either backdrop', (
        tester,
      ) async {
        api.serve('/dl/chrome', 'alpha');
        api.serve('/dl/chrome2', 'beta');
        await open(tester, ThemeMode.light);
        await pumpUntil(tester, find.text('alpha'));

        // One material for the whole chrome: bars, buttons and filmstrip all
        // hand the lens the same fill, so one composite covers all of them.
        final fills = tester
            .widgetList<GlassContainer>(inViewer(find.byType(GlassContainer)))
            .map((g) => g.settings!.glassColor)
            .toSet();
        expect(fills, hasLength(1));

        // The header's two lines, in order: the filename, then the size line
        // that all but disappeared.
        final header = tester
            .widgetList<Text>(
              find.descendant(
                of: inViewer(find.byType(GlassFloatingSurface)).first,
                matching: find.byType(Text),
              ),
            )
            .toList();
        final filename = header.first.style!.color!;
        final subtitle = header[1].style!.color!;
        final readout = tester
            .widget<Text>(
              find.byWidgetPredicate(
                (w) => w is Text && (w.data?.endsWith('%') ?? false),
              ),
            )
            .style!
            .color!;

        final enabled = tester
            .widget<Icon>(find.byIcon(LucideIcons.plus))
            .color!;
        // At 100 % there is nothing to reset, so this one is really disabled —
        // asserted from its handler, not assumed from its colour.
        expect(
          tester
              .widget<InkWell>(
                find
                    .ancestor(
                      of: find.byIcon(LucideIcons.maximize),
                      matching: find.byType(InkWell),
                    )
                    .first,
              )
              .onTap,
          isNull,
        );
        final disabled = tester
            .widget<Icon>(find.byIcon(LucideIcons.maximize))
            .color!;

        // Wrap starts on, so its button carries the active state.
        final activeButton = tester.widget<Material>(
          find
              .ancestor(
                of: find.byIcon(LucideIcons.wrapText),
                matching: find.byType(Material),
              )
              .first,
        );
        final activeGlyph = tester
            .widget<Icon>(find.byIcon(LucideIcons.wrapText))
            .color!;
        final activeEdge =
            (activeButton.shape! as RoundedRectangleBorder).side.color;

        // The filmstrip's selected entry is marked by a ring and nothing else,
        // which puts it squarely under the 3:1 WCAG asks of a state indicator.
        final ring = tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_StripThumb',
                ),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .map((c) => (c.decoration! as BoxDecoration).border!.top.color)
            .firstWhere((c) => c != Colors.transparent);

        for (final brightness in Brightness.values) {
          final pill = _composite(fills.single, stage(brightness));
          final why = 'app in $brightness';

          expect(_contrast(filename, pill), greaterThan(4.5), reason: why);
          expect(_contrast(subtitle, pill), greaterThan(4.5), reason: why);
          expect(_contrast(readout, pill), greaterThan(4.5), reason: why);
          // A glyph only owes 3:1; the enabled one clears the text bar anyway.
          expect(_contrast(enabled, pill), greaterThan(4.5), reason: why);

          // Disabled: present but not available. Visible on its own…
          expect(_contrast(disabled, pill), greaterThan(3), reason: why);
          // …and a step below the enabled glyph rather than a shade of it.
          expect(
            _contrast(disabled, pill),
            lessThan(_contrast(enabled, pill)),
            reason: why,
          );
          expect(_contrast(disabled, enabled), greaterThan(1.3), reason: why);

          // The active state reads as a state. Its glyph clears AA on its own
          // wash…
          final activeFill = _composite(activeButton.color!, pill);
          expect(
            _contrast(activeGlyph, activeFill),
            greaterThan(4.5),
            reason: why,
          );
          // …but what makes it *distinguishable* is not that glyph: contrast is
          // a luminance ratio, and the amber sits within 1.02:1 of the ordinary
          // ink — same lightness, different hue. So the state is carried by the
          // wash appearing behind the glyph and by a rim that is plainly
          // visible against the bar. That is also what keeps the state from
          // being colour-alone for anyone who cannot separate amber from grey.
          expect(activeButton.color, isNot(Colors.transparent), reason: why);
          expect(activeGlyph, isNot(enabled), reason: why);
          expect(_contrast(activeEdge, pill), greaterThan(3), reason: why);
          expect(_contrast(ring, pill), greaterThan(3), reason: why);
        }
      });

      testWidgets('the backdrop is the one colour the app still moves', (
        tester,
      ) async {
        api.serve('/dl/chrome', 'alpha');
        api.serve('/dl/chrome2', 'beta');

        /// The backdrop as the viewer *paints* it — the bottom layer of its
        /// own Stack, and so the first coloured box in its subtree. Read from
        /// the tree rather than from [viewerStageColor], because a test that
        /// only ever asked the helper would go on passing if the widget stopped
        /// calling it.
        Color painted() {
          final box = tester
              .widgetList<ColoredBox>(inViewer(find.byType(ColoredBox)))
              .first;
          // The identifying property of the backdrop, and the reason the page
          // behind has to be composited in before anything is measured.
          expect(box.color.a, lessThan(1));
          return box.color;
        }

        await open(tester, ThemeMode.light);
        await pumpUntil(tester, find.text('alpha'));
        final ink = tester
            .widgetList<Text>(
              find.descendant(
                of: inViewer(find.byType(GlassFloatingSurface)).first,
                matching: find.byType(Text),
              ),
            )
            .first
            .style!
            .color!;
        final lightApp = painted();

        // A second viewer under a dark app — the same widget, asked again.
        await open(tester, ThemeMode.dark);
        await pumpUntil(tester, find.text('alpha'));
        final darkApp = painted();

        // Over a light app it lifts to a deep indigo instead of slamming to
        // black, so the two ends are genuinely different colours…
        expect(lightApp, isNot(darkApp));
        final backdrops = {
          Brightness.light: lightApp,
          Brightness.dark: darkApp,
        };
        for (final brightness in Brightness.values) {
          final onScreen = _composite(
            backdrops[brightness]!,
            pageBehind(brightness),
          );
          // …but both are dark, which is the fact the whole pinning rests on:
          // light ink is the right ink over either of them.
          expect(
            _contrast(ink, onScreen),
            greaterThan(4.5),
            reason: 'app in $brightness',
          );
          // And what was painted is exactly what [stage] models, which is what
          // lets every other assertion in this group measure against both ends
          // while only one app is mounted.
          expect(onScreen, stage(brightness), reason: 'app in $brightness');
        }
      });

      // The one piece of the viewer's chrome that is *not* under its Theme:
      // showGlassToast inserts into the ROOT overlay, beside the route rather
      // than inside it, so the pill confirming the viewer's own action resolves
      // its material from the app. That is HIN-52 all over again, on the very
      // surface that says the copy worked.
      testWidgets('the copied toast is lit for the stage, not for the app', (
        tester,
      ) async {
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

        final toast = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_GlassToast',
        );

        /// Opens the viewer under an app set to [themeMode], copies the file,
        /// and reports the two colours the toast resolved: the fill it handed
        /// the lens, and the ink it put on that fill.
        Future<(Color fill, Color ink)> copyToast(ThemeMode themeMode) async {
          api.serve('/dl/chrome', 'alpha');
          api.serve('/dl/chrome2', 'beta');
          await open(tester, themeMode);
          await pumpUntil(tester, find.text('alpha'));

          await tester.tap(find.byIcon(LucideIcons.copy));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(copied, isNotEmpty);
          expect(toast, findsOneWidget);
          // The whole reason this test exists: the pill hangs off the root
          // overlay, *outside* the viewer, where the viewer's Theme cannot
          // reach it.
          expect(find.descendant(of: viewer, matching: toast), findsNothing);

          final fill = tester
              .widget<GlassContainer>(
                find.descendant(
                  of: toast,
                  matching: find.byType(GlassContainer),
                ),
              )
              .settings!
              .glassColor;
          final ink = tester
              .widget<Text>(
                find.descendant(of: toast, matching: find.byType(Text)),
              )
              .style!
              .color!;

          // Let the pill run out and leave again, so the next app starts with
          // an empty overlay instead of a stale entry.
          await tester.pump(const Duration(seconds: 4));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          expect(toast, findsNothing);
          return (fill, ink);
        }

        final (lightAppFill, lightAppInk) = await copyToast(ThemeMode.light);
        final (darkAppFill, darkAppInk) = await copyToast(ThemeMode.dark);

        // Pinned like the rest of the chrome: the same pill either way.
        expect(lightAppFill, darkAppFill);
        expect(lightAppInk, darkAppInk);

        // And legible on the stage it actually lands on. The fill is
        // translucent, so what the label sits on is the pill over the backdrop
        // — the same composite the bars are measured through.
        for (final brightness in Brightness.values) {
          expect(
            _contrast(lightAppInk, _composite(lightAppFill, stage(brightness))),
            greaterThan(4.5),
            reason: 'app in $brightness',
          );
        }
      });

      testWidgets('the "no preview" card is pinned dark with it', (
        tester,
      ) async {
        await open(
          tester,
          ThemeMode.light,
          items: const [
            ViewerItem(
              id: 'z',
              name: 'bundle.zip',
              kind: 'zip',
              size: 4096,
              url: '/dl/zip',
            ),
          ],
        );
        final card = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_FileCard',
        );
        expect(card, findsOneWidget);

        final boxes = tester
            .widgetList<DecoratedBox>(
              find.descendant(of: card, matching: find.byType(DecoratedBox)),
            )
            .map((b) => b.decoration as BoxDecoration)
            .toList();
        final fill = boxes.first.color!;
        final tile = boxes[1].color!;

        // Name, type · size, and why there is nothing to look at — every line
        // on the card clears AA against the card, not against a theme.
        final lines = tester.widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        );
        expect(lines, hasLength(3));
        for (final line in lines) {
          expect(_contrast(line.style!.color!, fill), greaterThan(4.5));
        }

        // A dark card on a dark stage: its fill draws no boundary whatsoever —
        // 1.07:1 over a light app's backdrop — so the edge is what has to
        // separate the card from the stage, and it clears the 3:1 WCAG asks of
        // a boundary in both themes. Without it the only thing locating the
        // card would be the kind tile, which is a decoration inside it.
        final edge = (boxes.first.border! as Border).top.color;
        for (final brightness in Brightness.values) {
          expect(_contrast(fill, stage(brightness)), lessThan(1.2));
          expect(
            _contrast(edge, stage(brightness)),
            greaterThan(3),
            reason: 'app in $brightness',
          );
          // The tile stays what it always was: a saturated colour that reads
          // against the stage too, but as the file's kind, not as the card.
          expect(
            _contrast(tile, stage(brightness)),
            greaterThan(3),
            reason: 'app in $brightness',
          );
        }
      });

      testWidgets('the retry pill on a failed render clears AA on the card', (
        tester,
      ) async {
        _FakePrinting().install(tester);
        // Nothing served: the download is empty, the rasterizer errors, and
        // the stage falls back to the card — the only place the accent pill
        // appears.
        await open(
          tester,
          ThemeMode.light,
          items: const [
            ViewerItem(
              id: 'p',
              name: 'spec.pdf',
              kind: 'pdf',
              size: 4096,
              url: '/dl/no-such-pdf',
              mime: 'application/pdf',
            ),
          ],
        );
        await pumpUntil(tester, find.byIcon(LucideIcons.rotateCcw));
        // The rasterizer reports its failure to the framework as well.
        expect(tester.takeException(), isNotNull);

        final card = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_FileCard',
        );
        final cardFill =
            (tester
                        .widgetList<DecoratedBox>(
                          find.descendant(
                            of: card,
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .first
                        .decoration
                    as BoxDecoration)
                .color!;
        final pill = tester.widget<Material>(
          find
              .ancestor(
                of: find.byIcon(LucideIcons.rotateCcw),
                matching: find.byType(Material),
              )
              .first,
        );
        // The wash keeps its own translucency, so what the label sits on is the
        // wash over the card.
        final fill = _composite(pill.color!, cardFill);
        final glyph = tester
            .widget<Icon>(find.byIcon(LucideIcons.rotateCcw))
            .color!;
        final label = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .last
            .style!
            .color!;

        expect(_contrast(glyph, fill), greaterThan(4.5));
        expect(_contrast(label, fill), greaterThan(4.5));
        expect(
          _contrast(
            (pill.shape! as RoundedRectangleBorder).side.color,
            cardFill,
          ),
          greaterThan(3),
        );
      });
    });
  });

  // ── The maths the zoom is built on ──────────────────────────────────────
  group('zoom geometry', () {
    test('content that fits is centred, content that overflows is clamped', () {
      // Below 1× the child is smaller than the window: (900 - 0.5*900) / 2.
      expect(zoomFitTranslation(scale: 0.5, extent: 900, wanted: -400), 225);
      // Exactly 1× there is nothing either way.
      expect(zoomFitTranslation(scale: 1, extent: 900, wanted: -400), 0);
      // Above 1× the wanted translation survives, inside the overflow.
      expect(zoomFitTranslation(scale: 2, extent: 900, wanted: -400), -400);
      expect(zoomFitTranslation(scale: 2, extent: 900, wanted: -2000), -900);
      expect(zoomFitTranslation(scale: 2, extent: 900, wanted: 300), 0);
    });

    test('the point under the focal point is what stays put', () {
      // The content 200px down the window sat at 300+200 = 500; doubled it is
      // at 1000, and 1000-200 = 800 puts it back under the same pixel.
      expect(
        zoomAnchoredOffset(offset: 300, focal: 200, factor: 2, maxExtent: 5000),
        800,
      );
      // Zooming out the same way.
      expect(
        zoomAnchoredOffset(
          offset: 800,
          focal: 200,
          factor: 0.5,
          maxExtent: 5000,
        ),
        300,
      );
      // The scroll extent wins over the anchor, at both ends.
      expect(
        zoomAnchoredOffset(offset: 300, focal: 200, factor: 2, maxExtent: 600),
        600,
      );
      expect(
        zoomAnchoredOffset(offset: 0, focal: 200, factor: 0.1, maxExtent: 600),
        0,
      );
      // An axis that cannot scroll is left alone — it belongs centred by the
      // layout, not pinned to its start.
      expect(
        zoomAnchoredOffset(offset: 0, focal: 200, factor: 4, maxExtent: 0),
        0,
      );
    });
  });

  // ── One palette, by construction (HIN-52) ───────────────────────────────
  //
  // The widget tests above prove the viewer's colours don't move with the app
  // theme *today*. These make the next person's mistake unlikely: they read the
  // source and fail if a theme-dependent token comes back. The trap is easy to
  // walk into — `AppColors.inkSoft` is the right call everywhere else in the
  // app, and on a screen that is dark whatever the app is set to, it is wrong
  // in a way nobody notices until they switch themes.
  group('viewer palette', () {
    const files = [
      'lib/features/issues/attachments/attachment_viewer.dart',
      'lib/features/issues/attachments/attachment_viewer.pages.dart',
    ];

    /// The two files with their comments taken out — the prose is allowed to
    /// name the tokens it is warning about, and does.
    String code(String source) => source
        .split('\n')
        .map((line) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) return '';
          final trailing = line.indexOf(' //');
          return trailing == -1 ? line : line.substring(0, trailing);
        })
        .join('\n');

    final sources = {
      for (final path in files) path: code(File(path).readAsStringSync()),
    };

    test('reads no colour that resolves against the app theme', () {
      // Every member of AppColors whose value depends on `AppColors.brightness`
      // — a global written from the app's theme, which the viewer's own Theme
      // cannot reach. Longest first, so `\b` is judged against the whole name.
      final themed = RegExp(
        r'AppColors\.('
        r'accentSoft|accentInk|surfaceMuted|textSecondary|textPrimary|'
        r'backgroundEnd|background|brandInk|hairline2|hairline|canvas2|canvas|'
        r'surface|inkSoft|inkFaint|pastelFor|ink|soft'
        r')\b',
      );
      sources.forEach((path, source) {
        expect(
          themed.allMatches(source).map((m) => m[0]).toList(),
          isEmpty,
          reason: path,
        );
      });
    });

    test('names every colour in one place', () {
      // _ViewerInk is where the "pinned dark, and here is why" decision lives.
      // A colour named anywhere else in these two files is a second opinion.
      final palette = RegExp(
        r'abstract final class _ViewerInk \{.*?\n\}\n',
        dotAll: true,
      ).firstMatch(sources[files.first]!);
      expect(palette, isNotNull, reason: 'the palette itself must exist');

      sources.forEach((path, source) {
        final outside = source.replaceFirst(palette![0]!, '');
        expect(outside.contains('AppColors.'), isFalse, reason: path);
      });
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

/// The `printing` plugin's platform side, in Dart.
///
/// The package talks to it over one method channel: it asks for `printingInfo`
/// (which decides whether rastering is possible at all), then fires `rasterPdf`
/// and waits for the platform to push `onPageRasterized` — one per page — and
/// finally `onPageRasterEnd`, optionally carrying an error. Answering both
/// directions here is what makes the PDF stage mountable in a widget test; the
/// real rasterizer never runs, but everything the app builds on top of it does.
class _FakePrinting {
  static const _channel = MethodChannel('net.nfet.printing');
  static const _codec = StandardMethodCodec();

  /// Fake pages, small enough to be free and portrait enough to overflow the
  /// stage vertically — which is what gives the scroll something to anchor.
  static const _pageWidth = 40;
  static const _pageHeight = 60;

  int rasterCalls = 0;

  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'printingInfo':
          return <String, dynamic>{'canRaster': true};
        case 'rasterPdf':
          rasterCalls++;
          final args = call.arguments as Map<dynamic, dynamic>;
          final doc = args['doc'] as Uint8List;
          // An empty document is what a failed download hands the rasterizer;
          // the real one errors out on it, and so does this.
          _deliver(tester, args['job'] as int, failed: doc.isEmpty);
          return null;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }

  Future<void> _deliver(
    WidgetTester tester,
    int job, {
    required bool failed,
  }) async {
    Future<void> push(String method, Map<String, dynamic> args) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          _channel.name,
          _codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    if (!failed) {
      for (var page = 0; page < 2; page++) {
        await push('onPageRasterized', <String, dynamic>{
          'job': job,
          'width': _pageWidth,
          'height': _pageHeight,
          'image': Uint8List(_pageWidth * _pageHeight * 4),
        });
      }
    }
    await push('onPageRasterEnd', <String, dynamic>{
      'job': job,
      if (failed) 'error': 'no document',
    });
  }
}

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
