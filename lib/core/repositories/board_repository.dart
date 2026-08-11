import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../events/board_events.dart';
import '../models/deletion_models.dart';
import '../models/work_models.dart';

/// Agile boards: listing, creation, the column view aggregate, and cascading
/// deletion.
///
/// The mutations that change what a *list* of boards shows announce themselves
/// on [BoardEvents], so every screen that renders boards re-fetches without the
/// screen that made the change having to know who else is on screen. See
/// [BoardEvents] for why that lives here rather than at each call site.
class BoardRepository {
  BoardRepository(this._api);

  final ApiClient _api;

  Future<List<AgileBoard>> boards({String? projectId}) async =>
      ((await _api.get('/api/v1/boards', query: {'projectId': ?projectId}))
              as List<dynamic>)
          .map((b) => AgileBoard.fromJson(b as Map<String, dynamic>))
          .toList();

  Future<AgileBoard> createBoard(
    String name,
    List<String> projectIds, {
    BoardType type = BoardType.kanban,
  }) async {
    final board = AgileBoard.fromJson(
      await _api.post(
            '/api/v1/boards',
            body: {
              'name': name,
              'projectIds': projectIds,
              'type': type == BoardType.scrum ? 'SCRUM' : 'KANBAN',
            },
          )
          as Map<String, dynamic>,
    );
    BoardEvents.instance.notifyChanged();
    return board;
  }

  /// Renames a board (management action — server enforces owner/lead/admin).
  Future<AgileBoard> renameBoard(String boardId, String name) async {
    final board = AgileBoard.fromJson(
      await _api.patch('/api/v1/boards/$boardId', body: {'name': name})
          as Map<String, dynamic>,
    );
    BoardEvents.instance.notifyChanged();
    return board;
  }

  /// Changes which projects a board spans (management action — the server also
  /// re-checks membership on every project in the new set, so widening a board
  /// can never be used to reach a project the caller isn't in).
  Future<AgileBoard> updateBoardProjects(
    String boardId,
    List<String> projectIds,
  ) async {
    final board = AgileBoard.fromJson(
      await _api.patch(
            '/api/v1/boards/$boardId',
            body: {'projectIds': projectIds},
          )
          as Map<String, dynamic>,
    );
    BoardEvents.instance.notifyChanged();
    return board;
  }

  /// Stores a hand-made column layout. The server validates it as a whole: every
  /// status of every spanned project needs exactly one column, and no column may
  /// hold two statuses of the same project (a drop there would be ambiguous).
  Future<AgileBoard> updateBoardColumns(
    String boardId,
    List<BoardColumnLayout> columns,
  ) async => AgileBoard.fromJson(
    await _api.patch(
          '/api/v1/boards/$boardId',
          body: {
            'columns': [for (final c in columns) c.toJson()],
          },
        )
        as Map<String, dynamic>,
  );

  /// Drops a hand-made layout and goes back to columns derived from the spanned
  /// workflows.
  Future<AgileBoard> resetBoardColumns(String boardId) async =>
      AgileBoard.fromJson(
        await _api.patch(
              '/api/v1/boards/$boardId',
              body: {'resetColumns': true},
            )
            as Map<String, dynamic>,
      );

  Future<BoardView> boardView(String boardId, {String? sprintId}) async =>
      BoardView.fromJson(
        await _api.get(
              '/api/v1/boards/$boardId',
              query: {'sprintId': ?sprintId},
            )
            as Map<String, dynamic>,
      );

  /// Counts driving the board delete confirmation (sprints, issues to detach).
  Future<BoardDeletionImpact> boardDeletionImpact(String boardId) async =>
      BoardDeletionImpact.fromJson(
        await _api.get('/api/v1/boards/$boardId/deletion-impact')
            as Map<String, dynamic>,
      );

  /// Raw SSE byte stream of a board deletion (parse with [parseSse] →
  /// [DeleteEvent.tryParse]). Cancel via [cancelToken] to abort listening.
  Future<Stream<List<int>>> boardDeleteStream(
    String boardId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/boards/$boardId/delete-stream',
    cancelToken: cancelToken,
  );
}
