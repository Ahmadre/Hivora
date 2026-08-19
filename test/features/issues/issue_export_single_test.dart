/// Exporting a single issue, from the app's side.
///
/// The documents themselves are the server's, so what is left here is the part
/// the client owns and can get wrong on its own: which URL each menu entry asks
/// for, what the saved file ends up called, and that a refusal arrives as the
/// server's own words instead of a generic sentence.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_detail_sheet.dart';

void main() {
  Issue issue(String readableId, String title) => Issue(
    id: 'i1',
    projectId: 'p1',
    readableId: readableId,
    title: title,
    state: 'Open',
  );

  group('the export choices', () {
    test('every file format knows its suffix and its media type', () {
      for (final choice in IssueExportChoice.values) {
        if (choice == IssueExportChoice.print) continue;
        expect(choice.extension, isNotNull, reason: choice.name);
        expect(choice.mimeType, isNotNull, reason: choice.name);
      }
    });

    /// Printing is the PDF plus the platform's dialog, not a format of its own —
    /// which is what keeps a printed issue and a saved one identical.
    test('print carries no format of its own', () {
      expect(IssueExportChoice.print.extension, isNull);
      expect(IssueExportChoice.print.mimeType, isNull);
    });

    test('the media types are the ones Word and Excel actually register', () {
      expect(
        IssueExportChoice.docx.mimeType,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(
        IssueExportChoice.xlsx.mimeType,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    });

    test('every entry has a label key under issues.export', () {
      for (final choice in IssueExportChoice.values) {
        expect(choice.labelKey, 'issues.export.${choice.name}');
      }
    });
  });

  group('the download file name', () {
    test('is the readable id and the title', () {
      expect(
        issueExportFileName(
          issue('HIN-50', 'Einzelnes Issue exportieren'),
          'pdf',
        ),
        'HIN-50-Einzelnes-Issue-exportieren.pdf',
      );
    });

    /// The same rule the server applies, so the saved file matches the name the
    /// server put in Content-Disposition rather than diverging from it.
    test('drops everything that is not a letter or a digit', () {
      final name = issueExportFileName(
        issue('HIN-50', 'evil\r\nX-Injected: yes"; filename="owned/../x'),
        'xml',
      );

      expect(name, endsWith('.xml'));
      expect(name, isNot(contains('\r')));
      expect(name, isNot(contains('\n')));
      expect(name, isNot(contains('"')));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('..')));
    });

    test('keeps letters from any script', () {
      expect(
        issueExportFileName(issue('HIN-50', 'Grüße & Kalender'), 'docx'),
        'HIN-50-Grüße-Kalender.docx',
      );
    });

    test('stays short enough for a file system', () {
      final name = issueExportFileName(issue('HIN-50', 'x' * 400), 'xlsx');

      expect(name.length, lessThanOrEqualTo(85));
      expect(name, endsWith('.xlsx'));
    });

    test('a title of pure punctuation still produces a name', () {
      expect(issueExportFileName(issue('', '///'), 'pdf'), 'issue.pdf');
    });
  });

  group('fetching an export', () {
    test('asks for the format the entry stands for', () async {
      final api = _FakeApi();

      await fetchIssueExport(api, 'i1', 'docx');

      expect(api.lastPath, '/api/v1/issues/i1/export.docx');
      // A document the server has to render needs longer than a row does.
      expect(api.lastReceiveTimeout, isNotNull);
    });

    /// A refused or throttled export has something worth saying, and the point
    /// of going through the failing fetch is that it survives to the toast.
    test('lets the server’s own message through', () async {
      final api = _FakeApi(
        failure: ApiFailure('Zu viele Exporte', statusCode: 429),
      );

      expect(
        () => fetchIssueExport(api, 'i1', 'pdf'),
        throwsA(
          isA<ApiFailure>()
              .having((f) => f.message, 'message', 'Zu viele Exporte')
              .having((f) => f.statusCode, 'statusCode', 429),
        ),
      );
    });
  });
}

class _FakeApi implements ApiClient {
  _FakeApi({this.failure});

  Object? failure;
  String? lastPath;
  Duration? lastReceiveTimeout;

  @override
  Future<Uint8List> getFileBytes(
    String path, {
    Duration? receiveTimeout,
  }) async {
    lastPath = path;
    lastReceiveTimeout = receiveTimeout;
    if (failure != null) throw failure!;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
