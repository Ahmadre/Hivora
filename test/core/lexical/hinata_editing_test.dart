/// The block operations the toolbar performs.
///
/// These rewrite the document tree by hand, which is the part of an editor
/// where a mistake destroys content rather than merely looking wrong — a
/// conversion that drops the words is silent and permanent. So every case
/// asserts the text survived, not just that the block type changed.
library;

import 'dart:io';

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

  /// Puts the caret in the first piece of text anywhere in the document.
  ///
  /// The caret a writer actually has when they reach for a toolbar button: it
  /// is inside whatever block they are in, however deeply that block nests.
  void caretInFirstText() {
    editor.update(() {
      TextNode? first;
      void walk(ElementNode element) {
        for (final child in element.children) {
          if (first != null) return;
          if (child is TextNode) {
            first = child;
            return;
          }
          if (child is ElementNode) walk(child);
        }
      }

      walk($getRoot());
      first?.selectEnd();
    }, discrete: true);
  }

  /// Seeds the root with the blocks [build] returns, caret in the first text.
  void seedBlocks(List<LexicalNode> Function() build) {
    editor.update(() {
      $getRoot()
        ..clear()
        ..appendAll(build());
    }, discrete: true);
    caretInFirstText();
  }

  /// Seeds a stored fixture — a real document from the server's own converter.
  void seedFixture(String name) {
    final json = File('test/fixtures/richtext/$name.json').readAsStringSync();
    editor.setEditorState(editor.parseEditorStateFromString(json));
    caretInFirstText();
  }

  /// The type string of every top-level block.
  List<String> blockTypes() => editor.editorState.read(
    () => $getRoot().children.map((node) => node.type).toList(),
  );

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

  group('shapes the toolbar does not model are left alone', () {
    test('no block button touches a table', () {
      // The data-loss case: every cell flattened into one heading, the rows
      // and the table itself gone, and the result still stores and still
      // round-trips — so nothing anywhere reports a problem.
      seedFixture('table');
      final before = allText();

      for (final kind in BlockKind.values) {
        apply(kind);

        expect(
          onFirstBlock((b) => b),
          isA<TableNode>(),
          reason: '${kind.name} replaced the table',
        );
        expect(allText(), before, reason: '${kind.name} changed the text');
        expect(blockTypes(), ['table']);
      }
    });

    test('a selection of the root itself is not replaced', () {
      // `root.replace` throws, uncaught, inside the update. Not reachable from
      // the toolbar today; nothing should make it reachable tomorrow either.
      seedParagraph('Inhalt');
      editor.update(() => $getRoot().select(), discrete: true);

      expect(() => apply(BlockKind.heading1), returnsNormally);
      expect(allText(), 'Inhalt');
    });
  });

  group('converting a container keeps its blocks apart', () {
    test('a three-item list becomes three headings, not one', () {
      seedBlocks(() {
        final list = $createListNode(ListType.bullet);
        for (final text in ['Eins', 'Zwei', 'Drei']) {
          list.append($createListItemNode()..append($createTextNode(text)));
        }
        return [list];
      });

      apply(BlockKind.heading2);

      expect(blockTypes(), ['heading', 'heading', 'heading']);
      // The failure this pins: "EinsZweiDrei" in a single heading. Every
      // character survived that too — only the boundaries did not.
      expect(allText(), 'Eins\n\nZwei\n\nDrei');
    });

    test('a callout holding a list unwraps into one block per item', () {
      seedBlocks(() {
        final list = $createListNode(ListType.bullet)
          ..append($createListItemNode()..append($createTextNode('A')))
          ..append($createListItemNode()..append($createTextNode('B')));
        return [
          $createCalloutNode(CalloutKind.info)
            ..append($createParagraphNode()..append($createTextNode('Kopf')))
            ..append(list),
        ];
      });

      // Toggling the callout off.
      apply(BlockKind.callout);

      expect(blockTypes(), ['paragraph', 'paragraph', 'paragraph']);
      expect(allText(), 'Kopf\n\nA\n\nB');
    });

    test('unwrapping a nested list keeps the levels apart', () {
      seedBlocks(() {
        final inner = $createListNode(ListType.bullet)
          ..append($createListItemNode()..append($createTextNode('Innen')));
        return [
          $createListNode(ListType.bullet)
            ..append($createListItemNode()..append($createTextNode('Aussen')))
            ..append($createListItemNode()..append(inner)),
        ];
      });

      apply(BlockKind.bulletList);

      expect(blockTypes(), ['paragraph', 'paragraph']);
      expect(allText(), 'Aussen\n\nInnen');
    });

    test('a list converted to a callout keeps the list a list', () {
      // `callout > paragraph > [listitem, listitem]` round-trips and renders,
      // and is a tree no other Lexical client can read.
      seedBlocks(() {
        final list = $createListNode(ListType.bullet)
          ..append($createListItemNode()..append($createTextNode('eins')))
          ..append($createListItemNode()..append($createTextNode('zwei')));
        return [list];
      });

      apply(BlockKind.callout, callout: CalloutKind.warn);

      editor.editorState.read(() {
        final callout = $getRoot().getFirstChild()! as CalloutNode;
        expect(callout.kind, CalloutKind.warn);
        final inner = callout.getFirstChild();
        expect(inner, isA<ListNode>());
        // Every list item still has a list for a parent.
        for (final item in (inner! as ListNode).children) {
          expect(item, isA<ListItemNode>());
        }
      });
      expect(allText(), 'eins\n\nzwei');
    });

    test('a callout of two paragraphs becomes two bullets', () {
      seedBlocks(
        () => [
          $createCalloutNode(CalloutKind.note)
            ..append($createParagraphNode()..append($createTextNode('Eins')))
            ..append($createParagraphNode()..append($createTextNode('Zwei'))),
        ],
      );

      apply(BlockKind.bulletList);

      editor.editorState.read(() {
        final list = $getRoot().getFirstChild()! as ListNode;
        expect(list.childrenSize, 2);
      });
      expect(allText(), 'Eins\n\nZwei');
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
