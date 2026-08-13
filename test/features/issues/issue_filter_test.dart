import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_filter.dart';

void main() {
  // With server-side facet filtering, the loaded issue list is already
  // reduced, so the filter picker must offer the full value space from
  // reference data (all states/projects/users + the fixed enums) rather than
  // deriving options from the loaded issues (which would hide values the current
  // result page doesn't contain).
  group('IssueFilterOptions.reference', () {
    final options = IssueFilterOptions.reference(
      states: const ['OPEN', 'IN PROGRESS', 'DONE'],
      assignees: const ['u1', 'u2'],
      projects: const ['p1'],
    );

    test('passes through the reference states/assignees/projects', () {
      expect(options.states, ['OPEN', 'IN PROGRESS', 'DONE']);
      expect(options.assignees, ['u1', 'u2']);
      expect(options.projects, ['p1']);
    });

    test('offers the full fixed type + priority enums', () {
      expect(options.types, kIssueTypeCodes);
      expect(options.priorities, kIssuePriorityCodes);
      expect(options.types, contains('EPIC'));
      expect(options.priorities, contains('SHOWSTOPPER'));
      // Lowest severity is offered too and stays last in display order.
      expect(options.priorities, contains('TRIVIAL'));
      expect(kIssuePriorityCodes.last, 'TRIVIAL');
    });

    test('always allows filtering the unassigned bucket', () {
      expect(options.hasUnassigned, isTrue);
    });

    test('is not empty when any facet has values', () {
      expect(options.isEmpty, isFalse);
    });
  });

  // The lightweight mention/resolve endpoints return a minimal summary.
  group('IssueRef.fromJson', () {
    test('parses the id/readableId/title/type fields', () {
      final ref = IssueRef.fromJson(const {
        'id': '507f1f77bcf86cd799439011',
        'readableId': 'HIN-1',
        'title': 'Board redesign',
        'type': 'STORY',
      });
      expect(ref.id, '507f1f77bcf86cd799439011');
      expect(ref.readableId, 'HIN-1');
      expect(ref.title, 'Board redesign');
      expect(ref.type, 'STORY');
    });

    test('tolerates missing fields with sensible fallbacks', () {
      final ref = IssueRef.fromJson(const {'readableId': 'HIN-2'});
      expect(ref.id, '');
      expect(ref.readableId, 'HIN-2');
      expect(ref.title, '');
      // Type falls back to TASK so the menu still picks a glyph.
      expect(ref.type, 'TASK');
    });
  });
}
