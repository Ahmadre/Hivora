/// The editable surface and its controller.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_editor.dart';
import 'package:hinata/core/lexical/hinata_editor_controller.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/knowledge/markdown/smart_link_chip.dart';
import 'package:hinata/features/knowledge/markdown/smart_link_resolver.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// A resolver that knows about exactly one article.
///
/// Enough to prove a chip resolved: the point is whether the editor asks at
/// all, not what the knowledge base would have answered.
class _OneDocResolver extends SmartLinkResolver {
  static const String docId = '507f1f77bcf86cd799439011';

  @override
  SmartDoc? doc(String id) => id == docId
      ? const SmartDoc(id: docId, title: 'Handbuch', icon: 'file-text')
      : null;

  @override
  SmartIssue? issue(String id) => null;

  @override
  SmartPerson? person(String id) => null;

  @override
  void openDoc(String id) {}

  @override
  void openIssue(String id) {}

  @override
  void openPerson(String id) {}

  @override
  List<MentionCandidate> mentions(String query, {required bool commentMode}) =>
      const [];
}

void main() {
  String fixture(String name) =>
      File('test/fixtures/richtext/$name.json').readAsStringSync();

  group('the controller', () {
    test('an empty controller starts on one empty paragraph', () {
      final controller = HinataEditorController();

      expect(controller.isEmpty, isTrue);
      expect(controller.plainText.trim(), isEmpty);
      // Not a bare root: a document with nowhere to type is one the writer
      // cannot start.
      expect(
        controller.editor.editorState.read(() => $getRoot().childrenSize),
        1,
      );
    });

    test('seeding from a stored document keeps its text', () {
      final controller = HinataEditorController(doc: fixture('headings'));

      expect(controller.plainText, contains('Eins'));
      expect(controller.hasContent, isTrue);
    });

    test('a seeded document is not dirty until it changes', () {
      final controller = HinataEditorController(doc: fixture('paragraph'));

      expect(controller.isDirty, isFalse);

      controller.editor.update(() {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode('mehr')),
        );
      }, discrete: true);

      expect(controller.isDirty, isTrue);
    });

    test('markSaved makes the current content the clean state', () {
      final controller = HinataEditorController(doc: fixture('paragraph'));
      controller.editor.update(() {
        $getRoot().append($createParagraphNode()..append($createTextNode('x')));
      }, discrete: true);

      controller.markSaved();

      expect(controller.isDirty, isFalse);
    });

    test('an unreadable document opens as empty rather than refusing', () {
      // A page the user can neither use nor repair is worse than a blank one.
      final controller = HinataEditorController(doc: '{ not json');

      expect(controller.isEmpty, isTrue);
      expect(
        controller.editor.editorState.read(() => $getRoot().childrenSize),
        1,
      );
    });

    test('a document holding only an image counts as content', () {
      // Text-emptiness is not emptiness; saving over this would drop the image.
      final controller = HinataEditorController(doc: fixture('image'));

      expect(controller.plainText.trim(), 'Ringelblumen');
      expect(controller.hasContent, isTrue);
    });

    test('a document holding only a divider counts as content', () {
      final controller = HinataEditorController(doc: fixture('rule'));

      expect(controller.hasContent, isTrue);
    });

    test('load replaces the content and resets dirtiness', () {
      final controller = HinataEditorController(doc: fixture('paragraph'));

      controller.load(fixture('headings'));

      expect(controller.plainText, contains('Eins'));
      expect(controller.isDirty, isFalse);
    });

    test('what the controller reads back reopens unchanged', () {
      // The controller's output is what goes to the API, so it has to be a
      // document the next open produces identically.
      final controller = HinataEditorController(doc: fixture('mixed'));

      final reopened = HinataEditorController(doc: controller.doc);

      expect(reopened.doc, controller.doc);
    });
  });

  group('the editor widget', () {
    Future<HinataEditorController> pump(
      WidgetTester tester, {
      String? doc,
      bool showToolbar = true,
      Size size = const Size(360, 800),
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = HinataEditorController(doc: doc);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        // No localization delegate: context.t echoes the raw key, so the
        // buttons are found by key rather than by a translated label — which is
        // the right thing to assert anyway.
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HinataEditor(
                controller: controller,
                showToolbar: showToolbar,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('renders an empty document without overflowing', (
      tester,
    ) async {
      await pump(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(HinataEditor), findsOneWidget);
    });

    testWidgets('renders a rich document without overflowing', (tester) async {
      await pump(
        tester,
        doc: File('test/fixtures/richtext/mixed.json').readAsStringSync(),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the toolbar scrolls instead of wrapping on a phone', (
      tester,
    ) async {
      // A wrapped second row pushes the writing area off-screen exactly when
      // the keyboard is already taking half of it.
      await pump(tester, size: const Size(320, 700));

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('the toolbar can be turned off', (tester) async {
      await pump(tester, showToolbar: false);

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('pressing a block button changes the document', (tester) async {
      final controller = await pump(tester);
      controller.editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode('Titel'));
        $getRoot()
          ..clear()
          ..append(paragraph);
        paragraph.selectEnd();
      }, discrete: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('md.heading2'));
      await tester.pumpAndSettle();

      expect(
        controller.editor.editorState.read(
          () => $getRoot().getFirstChild() is HeadingNode,
        ),
        isTrue,
      );
      expect(controller.plainText, 'Titel');
    });

    testWidgets('every authoring action the toolbar advertises is there', (
      tester,
    ) async {
      // The toolbar shipped without a link button, without undo/redo and with
      // one callout flavour out of four, while the strings for all of them were
      // in both locales. A key nobody renders is a feature nobody has.
      //
      // Wide on purpose: the row scrolls, so a narrow viewport does not build
      // the buttons past the fold at all. The narrow case is its own test.
      await pump(tester, size: const Size(1400, 700));

      for (final key in [
        'md.bold',
        'md.italic',
        'md.underline',
        'md.strikethrough',
        'md.inlineCode',
        'md.link',
        'md.paragraph',
        'md.heading1',
        'md.heading2',
        'md.heading3',
        'md.bulletList',
        'md.numberedList',
        'md.taskList',
        'md.quote',
        'md.codeBlock',
        'md.calloutInfo',
        'md.calloutWarn',
        'md.calloutNote',
        'md.calloutTip',
        'md.divider',
        'md.undo',
        'md.redo',
      ]) {
        expect(
          find.byTooltip(key, skipOffstage: false),
          findsOneWidget,
          reason: '$key has no button',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fuller toolbar still scrolls rather than overflowing', (
      tester,
    ) async {
      await pump(tester, size: const Size(320, 700));

      expect(tester.takeException(), isNull);
      // The buttons past the fold are reachable by dragging, which is what
      // makes a scrolling row an acceptable answer to a narrow screen.
      expect(find.byTooltip('md.undo'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(find.byTooltip('md.undo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a callout button is pressed only for its own flavour', (
      tester,
    ) async {
      final controller = await pump(tester, size: const Size(900, 700));
      controller.editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode('Achtung'));
        $getRoot()
          ..clear()
          ..append(paragraph);
        paragraph.selectEnd();
      }, discrete: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('md.calloutWarn'));
      await tester.pumpAndSettle();

      Color colourOf(String key) => tester
          .widget<Icon>(
            find.descendant(
              of: find.byTooltip(key),
              matching: find.byType(Icon),
            ),
          )
          .color!;

      expect(colourOf('md.calloutWarn'), AppColors.accent);
      expect(colourOf('md.calloutInfo'), isNot(AppColors.accent));
      expect(controller.plainText, 'Achtung');
    });

    testWidgets('the link button opens the address field over the text', (
      tester,
    ) async {
      // Not a modal: the writer has to keep seeing the words being linked, and
      // the address is confirmed by the check beside the field rather than by a
      // button in the corner of a dialog.
      await pump(tester, size: const Size(320, 700));

      await tester.tap(find.byTooltip('md.link'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('md.linkAdd'), findsOneWidget);
      expect(find.byTooltip('common.cancel'), findsOneWidget);
      // An overlay that overflows the phone it opens on cannot be used on it.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the address field links the caret it was opened over', (
      tester,
    ) async {
      final controller = await pump(tester, size: const Size(600, 700));
      controller.editor.update(() {
        final paragraph = $createParagraphNode();
        $getRoot()
          ..clear()
          ..append(paragraph);
        paragraph.selectEnd();
      }, discrete: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('md.link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'https://hinata.example',
      );
      await tester.tap(find.byTooltip('md.linkAdd'));
      await tester.pumpAndSettle();

      // Nothing was selected, so the address becomes the link's own text —
      // the alternative is the writer watching what they typed disappear.
      expect(
        controller.editor.editorState.read(() {
          bool anyLink(ElementNode element) => element.children.any(
            (child) =>
                child is LinkNode || (child is ElementNode && anyLink(child)),
          );
          return anyLink($getRoot());
        }),
        isTrue,
      );
      expect(controller.plainText, contains('hinata.example'));
    });

    testWidgets('the cancel button closes the field without linking', (
      tester,
    ) async {
      final controller = await pump(tester, size: const Size(600, 700));

      await tester.tap(find.byTooltip('md.link'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://nope.test');
      await tester.tap(find.byTooltip('common.cancel'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('md.linkAdd'), findsNothing);
      expect(controller.plainText, isNot(contains('nope.test')));
    });

    testWidgets('the platform selection menu is off', (tester) async {
      // Two menus on one gesture, one over the other, is what the writer got
      // before hinata drew its own quick actions.
      await pump(tester, size: const Size(600, 700));

      final field = tester.widget<LexicalEditorField>(
        find.byType(LexicalEditorField),
      );

      expect(
        field.contextMenuBuilder(
          tester.element(find.byType(LexicalEditorField)),
          tester.state<LexicalEditableState>(find.byType(LexicalEditable)),
        ),
        isA<SizedBox>(),
      );
    });

    testWidgets('the language strip appears with a code block and leaves with '
        'it', (tester) async {
      final controller = await pump(tester, size: const Size(900, 700));
      controller.editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode('print(1)'));
        $getRoot()
          ..clear()
          ..append(paragraph);
        paragraph.selectEnd();
      }, discrete: true);
      await tester.pumpAndSettle();

      // Nothing to say about a paragraph.
      expect(find.text('md.codeLanguagePlain'), findsNothing);

      await tester.tap(find.byTooltip('md.codeBlock'));
      await tester.pumpAndSettle();

      // A code block with no language is not highlighted at all, and the strip
      // says so rather than pretending one is chosen.
      expect(find.text('md.codeLanguagePlain'), findsOneWidget);
    });

    testWidgets('an empty document shows the prompt and a written one does '
        'not', (tester) async {
      final controller = await pump(tester);

      expect(find.text('md.placeholder'), findsOneWidget);

      controller.editor.update(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode()..append($createTextNode('Text')));
      }, discrete: true);
      await tester.pumpAndSettle();

      // Absent rather than transparent: an invisible placeholder is still read
      // out by a screen reader and still found by a search.
      expect(find.text('md.placeholder'), findsNothing);
    });

    testWidgets('a swapped controller is the one the toolbar follows', (
      tester,
    ) async {
      // Every host holds its controller in a `late final` today, so nothing
      // exercises this — which is exactly why it has to be pinned: the next
      // host to swap one would find the toolbar quietly tracking the old
      // document and the old controller still holding a live setState closure.
      tester.view
        ..physicalSize = const Size(900, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final first = HinataEditorController();
      final second = HinataEditorController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Future<void> pumpWith(HinataEditorController controller) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HinataEditor(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpWith(first);
      await pumpWith(second);

      // Only the *new* controller commits from here on. Without the listener
      // moving with it, nothing tells the toolbar to rebuild.
      second.editor.update(() {
        final heading = $createHeadingNode(HeadingTag.h2)
          ..append($createTextNode('Titel'));
        $getRoot()
          ..clear()
          ..append(heading);
        heading.selectEnd();
      }, discrete: true);
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('md.heading2'),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, AppColors.accent);
    });

    testWidgets('a smart link resolves while it is being edited', (
      tester,
    ) async {
      // A `doc` link carries no label by design, so without the chip-builder
      // fallback it renders as a raw ObjectId while you write and as the
      // article's title the moment you save.
      final controller = HinataEditorController(doc: fixture('smart-links'));
      addTearDown(controller.dispose);

      tester.view
        ..physicalSize = const Size(900, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartLinkScope(
              resolver: _OneDocResolver(),
              child: SingleChildScrollView(
                child: HinataEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SmartLinkChip), findsWidgets);
      expect(find.text('Handbuch'), findsOneWidget);
      expect(find.text(_OneDocResolver.docId), findsNothing);
    });
  });
}
