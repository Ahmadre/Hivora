import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';
import '../../../core/events/issue_events.dart';
import '../../../core/repositories/issue_repository.dart';

/// Who is subscribed to one issue, plus the in-flight/error state of the
/// caller's own subscription toggle.
class IssueWatchState extends Equatable {
  const IssueWatchState({
    this.watcherIds = const [],
    this.busy = false,
    this.errorKey,
  });

  final List<String> watcherIds;

  /// A watch/unwatch call is in flight. The optimistic result is already in
  /// [watcherIds]; this only drives the disabled/pending look of the toggle.
  final bool busy;

  /// Set for exactly one state after a failed toggle so the host can raise a
  /// toast; cleared again by the next emit.
  final String? errorKey;

  int get count => watcherIds.length;

  bool isWatchedBy(String? userId) =>
      userId != null && watcherIds.contains(userId);

  @override
  List<Object?> get props => [watcherIds, busy, errorKey];
}

/// Drives the issue-detail watch toggle.
///
/// The toggle flips **optimistically** — a subscription is a one-tap,
/// low-stakes action, and waiting out a round trip before the switch moves
/// reads as a broken control. The pre-call watcher list is kept and restored
/// verbatim when the server refuses, so a failed toggle leaves no phantom
/// "watching" state behind; the accompanying [IssueWatchState.errorKey] tells
/// the host to explain why.
class IssueWatchCubit extends Cubit<IssueWatchState> {
  IssueWatchCubit({
    required IssueRepository repository,
    required this.issueId,
    required this.userId,
    List<String> watcherIds = const [],
  }) : _repo = repository,
       super(IssueWatchState(watcherIds: watcherIds));

  final IssueRepository _repo;
  final String issueId;

  /// The signed-in user, or null while the session is still resolving — the
  /// toggle has nobody to subscribe then and stays inert.
  final String? userId;

  /// What the caller's own subscription settled on after the last toggle, or
  /// null while they never touched it. This cubit is per-issue and the card
  /// recreates it whenever the issue id (or the session user) changes, so this
  /// can never be carried over to a different issue.
  bool? _committedOwnState;

  bool get watching => state.isWatchedBy(userId);

  /// Adopts a fresh server copy of the watcher list (a reload of the issue, a
  /// change pushed in from elsewhere). Ignored while a toggle is in flight so a
  /// stale payload can't undo what the user just tapped.
  ///
  /// A payload can also have *left the server before* the toggle and land after
  /// it — the sheet's title PATCH is the everyday case, its response carries a
  /// pre-watch roster. Since nothing in a payload says how old it is, the
  /// committed own-state wins: the incoming roster is taken for everybody else
  /// and the caller's own membership is re-applied on top. A genuine unwatch
  /// from another device is then only picked up on the next sheet open, which
  /// is the better of the two errors.
  void sync(List<String> watcherIds) {
    if (state.busy) return;
    final me = userId;
    final committed = _committedOwnState;
    var next = watcherIds;
    if (me != null &&
        committed != null &&
        watcherIds.contains(me) != committed) {
      next = committed
          ? [...watcherIds, me]
          : [
              for (final id in watcherIds)
                if (id != me) id,
            ];
    }
    if (_sameAsState(next)) return;
    emit(IssueWatchState(watcherIds: List.unmodifiable(next)));
  }

  bool _sameAsState(List<String> ids) {
    if (ids.length != state.watcherIds.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != state.watcherIds[i]) return false;
    }
    return true;
  }

  /// Subscribes or unsubscribes the caller, applying the change up front and
  /// rolling it back if the server rejects it.
  Future<void> toggle() async {
    final me = userId;
    if (me == null || state.busy) return;

    final before = state.watcherIds;
    final wasWatching = before.contains(me);
    final optimistic = wasWatching
        ? [
            for (final id in before)
              if (id != me) id,
          ]
        : [...before, me];

    emit(IssueWatchState(watcherIds: optimistic, busy: true));
    try {
      if (wasWatching) {
        await _repo.unwatchIssue(issueId);
      } else {
        await _repo.watchIssue(issueId);
      }
      if (isClosed) return;
      _committedOwnState = !wasWatching;
      emit(IssueWatchState(watcherIds: optimistic));
      // The "Watched" list is a separate screen holding its own page of issues
      // and has no handle to this sheet — the watch-only broadcast is how it
      // learns an issue joined or left it. Deliberately *not* IssueEvents: no
      // other screen renders watch state, so nothing else should re-fetch.
      IssueWatchEvents.instance.notifyChanged();
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      _committedOwnState = wasWatching;
      emit(IssueWatchState(watcherIds: before, errorKey: failure.message));
    } catch (_) {
      if (isClosed) return;
      _committedOwnState = wasWatching;
      emit(IssueWatchState(watcherIds: before, errorKey: 'errors.unexpected'));
    }
  }
}
