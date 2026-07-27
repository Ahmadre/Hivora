/// The editable surface and its controller.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_editor.dart';
import 'package:hinata/core/lexical/hinata_editor_controller.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

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
  });
}
