import 'dart:async';

/// App-wide broadcast for board changes (create / rename / re-scope / delete).
///
/// The sibling of [IssueEvents](issue_events.dart), for the same reason and
/// with one deliberate difference: **the repository fires this, not the
/// screen**.
///
/// A board is created from two places and managed from two more, and every one
/// of them is somewhere else than the lists that show boards — the board
/// overview, a project's board list, the dashboard's hero-board picker. The
/// overview learnt that the hard way: it opened the new board on top of itself
/// and never refreshed, so coming back showed a list without the board that had
/// just been made, until the page was left and entered again. Put the signal on
/// each screen that changes something and that is one place per screen to
/// forget; put it on the repository and there is one place per *mutation*,
/// which is where the change actually happens.
///
/// A single app-wide instance ([instance]) is intentional — the stream is a
/// broadcast controller, so it is safe to have many concurrent listeners and it
/// never needs disposing for the app's lifetime. Subscribers must still cancel
/// their own [StreamSubscription] in `dispose`.
class BoardEvents {
  BoardEvents._();

  /// The shared app-wide instance.
  static final BoardEvents instance = BoardEvents._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires whenever the set of boards, or how one of them is named or scoped,
  /// changed anywhere in the app.
  ///
  /// A board's *column layout* deliberately does not fire: it changes nothing
  /// a list shows, and the editor that changes it is inside the one board it
  /// belongs to.
  Stream<void> get changes => _controller.stream;

  /// Signal that boards changed so subscribed screens re-fetch.
  void notifyChanged() => _controller.add(null);
}
