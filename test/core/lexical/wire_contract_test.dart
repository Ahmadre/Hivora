/// The wire contract between the server and this app.
///
/// The server converts markdown to Lexical JSON and stores it; this app opens
/// what it stored. Unit tests on either side only prove that side is
/// self-consistent — a document the server writes and the app cannot open would
/// pass both of them.
///
/// So this loads the corpus the server's own converter produced
/// (`hinata-server`, `RichTextCorpusTest`) and asserts two things per document:
/// it opens under this app's node registry, and re-exporting it changes
/// nothing. The second is the real contract: a document that survives being
/// opened and saved is one an edit cannot silently rewrite.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_lexical.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

void main() {
  final directory = Directory('test/fixtures/richtext');
  final fixtures =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          // `_`-prefixed files are the corpus's own metadata — the markdown each
          // document was produced from — not documents to open.
          .where((file) => !file.uri.pathSegments.last.startsWith('_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the corpus is present', () {
    // A silently empty fixture directory would make every test below vacuous.
    expect(fixtures, isNotEmpty);
    expect(fixtures.length, greaterThanOrEqualTo(16));
  });

  for (final file in fixtures) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');

    group(name, () {
      late Map<String, Object?> canonical;

      setUp(() {
        canonical = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      });

      test('opens under the hinata registry', () {
        final editor = createHinataEditor();

        // Throws on a node type this app does not know — which is exactly the
        // failure this corpus exists to catch, and the reason it must not be
        // caught and softened here.
        editor.setEditorState(editor.parseEditorState(canonical));

        // Read the value inside the scope, not the node: a node accessor is
        // only valid while the read is active.
        expect(
          editor.editorState.read(() => $getRoot().childrenSize),
          greaterThan(0),
        );
      });

      test('is a fixed point: exporting it back changes nothing', () {
        final editor = createHinataEditor();
        editor.setEditorState(editor.parseEditorState(canonical));

        final exported = editor.editorState.toJson();

        expect(exported, equals(canonical));
      });

      test('projects to text without leaking markup', () {
        final editor = createHinataEditor();
        editor.setEditorState(editor.parseEditorState(canonical));

        final text = editor.editorState.read(() => $getRoot().getTextContent());

        expect(text.trim(), isNotEmpty, reason: 'lost all its text');
        expect(text, isNot(contains('{{')));
        expect(text, isNot(contains(':::')));
      });
    });
  }

  group('the dialect arrives as node types, not as syntax', () {
    Map<String, Object?> fixture(String name) =>
        jsonDecode(File('test/fixtures/richtext/$name.json').readAsStringSync())
            as Map<String, Object?>;

    LexicalEditor opened(String name) {
      final editor = createHinataEditor();
      editor.setEditorState(editor.parseEditorState(fixture(name)));
      return editor;
    }

    test('a callout is a CalloutNode carrying its kind', () {
      final editor = opened('callout');

      editor.editorState.read(() {
        final block = $getRoot().getFirstChild();
        expect(block, isA<CalloutNode>());
        expect((block! as CalloutNode).kind, CalloutKind.info);
        // Its content stays a document, which is why it is an element.
        expect((block as CalloutNode).childrenSize, greaterThan(0));
      });
    });

    test('a warn callout keeps block structure inside', () {
      final editor = opened('callout-with-list');

      editor.editorState.read(() {
        final block = $getRoot().getFirstChild()! as CalloutNode;
        expect(block.kind, CalloutKind.warn);
        expect(block.getFirstChild(), isA<ListNode>());
      });
    });

    test('smart links carry kind and target', () {
      final editor = opened('smart-links');

      editor.editorState.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        final chips = paragraph.children.whereType<SmartLinkNode>().toList();
        expect(chips.map((chip) => chip.kind), [
          SmartLinkKind.issue,
          SmartLinkKind.doc,
          SmartLinkKind.user,
        ]);
        expect(chips.first.targetId, 'HIN-5');
        // An issue key is readable, so it is the label; an ObjectId is not, so
        // there is none — that is what keeps ids out of the search index.
        expect(chips.first.label, 'HIN-5');
        expect(chips.last.label, isNull);
      });
    });

    test('a smart link is inline and atomic', () {
      final editor = opened('smart-links');

      editor.editorState.read(() {
        final paragraph = $getRoot().getFirstChild()! as ElementNode;
        final chip = paragraph.children.whereType<SmartLinkNode>().first;
        expect(chip.isInline, isTrue);
      });
    });
  });

  group('documents the app writes are documents the server can read', () {
    test('a chip the app creates round-trips through JSON', () {
      final editor = createHinataEditor();
      editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode('Siehe '))
          ..append(
            $createSmartLinkNode(
              kind: SmartLinkKind.issue,
              targetId: 'HIN-9',
              label: 'HIN-9',
            ),
          );
        $getRoot().append(paragraph);
      }, discrete: true);

      final json = editor.editorState.toJson();
      final reopened = createHinataEditor();
      reopened.setEditorState(reopened.parseEditorState(json));

      expect(reopened.editorState.toJson(), equals(json));
    });

    test('a callout the app creates round-trips through JSON', () {
      final editor = createHinataEditor();
      editor.update(() {
        final callout = $createCalloutNode(CalloutKind.tip)
          ..append($createParagraphNode()..append($createTextNode('Hinweis')));
        $getRoot().append(callout);
      }, discrete: true);

      final json = editor.editorState.toJson();
      final reopened = createHinataEditor();
      reopened.setEditorState(reopened.parseEditorState(json));

      expect(reopened.editorState.toJson(), equals(json));
    });
  });
}
