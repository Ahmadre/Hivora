import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/board/board_swimlanes.dart';

/// On a merged board a column stands for one step across several projects — but
/// a step only some of them took still gets a column, and a card from a project
/// without it can't go there. The board says which projects a column belongs to
/// so that refusal stops being a surprise.
void main() {
  Project project(String key, List<String> states) => Project(
    id: key.toLowerCase(),
    key: key,
    name: '$key Project',
    workflowStates: [
      for (final s in states) WorkflowState(id: s, name: s, hue: 250),
    ],
  );

  BoardColumnView column(String name, List<String> states) =>
      BoardColumnView(name: name, states: states, issues: const []);

  final hin = project('HIN', ['Open', 'In Freigabe', 'Done']);
  final mob = project('MOB', ['Open', 'Done']);
  final board = {hin.id: hin, mob.id: mob};

  test('says nothing about a column every project has', () {
    // Marking a shared column would be noise on every board that works.
    expect(boardColumnOwners(column('Open', ['Open']), board), isEmpty);
    expect(boardColumnOwners(column('Done', ['Done']), board), isEmpty);
  });

  test('names the projects a column belongs to when not all of them do', () {
    expect(boardColumnOwners(column('In Freigabe', ['In Freigabe']), board), [
      'HIN',
    ]);
  });

  test('stays quiet on a single-project board', () {
    // There is no other project to tell it apart from, so every column is
    // trivially "only" this one's.
    expect(
      boardColumnOwners(column('In Freigabe', ['In Freigabe']), {hin.id: hin}),
      isEmpty,
    );
    expect(boardColumnOwners(column('Open', ['Open']), const {}), isEmpty);
  });

  test('matches a merged column through any of its states', () {
    // The column merges HIN's "Open" with a differently named MOB state, so
    // both projects carry it even though neither name covers both.
    final neu = project('NEU', ['Neu', 'Done']);
    final merged = column('Open', ['Open', 'Neu']);

    expect(boardColumnCarries(hin, merged), isTrue);
    expect(boardColumnCarries(neu, merged), isTrue);
    expect(boardColumnOwners(merged, {hin.id: hin, neu.id: neu}), isEmpty);
  });

  test('is case-insensitive, like the drop resolution it mirrors', () {
    final lower = project('LOW', ['open', 'done']);
    expect(boardColumnCarries(lower, column('Open', ['Open'])), isTrue);
  });
}
