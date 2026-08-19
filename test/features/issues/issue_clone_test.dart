/// Cloning an issue, from the app's side.
///
/// Two things live here that are genuinely the client's job. The prefilled
/// summary has to be valid before the user ever touches it — the server bounds
/// the title at 300 characters, and a prefix that pushes a long title past that
/// would turn "clone" into a validation error nobody caused. And the request
/// itself has to say exactly what the two switches said, because every field
/// the dialog does not send is a field the server decides on its own.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/issues/issue_detail_sheet.dart';

void main() {
  group('the prefilled summary', () {
    test('offers the original behind the clone prefix', () {
      expect(
        cloneTitlePrefill('Kalender & Schichtplanung'),
        '${kIssueClonePrefix}Kalender & Schichtplanung',
      );
    });

    test('stays inside the length the server accepts', () {
      final prefill = cloneTitlePrefill('x' * 400);

      expect(prefill.length, kIssueTitleMaxChars);
    });

    /// A title long enough to need cutting is the one where the reader needs
    /// the word CLONE most — so the cut takes the tail, never the prefix.
    test('keeps the prefix when the original has to be cut', () {
      final prefill = cloneTitlePrefill('x' * 400);

      expect(prefill, startsWith(kIssueClonePrefix));
      expect(
        prefill.substring(kIssueClonePrefix.length),
        'x' * (kIssueTitleMaxChars - kIssueClonePrefix.length),
      );
    });

    /// Cutting between the halves of a surrogate pair leaves a lone surrogate,
    /// which is not a character at all — it renders as a replacement box and
    /// travels to the server as broken text.
    test('never cuts an emoji in half', () {
      // 🐝 is one code point, two UTF-16 code units — repeated past the bound so
      // the cut lands exactly between the halves of one of them.
      final prefill = cloneTitlePrefill('🐝' * 200);

      expect(prefill.length, lessThanOrEqualTo(kIssueTitleMaxChars));
      expect(prefill.runes.every((rune) => rune != 0xFFFD), isTrue);
      // Round-tripping proves no half-character survived the cut.
      expect(String.fromCharCodes(prefill.runes), prefill);
    });

    test('leaves a short title untouched apart from the prefix', () {
      final prefill = cloneTitlePrefill('Short');

      expect(prefill.length, lessThan(kIssueTitleMaxChars));
      expect(prefill, 'CLONE - Short');
    });
  });

  group('the summary length cap', () {
    const cap = IssueTitleLengthLimit();

    TextEditingValue v(String text) => TextEditingValue(text: text);

    test('lets anything inside the bound through', () {
      expect(cap.formatEditUpdate(v('a' * 299), v('a' * 300)).text, 'a' * 300);
    });

    /// The server counts UTF-16 code units. A grapheme-counting cap would let
    /// 300 emoji (600 units) through and turn Klonen into a 400.
    test('counts the units the server counts, not characters', () {
      final tooLong = v('🐝' * 151); // 302 UTF-16 units, 151 characters
      final before = v('🐝' * 150);

      expect(cap.formatEditUpdate(before, tooLong).text, before.text);
    });

    test('an overflowing paste leaves what was there, not a clipped tail', () {
      final before = v('CLONE - keep me');

      expect(
        cap.formatEditUpdate(before, v('x' * 400)).text,
        'CLONE - keep me',
      );
    });
  });

  group('IssueRepository.cloneIssue', () {
    test('posts the four choices the dialog collects and nothing else', () async {
      final api = _FakeApi();
      final repo = IssueRepository(api);

      final copy = await repo.cloneIssue(
        'i1',
        title: 'CLONE - Kalender',
        assigneeIds: ['u2'],
        includeLinks: true,
        includeSprint: false,
      );

      expect(api.lastPath, '/api/v1/issues/i1/clone');
      // Every other field of a clone is the server's decision; sending more here
      // would be a second, divergent definition of what a clone is.
      expect(api.lastBody, {
        'title': 'CLONE - Kalender',
        'assigneeIds': ['u2'],
        'includeLinks': true,
        'includeSprint': false,
      });
      expect(copy.readableId, 'HIN-2');
    });

    test('sends an empty assignee list rather than omitting it', () async {
      final api = _FakeApi();
      final repo = IssueRepository(api);

      await repo.cloneIssue(
        'i1',
        title: 'CLONE - unassigned',
        assigneeIds: const [],
        includeLinks: false,
        includeSprint: false,
      );

      // Omitting it would read as "no opinion" and could inherit the original's
      // assignee; the dialog's cleared field has to mean cleared.
      expect(api.lastBody?['assigneeIds'], isEmpty);
    });

    test('lets a failure through so the dialog can keep the input', () async {
      final api = _FakeApi(failure: ApiFailure('errors.connection'));
      final repo = IssueRepository(api);

      expect(
        () => repo.cloneIssue(
          'i1',
          title: 'CLONE - Kalender',
          assigneeIds: const [],
          includeLinks: false,
          includeSprint: false,
        ),
        throwsA(isA<ApiFailure>()),
      );
    });
  });
}

class _FakeApi implements ApiClient {
  _FakeApi({this.failure});

  Object? failure;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    lastPath = path;
    lastBody = body as Map<String, dynamic>?;
    if (failure != null) throw failure!;
    return {
      'id': 'i2',
      'projectId': 'p1',
      'readableId': 'HIN-2',
      'title': lastBody?['title'],
      'state': 'Backlog',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
