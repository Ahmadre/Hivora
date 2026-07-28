/// Saving an article, and the one way that can destroy one.
///
/// The server backfills markdown into Lexical, but the migration has an
/// explicit per-row failure branch that logs and leaves the document null. On
/// those rows the editor used to open blank over content that was still there,
/// and the next Save wrote the blankness back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/article_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';
import 'package:hinata/features/knowledge/knowledge_editor.dart';
import 'package:hinata/features/knowledge/knowledge_scope.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late KnowledgeRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    // Never called: the editor only reads `repo.spaces`, which is empty until
    // something loads it. It exists because the scope demands one.
    final api = ApiClient(storage);
    repo = KnowledgeRepository(
      articles: ArticleRepository(api),
      users: UserRepository(api),
      auth: AuthRepository(api),
    );
  });

  Future<List<EditorResult>> pumpEditor(
    WidgetTester tester, {
    required String? initialDoc,
    required String initialBody,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final saved = <EditorResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeScope(
            repo: repo,
            openArticle: (_) {},
            openUser: (_) {},
            child: KnowledgeEditor(
              isNew: false,
              initialTitle: 'Titel',
              initialDoc: initialDoc,
              initialBody: initialBody,
              spaceId: '',
              onSave: saved.add,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('an article the backfill skipped opens with its content', (
    tester,
  ) async {
    final saved = await pumpEditor(
      tester,
      initialDoc: null,
      initialBody: '# Titel\n\nInhalt, die es noch gibt.',
    );

    // No localization delegate: `context.t` echoes the raw key.
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.doc, contains('Inhalt, die es noch gibt.'));
  });

  testWidgets('saving refuses to write an empty document over content', (
    tester,
  ) async {
    // A stored document that cannot be opened: the controller starts blank
    // rather than refusing to open the page at all, which is right — and makes
    // the Save button one click away from erasing the article.
    final saved = await pumpEditor(
      tester,
      initialDoc: '{ not json',
      initialBody: 'Inhalt, die es noch gibt.',
    );

    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.text('knowledge.saveWouldBlank'), findsOneWidget);
  });
}
