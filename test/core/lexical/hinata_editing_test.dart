/// The block operations the toolbar performs.
///
/// These rewrite the document tree by hand, which is the part of an editor
/// where a mistake destroys content rather than merely looking wrong — a
/// conversion that drops the words is silent and permanent. So every case
/// asserts the text survived, not just that the block type changed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_editing.dart';
import 'package:hinata/core/lexical/hinata_lexical.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

void main() {
  late LexicalEditor editor;

  setUp(() {
    editor = createHinataEditor();
  });

  /// Seeds a single paragraph and puts the caret in it.
  void seedParagraph(String text) {
    editor.update(() {
      final paragraph = $createParagraphNode()..append($createTextNode(text));
      $getRoot()
        ..clear()
        ..append(paragraph);
      paragraph.selectEnd();
    }, discrete: true);
  }

  /// Reads something off the root's first block, inside a scope.
  ///
  /// Takes a reader rather than returning the node: a node accessor outside an
  /// active read throws, and handing the node back all but invites that.
  R onFirstBlock<R>(R Function(LexicalNode block) read) =>
      editor.editorState.read(() => read($getRoot().getFirstChild()!));

  String allText() =>
      editor.editorState.read(() => $getRoot().getTextContent());

  void apply(BlockKind kind, {CalloutKind callout = CalloutKind.info}) {
    editor.update(() => $setBlockKind(kind, callout: callout), discrete: true);
  }

  group('converting a paragraph', () {
    for (final entry in {
      BlockKind.heading1: HeadingTag.h1,
      BlockKind.heading2: HeadingTag.h2,
      BlockKind.heading3: HeadingTag.h3,
    }.entries) {
      test('${entry.key.name} becomes a ${entry.value.name} heading', () {
        seedParagraph('Titel');

        apply(entry.key);

        expect(onFirstBlock((b) => (b as HeadingNode).tag), entry.value);
        expect(allText(), 'Titel');
      });
    }

    test('quote keeps the text', () {
      seedParagraph('Ein Zitat');

      apply(BlockKind.quote);

      expect(onFirstBlock((b) => b), isA<QuoteNode>());
      expect(allText(), 'Ein Zitat');
    });

    test('code keeps the text', () {
      seedParagraph('void main() {}');

      apply(BlockKind.code);

      expect(onFirstBlock((b) => b), isA<CodeNode>());
      expect(allText(), 'void main() {}');
    });

    test('a callout wraps its content in a paragraph', () {
      seedParagraph('Achtung');

      apply(BlockKind.callout, callout: CalloutKind.warn);

      editor.editorState.read(() {
        final callout = $getRoot().getFirstChild()! as CalloutNode;
        expect(callout.kind, CalloutKind.warn);
        // A callout holds blocks, not inline content — nesting text directly
        // would be an illegal tree.
        expect(callout.getFirstChild(), isA<ParagraphNode>());
      });
      expect(allText(), 'Achtung');
    });
  });

  group('lists', () {
    for (final entry in {
      BlockKind.bulletList: ListType.bullet,
      BlockKind.numberList: ListType.number,
      BlockKind.checkList: ListType.check,
    }.entries) {
      test('${entry.key.name} becomes a ${entry.value.name} list', () {
        seedParagraph('Punkt');

        apply(entry.key);

        expect(onFirstBlock((b) => (b as ListNode).listType), entry.value);
        expect(allText(), 'Punkt');
      });
    }

    test('switching list type keeps the items', () {
      seedParagraph('Punkt');
      apply(BlockKind.bulletList);

      apply(BlockKind.numberList);

      expect(onFirstBlock((b) => (b as ListNode).listType), ListType.number);
      expect(allText(), 'Punkt');
    });

    test('applying the same list again unwraps it back to a paragraph', () {
      seedParagraph('Punkt');
      apply(BlockKind.bulletList);

      apply(BlockKind.bulletList);

      expect(onFirstBlock((b) => b), isA<ParagraphNode>());
      expect(allText(), 'Punkt');
    });

    test('a list converted to a heading keeps the words', () {
      // The dangerous direction: a list item's text is one level deeper than a
      // paragraph's, so a naive move drops it.
      seedParagraph('Punkt');
      apply(BlockKind.bulletList);

      apply(BlockKind.heading2);

      expect(onFirstBlock((b) => (b as HeadingNode).tag), HeadingTag.h2);
      expect(allText(), 'Punkt');
    });

    test('a callout converted back to a paragraph keeps the words', () {
      seedParagraph('Achtung');
      apply(BlockKind.callout);

      apply(BlockKind.callout);

      expect(onFirstBlock((b) => b), isA<ParagraphNode>());
      expect(allText(), 'Achtung');
    });
  });

  group('toggling back', () {
    test('applying the same heading again returns to a paragraph', () {
      seedParagraph('Titel');
      apply(BlockKind.heading1);

      apply(BlockKind.heading1);

      expect(onFirstBlock((b) => b), isA<ParagraphNode>());
      expect(allText(), 'Titel');
    });

    test('the pressed state reflects the caret', () {
      seedParagraph('Titel');

      expect(
        editor.editorState.read(() => $blockKindIs(BlockKind.paragraph)),
        isTrue,
      );
      apply(BlockKind.quote);
      expect(
        editor.editorState.read(() => $blockKindIs(BlockKind.quote)),
        isTrue,
      );
      expect(
        editor.editorState.read(() => $blockKindIs(BlockKind.heading1)),
        isFalse,
      );
    });
  });

  group('inserting', () {
    test('a divider leaves somewhere to keep typing', () {
      // A rule at the very end with no paragraph after it is a document the
      // writer cannot add to.
      seedParagraph('davor');

      editor.update($insertDivider, discrete: true);

      editor.editorState.read(() {
        final children = $getRoot().children.toList();
        expect(children[1], isA<HorizontalRuleNode>());
        expect(children[2], isA<ParagraphNode>());
      });
    });

    test('a smart link lands at the caret and survives a round trip', () {
      seedParagraph('Siehe ');

      editor.update(
        () => $insertSmartLink(
          kind: SmartLinkKind.issue,
          targetId: 'HIN-7',
          label: 'HIN-7',
        ),
        discrete: true,
      );

      final json = editor.editorState.toJson();
      final reopened = createHinataEditor()
        ..setEditorState(createHinataEditor().parseEditorState(json));
      expect(reopened.editorState.toJson(), equals(json));
      expect(allText(), contains('HIN-7'));
    });
  });

  group('the document stays valid', () {
    test('every conversion produces a document that reopens unchanged', () {
      for (final kind in BlockKind.values) {
        seedParagraph('Inhalt');
        apply(kind);

        final json = editor.editorState.toJson();
        final reopened = createHinataEditor()
          ..setEditorState(createHinataEditor().parseEditorState(json));

        expect(
          reopened.editorState.toJson(),
          equals(json),
          reason: '${kind.name} produced a document that does not round-trip',
        );
      }
    });
  });
}
