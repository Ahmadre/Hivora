/// Reading an outline and a document's references back out of stored JSON.
///
/// Both run on the hot path — the outline on every article open, the smart-link
/// scan once per comment, per pinned comment and per loaded reply, from seven
/// call sites including live-update handlers. They are cheap only if they stay
/// cheap, and correct only if they keep answering from the document rather than
/// from a pattern match over text that no longer contains the tokens.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_lexical.dart';
import 'package:hinata/core/lexical/hinata_outline.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/richtext/$name.json').readAsStringSync();

  LexicalEditor open(String doc) {
    final editor = createHinataEditor();
    editor.setEditorState(editor.parseEditorStateFromString(doc));
    return editor;
  }

  group('the outline', () {
    test('lists h1–h3 in document order and stops there', () {
      // `headings` is `# Eins`, `## Zwei`, `### Drei`, `###### Sechs`.
      final entries = documentOutline(open(fixture('headings')));

      expect(entries.map((e) => e.text), ['Eins', 'Zwei', 'Drei']);
      expect(entries.map((e) => e.level), [1, 2, 3]);
    });

    test('an article without headings has an empty outline', () {
      expect(documentOutline(open(fixture('paragraph'))), isEmpty);
    });
  });

  group('smart links in a stored document', () {
    test('the referenced issues come back in order, deduplicated', () {
      expect(smartLinksIn(fixture('smart-links'), SmartLinkKind.issue), [
        'HIN-5',
      ]);
      expect(smartLinksIn(fixture('mixed'), SmartLinkKind.issue), ['HIN-1']);
    });

    test('links nested inside a callout are found', () {
      // `mixed` carries its user mention inside a callout, one level down from
      // the root — a walk that only looked at top-level blocks would miss it.
      expect(smartLinksIn(fixture('mixed'), SmartLinkKind.user), [
        '507f191e810c19729de860ea',
      ]);
    });

    test('nothing to read gives nothing back rather than throwing', () {
      expect(smartLinksIn(null, SmartLinkKind.issue), isEmpty);
      expect(smartLinksIn('', SmartLinkKind.issue), isEmpty);
      expect(smartLinksIn('{ not json', SmartLinkKind.issue), isEmpty);
    });
  });
}
