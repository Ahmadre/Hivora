/// Typing `@` produces one of hinata's chips, not the bundle's mention.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_editor.dart';
import 'package:hinata/core/lexical/hinata_editor_controller.dart';
import 'package:hinata/core/lexical/hinata_lexical.dart';
import 'package:hinata/core/lexical/hinata_mentions.dart';
import 'package:hinata/features/knowledge/markdown/smart_link_resolver.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// A resolver with one person and one issue in it.
class _TwoThingsResolver extends SmartLinkResolver {
  @override
  SmartDoc? doc(String id) => null;

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
      const [
        MentionCandidate(
          kind: 'user',
          id: 'u1',
          title: 'Jonas Becker',
          sub: 'jonas@example.org',
        ),
        MentionCandidate(
          kind: 'issue',
          id: 'HIN-5',
          title: 'Wire up the picker',
          sub: 'Open',
        ),
      ];
}

void main() {
  group('the typeahead', () {
    test('there is none without a resolver', () {
      // A menu that can never have a row is worse than no menu, and `@` should
      // stay the plain character it is.
      expect(
        hinataMentions(editor: createHinataEditor(), resolver: null),
        isNull,
      );
    });

    test('`@` finds people and issues in one list', () async {
      final mentions = hinataMentions(
        editor: createHinataEditor(),
        resolver: _TwoThingsResolver(),
      )!;

      expect(mentions.triggers.single.character, '@');

      final found = await mentions.source.search(
        const MentionQuery(text: '', mentionType: 'user'),
      );

      expect(found.map((suggestion) => suggestion.mentionType), [
        'user',
        'issue',
      ]);
      // Without the trigger character: the label builder prepends it, and
      // `@Jonas Becker` behind an `@` would insert `@@Jonas Becker`.
      expect(found.first.label, 'Jonas Becker');
    });

    test('the search source is equal for the same resolver', () {
      // `MentionScope` throws its search controller away when the source is not
      // `==` to the last one, and the editor rebuilds on every keystroke — so
      // an unequal source closes the picker on the first character after `@`.
      final resolver = _TwoThingsResolver();
      final editor = createHinataEditor();

      expect(
        hinataMentions(editor: editor, resolver: resolver)!.source,
        hinataMentions(editor: editor, resolver: resolver)!.source,
      );
    });
  });

  group('what an accepted suggestion leaves behind', () {
    Future<LexicalEditor> accept(MentionSuggestion suggestion) async {
      final editor = createHinataEditor();
      final mentions = hinataMentions(
        editor: editor,
        resolver: _TwoThingsResolver(),
      )!;

      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()..append(
              $createMentionNode(
                text: '@${suggestion.label}',
                mentionType: suggestion.mentionType,
                mentionId: suggestion.id,
              ),
            ),
          );
      }, discrete: true);

      mentions.onInserted!(suggestion);
      await Future<void>.delayed(Duration.zero);
      return editor;
    }

    test('a person becomes a smart link resolved live', () async {
      final editor = await accept(
        const MentionSuggestion(
          id: 'u1',
          label: 'Jonas Becker',
          mentionType: 'user',
        ),
      );

      // Plain values, not the node: it must not escape the read scope.
      final link = editor.editorState.read(() {
        final first = ($getRoot().getFirstChild()! as ElementNode)
            .getFirstChild();
        return first is SmartLinkNode
            ? (kind: first.kind, targetId: first.targetId, label: first.label)
            : null;
      });

      expect(link, isNotNull);
      expect(link!.kind, SmartLinkKind.user);
      expect(link.targetId, 'u1');
      // No denormalised label: an ObjectId is not readable and a stale name is
      // worse than the live one, so a person is resolved when the chip is built.
      expect(link.label, isNull);
    });

    test('an issue keeps its readable key as the label', () async {
      final editor = await accept(
        const MentionSuggestion(
          id: 'HIN-5',
          label: 'Wire up the picker',
          mentionType: 'issue',
        ),
      );

      final link = editor.editorState.read(() {
        final first =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as SmartLinkNode;
        return (kind: first.kind, label: first.label);
      });

      expect(link.kind, SmartLinkKind.issue);
      expect(link.label, 'Wire up the picker');
    });

    test('accepting from inside an open update still swaps', () async {
      // Accepting with Enter arrives through a command handler, so an update is
      // already open — and a nested `editor.update()` throws outright, which
      // would leave the bundle's grey word in the document and the exception in
      // the console.
      final editor = createHinataEditor();
      final mentions = hinataMentions(
        editor: editor,
        resolver: _TwoThingsResolver(),
      )!;
      const suggestion = MentionSuggestion(
        id: 'u1',
        label: 'Jonas Becker',
        mentionType: 'user',
      );

      editor.update(() {
        $getRoot()
          ..clear()
          ..append(
            $createParagraphNode()..append(
              $createMentionNode(
                text: '@Jonas Becker',
                mentionType: 'user',
                mentionId: 'u1',
              ),
            ),
          );
        mentions.onInserted!(suggestion);
      }, discrete: true);

      expect(editor.toJsonString(), contains('"smartlink"'));
      expect(editor.toJsonString(), isNot(contains('"mention"')));
    });

    test('nothing of the stand-in is left in the stored document', () async {
      // A `mention` node reaching the server is the regression this whole path
      // exists to avoid: it round-trips, so nobody notices until the chip is
      // a grey word in someone else's client.
      final editor = await accept(
        const MentionSuggestion(
          id: 'u1',
          label: 'Jonas Becker',
          mentionType: 'user',
        ),
      );

      expect(editor.toJsonString(), isNot(contains('"mention"')));
      expect(editor.toJsonString(), contains('"smartlink"'));
    });
  });

  group('the editor wires it up', () {
    testWidgets('a host with a resolver gets the picker, one without does '
        'not', (tester) async {
      tester.view
        ..physicalSize = const Size(900, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<LexicalMentions?> pump({required bool scoped}) async {
        final controller = HinataEditorController();
        addTearDown(controller.dispose);
        final editor = HinataEditor(controller: controller);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: scoped
                    ? SmartLinkScope(
                        resolver: _TwoThingsResolver(),
                        child: editor,
                      )
                    : editor,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widget<LexicalEditorField>(find.byType(LexicalEditorField))
            .mentions;
      }

      expect(await pump(scoped: true), isNotNull);
      expect(await pump(scoped: false), isNull);
    });
  });
}
