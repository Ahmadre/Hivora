import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/content_refused_dialog.dart';

/// Locks the two things the moderation UI shares with the backend and cannot
/// verify at compile time: the wire vocabulary of a report, and the status code
/// that means "your content was refused" rather than "your request was wrong".
void main() {
  group('ReportReason wire mapping', () {
    test('round-trips every reason', () {
      for (final reason in ReportReason.values) {
        expect(ReportReason.fromWire(reason.wire), reason);
      }
    });

    test('falls back to other for an unknown or missing value', () {
      // A server that grows a reason this build has never heard of must not be
      // able to make a report un-renderable.
      expect(ReportReason.fromWire('BRAND_NEW_CATEGORY'), ReportReason.other);
      expect(ReportReason.fromWire(null), ReportReason.other);
    });

    test('maps onto the pipeline vocabulary where one exists', () {
      // Every mapped reason must name a real ModerationCategory constant, since
      // the queue files reports and automated verdicts under the same heading.
      const categories = {
        'SEXUAL',
        'SEXUAL_MINORS',
        'VIOLENCE',
        'VIOLENT_THREAT',
        'HATE',
        'HARASSMENT',
        'SELF_HARM',
        'EXTREMISM',
        'ILLEGAL',
        'MALWARE',
      };
      for (final reason in ReportReason.values) {
        if (reason.category != null) {
          expect(categories, contains(reason.category));
        }
      }
      // The two the classifier never produces stay uncategorised rather than
      // being filed under a heading no machine could have written.
      expect(ReportReason.spam.category, isNull);
      expect(ReportReason.other.category, isNull);
    });

    test('uses distinct i18n keys for the label and its hint', () {
      // i18next splits on dots, so a reason cannot be both a string and the
      // parent of its own `.hint` — the `.label` suffix is what keeps them apart.
      expect(ReportReason.hate.labelKey, 'moderation.reason.hate.label');
      expect(ReportReason.hate.hintKey, 'moderation.reason.hate.hint');
    });
  });

  group('ReportTarget payload', () {
    test('carries type, id and the container a nested item needs', () {
      final json = ReportTarget.comment(
        commentId: 'c1',
        issueId: 'i1',
      ).toJson();
      // The request binds a Java enum constant, so the type goes over upper-case
      // — the queue's own lower-case entity kind would not deserialize at all.
      expect(json['targetType'], 'COMMENT');
      expect(json['targetId'], 'c1');
      // `contextId` is what the report record calls the owning issue; a
      // `parentId` would be dropped, and an attachment report rejected for
      // having no context.
      expect(json['contextId'], 'i1');
    });

    test('omits the container when the target stands on its own', () {
      final json = const ReportTarget(
        type: ReportTargetType.user,
        id: 'u1',
      ).toJson();
      expect(json['targetType'], 'USER');
      expect(json.containsKey('contextId'), isFalse);
    });

    test('never sends the label the server derives for itself', () {
      final json = ReportTarget.attachment(
        attachmentId: 'a1',
        issueId: 'i1',
        fileName: 'screenshot.png',
      ).toJson();
      // The reporter is shown the file name; the queue row's handle comes from
      // the entity the server resolved and authorized, not from the client.
      expect(json.containsKey('label'), isFalse);
      expect(json.keys.toSet(), {'targetType', 'targetId', 'contextId'});
    });
  });

  group('content refusal detection', () {
    test('recognises 422 and nothing else', () {
      expect(
        isContentRefusal(ApiFailure('nope', statusCode: 422)),
        isTrue,
      );
      // 400 is a malformed body and 403 is a permission problem; both get a
      // field error or a toast, never the policy dialog.
      expect(isContentRefusal(ApiFailure('nope', statusCode: 400)), isFalse);
      expect(isContentRefusal(ApiFailure('nope', statusCode: 403)), isFalse);
      expect(isContentRefusal(ApiFailure('errors.connection')), isFalse);
    });
  });

  group('BlockedUser', () {
    test('parses the list payload', () {
      final user = BlockedUser.fromJson(const {
        'userId': 'u1',
        'displayName': 'Ada Lovelace',
        'username': 'ada',
        'blockedAt': '2026-08-05T10:00:00Z',
      });
      expect(user.userId, 'u1');
      expect(user.displayName, 'Ada Lovelace');
      expect(user.blockedAt, isNotNull);
    });

    test('accepts a plain id and falls back to the username', () {
      final user = BlockedUser.fromJson(const {'id': 'u2', 'username': 'bob'});
      expect(user.userId, 'u2');
      expect(user.displayName, 'bob');
    });
  });
}
