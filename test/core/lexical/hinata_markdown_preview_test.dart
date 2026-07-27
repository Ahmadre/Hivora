/// The composer's preview must agree with what the server will store.
///
/// The comment composer sends markdown and the server converts it. If this
/// client-side conversion disagrees, the preview is a promise the save breaks —
/// so these assert the same shapes the server's own converter test asserts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_lexical.dart';
import 'package:hinata/core/lexical/hinata_markdown_preview.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

void main() {
  Map<String, Object?>? convert(String markdown) {
    final doc = markdownToDocument(markdown);
    return doc == null ? null : jsonDecode(doc) as Map<String, Object?>;
  }

  List<Object?> blocks(String markdown) =>
      ((convert(markdown)!['root']! as Map<String, Object?>)['children']!
          as List<Object?>);

  Map<String, Object?> block(String markdown, [int index = 0]) =>
      blocks(markdown)[index]! as Map<String, Object?>;

  String textOf(String markdown) {
    final editor = createHinataEditor()
      ..setEditorState(
        createHinataEditor().parseEditorStateFromString(
          markdownToDocument(markdown)!,
        ),
      );
    return editor.editorState.read(() => $getRoot().getTextContent());
  }

  group('nothing to preview', () {
    test('an empty draft has no document', () {
      expect(markdownToDocument(''), isNull);
      expect(markdownToDocument('   \n '), isNull);
    });
  });

  group('the shapes the server also produces', () {
    test('a heading carries its tag', () {
      expect(block('## Titel')['type'], 'heading');
      expect(block('## Titel')['tag'], 'h2');
    });

    test('a bullet list is a list of items', () {
      expect(block('- eins\n- zwei')['type'], 'list');
      expect(block('- eins\n- zwei')['listType'], 'bullet');
    });

    test('a quote holds its text', () {
      expect(block('> Zitat')['type'], 'quote');
      expect(textOf('> Zitat'), 'Zitat');
    });

    test('a code block keeps its content literal', () {
      expect(block('```\n**nicht fett**\n```')['type'], 'code');
      expect(textOf('```\n**nicht fett**\n```'), contains('**nicht fett**'));
    });
  });

  group('the hinata dialect', () {
    test('a callout becomes a callout block, not three paragraphs', () {
      final callout = block(':::info\nGeprüft.\n:::');

      expect(callout['type'], 'callout');
      expect(callout['kind'], 'info');
      expect(textOf(':::info\nGeprüft.\n:::'), 'Geprüft.');
    });

    test('each flavour is preserved', () {
      for (final kind in ['info', 'warn', 'note', 'tip']) {
        expect(block(':::$kind\nText\n:::')['kind'], kind);
      }
    });

    test('a callout keeps block structure inside', () {
      final callout = block(':::warn\n- eins\n- zwei\n:::');

      final children = callout['children']! as List<Object?>;
      expect((children.first! as Map<String, Object?>)['type'], 'list');
    });

    test('a nested fence folds instead of leaving its marker on screen', () {
      const draft = ':::info\nAussen\n:::warn\nInnen\n:::\n:::';
      final outer = block(draft);

      expect(outer['type'], 'callout');
      expect(outer['kind'], 'info');
      final inner =
          (outer['children']! as List<Object?>).last! as Map<String, Object?>;
      expect(inner['type'], 'callout');
      expect(inner['kind'], 'warn');
      // The marker itself must not survive as text anywhere.
      expect(textOf(draft), isNot(contains(':::')));
      expect(blocks(draft), hasLength(1));
    });

    test('an unterminated fence stays text rather than eating the draft', () {
      // The failure that must not happen: a typo silently hiding everything
      // the writer typed after it.
      expect(textOf(':::tip\nDer Rest'), contains('Der Rest'));
      expect(block(':::tip\nDer Rest')['type'], isNot('callout'));
    });

    test('a mention becomes a smart link, not literal braces', () {
      final paragraph = block('Hallo {{user:507f1f77bcf86cd799439011}}');
      final children = paragraph['children']! as List<Object?>;
      final chip = children.last! as Map<String, Object?>;

      expect(chip['type'], 'smartlink');
      expect(chip['kind'], 'user');
      expect(chip['targetId'], '507f1f77bcf86cd799439011');
      // No readable label for an id — the same rule the server applies, which
      // is what keeps ObjectIds out of the search index.
      expect(chip['label'], isNull);
    });

    test('an issue key becomes a labelled chip', () {
      final children =
          block('Siehe {{issue:HIN-5}}')['children']! as List<Object?>;
      final chip = children.last! as Map<String, Object?>;

      expect(chip['kind'], 'issue');
      expect(chip['label'], 'HIN-5');
    });

    test('tokens inside a callout are converted too', () {
      final callout = block(':::info\nOwner {{issue:HIN-2}}\n:::');
      final paragraph =
          (callout['children']! as List<Object?>).first!
              as Map<String, Object?>;
      final children = paragraph['children']! as List<Object?>;

      expect((children.last! as Map<String, Object?>)['type'], 'smartlink');
    });
  });

  group('the same document the server would store', () {
    // Not "a document of roughly the same shape": these fixtures were produced
    // by the server's own converter from exactly these markdown strings
    // (hinata-server RichTextCorpusTest). A deep comparison against them is the
    // only assertion that can tell the preview is honest — and it keeps
    // catching drift when either converter changes.
    const corpus = {
      'image': '![Ringelblumen](https://example.org/f.jpg)',
      'table':
          '| View | Groups by |\n|---|---|\n'
          '| Board | Status |\n| Backlog | Sprint |',
      'rule': 'davor\n\n---\n\ndanach',
    };

    for (final entry in corpus.entries) {
      test('${entry.key} converts to exactly what the server writes', () {
        final fixture = File(
          'test/fixtures/richtext/${entry.key}.json',
        ).readAsStringSync();

        expect(convert(entry.value), jsonDecode(fixture));
      });
    }

    test('an image is an image, not a link behind a stray exclamation', () {
      final paragraph = block('![Ringelblumen](https://example.org/f.jpg)');
      final children = paragraph['children']! as List<Object?>;

      expect(children, hasLength(1));
      expect((children.single! as Map<String, Object?>)['type'], 'image');
    });

    test('a pipe table is a table, not paragraphs of pipes', () {
      expect(block('| a | b |\n|---|---|\n| 1 | 2 |')['type'], 'table');
    });

    test('a rule is a divider, not the characters that spell one', () {
      for (final marker in ['---', '***', '___', '-----']) {
        expect(
          block('davor\n\n$marker\n\ndanach', 1)['type'],
          'horizontalrule',
          reason: '$marker stayed text',
        );
      }
    });

    test('dashes inside a code block stay content', () {
      // The pre-pass must not reach into a block that means them literally.
      expect(block('```\n---\n```')['type'], 'code');
      expect(textOf('```\n---\n```'), contains('---'));
    });
  });

  group('what it produces is openable', () {
    test('the preview document is a fixed point', () {
      const draft = '''
# Titel

Ein Absatz mit **fett** und {{issue:HIN-1}}.

:::warn
Vorsicht.
:::

- [x] fertig
''';
      final json = markdownToDocument(draft)!;

      final editor = createHinataEditor()
        ..setEditorState(createHinataEditor().parseEditorStateFromString(json));

      expect(
        jsonEncode(editor.editorState.toJson()),
        jsonEncode(jsonDecode(json)),
      );
    });

    test('an unconvertible draft yields nothing rather than throwing', () {
      // Whatever the importer chokes on, the composer must keep working.
      expect(() => markdownToDocument('```\nunclosed fence'), returnsNormally);
    });
  });
}
