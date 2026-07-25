import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Motion design of a board card drag — shared by the Kanban board and the
/// Scrum surface so both walls feel like the same physical object.
///
/// The choreography deliberately keeps **one thing moving at a time**, so a
/// board with a dozen lanes never turns into a light show:
///
///  1. **Lift** — on grab the carried card scales up a hair and its shadow
///     grows, as if it left the surface. 190 ms, then it just sits there.
///  2. **Sway** — while carried, the card leans into the direction of travel
///     like something held by its top edge: a spring drives the tilt from the
///     horizontal drag velocity, so it swings out on a fast sideways move and
///     settles back with one soft over-swing when the pointer stops. Capped at
///     6°, never more.
///  3. **Socket** — the vacated spot stays exactly where it was, drawn as a
///     quiet empty recess. Nothing above or below it moves, so the column the
///     card came from never jumps.
///  4. **Slot** — the hovered column opens an accent slot at its foot, in the
///     dragged card's own height. It grows at the *end* of the list, so again
///     no existing card is pushed around.
///  5. **Landing** — after the drop the card scales out of that slot at its new
///     home with an accent ring that fades away once.
///
/// Everything is skipped when the platform asks for reduced motion.
abstract final class BoardDragMotion {
  /// Pick-up: scale + shadow ramp.
  static const lift = Duration(milliseconds: 190);

  /// Drop slot opening / closing in the hovered column.
  static const slot = Duration(milliseconds: 260);

  /// The card settling in at its new column.
  static const landing = Duration(milliseconds: 460);

  /// Socket fading in where the card was picked up.
  static const socket = Duration(milliseconds: 160);

  /// Hard cap for the carry tilt (~6°). Beyond this it reads as a glitch.
  static const maxTilt = 0.105;

  /// Radians of tilt per px/s of horizontal drag velocity — a brisk 1500 px/s
  /// swipe reaches the cap, everyday movement stays well under it.
  static const tiltPerVelocity = maxTilt / 1500;

  /// Tilt spring. The damping ratio (~0.7) is chosen for exactly one gentle
  /// over-swing when the pointer stops — the "hin und her" without the wobble.
  static const tiltStiffness = 260.0;
  static const tiltDamping = 23.0;

  /// Time constant for smoothing raw pointer deltas into a velocity.
  static const velocitySmoothing = 0.05;

  /// How much the carried card grows over the column card.
  static const liftScale = 0.045;

  /// Pivot of the carry: near the top edge, so the card swings like something
  /// hanging from the pointer instead of spinning around its middle.
  static const carryPivot = Alignment(0, -0.75);

  /// Fallback slot height before a card size is known (touch, tests).
  static const fallbackCardHeight = 96.0;

  /// Distance from a board edge at which carrying a card starts to scroll the
  /// wall, and the speed reached at the very edge.
  static const scrollEdge = 76.0;
  static const scrollSpeed = 900.0;

  /// Whether the platform asks for reduced motion. Read off the dispatcher
  /// rather than [MediaQuery] because both users of it decide in `initState`,
  /// where taking an inherited dependency isn't allowed.
  static bool get reducedMotion => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;
}

/// Ambient state of the one card drag that can be in flight.
///
/// A pointer can carry exactly one card at a time and the feedback lives in the
/// app overlay — outside the board's own tree, where inherited widgets don't
/// reach. So instead of threading a controller through every lane, column and
/// list item, the drag publishes itself here and the three participants (the
/// carried card, the vacated socket, the target slot) read what they need.
final BoardDragState boardDrag = BoardDragState._();

class BoardDragState extends ChangeNotifier {
  BoardDragState._();

  Size? _cardSize;
  Offset _pending = Offset.zero;
  Offset? _pointer;
  bool _dragging = false;
  String? _landedId;

  /// Whether a card is in the air right now.
  bool get isDragging => _dragging;

  /// Where the carried card currently is, in global coordinates — what the
  /// board's edge auto-scroll steers by.
  Offset? get pointer => _pointer;

  /// Height of the card as it sat in its column, so the target slot opens to
  /// exactly what will land in it. Null while nothing is being dragged.
  double get cardHeight =>
      _cardSize?.height ?? BoardDragMotion.fallbackCardHeight;

  /// The issue that just completed a drop and still owes its landing
  /// animation — consumed once by the card that renders it.
  String? get landedId => _landedId;

  void start(Size? cardSize, Offset pointer) {
    _cardSize = cardSize;
    _pointer = pointer;
    _pending = Offset.zero;
    _dragging = true;
    notifyListeners();
  }

  /// Feeds a pointer sample. The delta is drained by the carried card once per
  /// frame, the position polled by the auto-scroller — neither wants a
  /// notification per pointer event.
  void move(Offset delta, Offset pointer) {
    _pending += delta;
    _pointer = pointer;
  }

  Offset takeMotion() {
    final pending = _pending;
    _pending = Offset.zero;
    return pending;
  }

  void end() {
    _cardSize = null;
    _pointer = null;
    _pending = Offset.zero;
    _dragging = false;
    notifyListeners();
  }

  /// Marks [issueId] as freshly dropped. Call right before the board reloads;
  /// the card that shows up in the target column plays the landing once.
  void land(String issueId) => _landedId = issueId;

  /// Consumed by the landing card during build — deliberately silent, a
  /// notification here would rebuild mid-frame.
  void clearLanded(String issueId) {
    if (_landedId == issueId) _landedId = null;
  }
}

/// Makes [child] a draggable board card with the full lift → sway → socket
/// choreography. [ghost] is a non-interactive copy of the card, used both for
/// the carried feedback and for sizing the socket left behind.
class BoardDragCard extends StatelessWidget {
  const BoardDragCard({
    super.key,
    required this.issue,
    required this.child,
    required this.ghost,
    this.width = 276,
    this.enabled = true,
  });

  final Issue issue;
  final Widget child;
  final Widget ghost;

  /// Width of the carried card — a touch narrower than the column so it reads
  /// as detached from the wall.
  final double width;

  /// Touch platforms pass false: a card drag there fights the board's scroll
  /// gesture, so state changes happen in the issue sheet instead.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<Issue>(
        data: issue,
        dragAnchorStrategy: childDragAnchorStrategy,
        maxSimultaneousDrags: 1,
        onDragStarted: () {
          // The card is still laid out at this point, so its box gives both the
          // height the target slot opens to and a starting position for the
          // auto-scroll, until the first pointer sample arrives.
          final box = context.findRenderObject() as RenderBox?;
          final laidOut = box != null && box.hasSize;
          boardDrag.start(
            laidOut ? box.size : null,
            laidOut
                ? box.localToGlobal(box.size.center(Offset.zero))
                : Offset.zero,
          );
        },
        onDragUpdate: (details) =>
            boardDrag.move(details.delta, details.globalPosition),
        onDragEnd: (_) => boardDrag.end(),
        feedback: _CarriedCard(width: width, child: ghost),
        childWhenDragging: _VacatedSocket(child: ghost),
        child: child,
      ),
    );
  }
}

/// Scrolls the board under a carried card when it is brought near an edge —
/// the only way to reach a column or lane that is currently off-screen, since
/// the drag holds the pointer and the board's own scroll gestures can't run.
///
/// Owns the scroll controllers and hands them to [builder], so callers stay
/// stateless. The speed ramps up towards the edge, so a card parked just inside
/// the margin creeps rather than shoots.
class BoardDragScroller extends StatefulWidget {
  const BoardDragScroller({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    ScrollController vertical,
    ScrollController horizontal,
  )
  builder;

  @override
  State<BoardDragScroller> createState() => _BoardDragScrollerState();
}

class _BoardDragScrollerState extends State<BoardDragScroller>
    with SingleTickerProviderStateMixin {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    boardDrag.addListener(_onDragChanged);
  }

  @override
  void dispose() {
    boardDrag.removeListener(_onDragChanged);
    _ticker.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _onDragChanged() {
    if (boardDrag.isDragging == _ticker.isActive) return;
    if (boardDrag.isDragging) {
      _last = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 30);
    _last = elapsed;
    if (dt <= 0) return;
    final pointer = boardDrag.pointer;
    final box = context.findRenderObject() as RenderBox?;
    if (pointer == null || box == null || !box.hasSize) return;
    final local = box.globalToLocal(pointer);
    _drive(_vertical, local.dy, box.size.height, dt);
    _drive(_horizontal, local.dx, box.size.width, dt);
  }

  void _drive(
    ScrollController controller,
    double pos,
    double extent,
    double dt,
  ) {
    const edge = BoardDragMotion.scrollEdge;
    // Ignore a pointer that has left this board entirely (dragged over the app
    // bar, another lane's viewport, …) instead of scrolling on its behalf.
    if (pos < -edge || pos > extent + edge) return;
    final speed = pos < edge
        ? -_ramp((edge - pos) / edge)
        : pos > extent - edge
        ? _ramp((pos - (extent - edge)) / edge)
        : 0.0;
    if (speed == 0 || !controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    final target = (position.pixels + speed * dt).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) controller.jumpTo(target);
  }

  double _ramp(double t) =>
      BoardDragMotion.scrollSpeed * Curves.easeIn.transform(t.clamp(0, 1));

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _vertical, _horizontal);
}

/// The card while it is carried: lifts off on grab, then leans into the
/// direction of travel on a damped spring.
class _CarriedCard extends StatefulWidget {
  const _CarriedCard({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_CarriedCard> createState() => _CarriedCardState();
}

class _CarriedCardState extends State<_CarriedCard>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _lift = 0;
  double _tilt = 0;
  double _tiltVelocity = 0;
  double _velocity = 0;

  @override
  void initState() {
    super.initState();
    // Reduced motion: the card is simply carried, fully lifted, dead level.
    if (BoardDragMotion.reducedMotion) {
      _lift = 1;
      return;
    }
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    // Clamp dt so a dropped frame can't kick the spring across the screen.
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 30);
    _last = elapsed;
    if (dt <= 0) return;

    final dx = boardDrag.takeMotion().dx;
    final blend = 1 - math.exp(-dt / BoardDragMotion.velocitySmoothing);
    _velocity += (dx / dt - _velocity) * blend;

    final target = (_velocity * BoardDragMotion.tiltPerVelocity).clamp(
      -BoardDragMotion.maxTilt,
      BoardDragMotion.maxTilt,
    );
    final accel =
        BoardDragMotion.tiltStiffness * (target - _tilt) -
        BoardDragMotion.tiltDamping * _tiltVelocity;
    _tiltVelocity += accel * dt;
    _tilt += _tiltVelocity * dt;
    _lift = math.min(
      1,
      _lift + dt / (BoardDragMotion.lift.inMilliseconds / 1000),
    );

    // At rest (level card, fully lifted, pointer parked) there is nothing to
    // repaint — hold still until the pointer moves again.
    final settled =
        _lift == 1 &&
        _tilt.abs() < 1e-4 &&
        _tiltVelocity.abs() < 1e-3 &&
        _velocity.abs() < 1;
    if (settled) {
      _tilt = 0;
      _tiltVelocity = 0;
      _velocity = 0;
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lifted = Curves.easeOutCubic.transform(_lift);
    const pivot = BoardDragMotion.carryPivot;
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: widget.width,
        child: Transform.rotate(
          angle: _tilt,
          alignment: pivot,
          child: Transform.scale(
            scale: 1 + BoardDragMotion.liftScale * lifted,
            alignment: pivot,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06 + 0.14 * lifted),
                    blurRadius: 6 + 20 * lifted,
                    offset: Offset(0, 2 + 10 * lifted),
                  ),
                ],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The spot the card was picked up from: same size, no content, drawn as a
/// quiet recess. Keeping the box means the source column never reflows while
/// the card is in the air.
class _VacatedSocket extends StatelessWidget {
  const _VacatedSocket({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // Sizing only — Opacity(0) skips painting the card entirely.
      Opacity(opacity: 0, child: child),
      Positioned.fill(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: BoardDragMotion.socket,
          curve: Curves.easeOut,
          builder: (context, t, _) => DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.inkFaint.withValues(alpha: 0.055 * t),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppColors.inkFaint.withValues(alpha: 0.2 * t),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// The slot that opens at the foot of the column a card is hovering over,
/// sized to that card. Rendered after the column's list so nothing already on
/// the wall has to move aside.
class BoardDropSlot extends StatelessWidget {
  const BoardDropSlot({super.key, required this.open, this.hasCards = true});

  final bool open;

  /// An empty column has no separator above the slot to match.
  final bool hasCards;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: BoardDragMotion.slot,
    curve: Curves.easeOutCubic,
    height: open ? boardDrag.cardHeight : 0,
    margin: EdgeInsets.only(top: open && hasCards ? 9 : 0),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: open ? 0.1 : 0),
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      border: Border.all(
        color: AppColors.accentLine.withValues(alpha: open ? 1 : 0),
        width: 1.5,
      ),
    ),
  );
}

/// Plays the landing once for the card that just completed a drop: it scales
/// out of the slot it was dropped into, with an accent ring that fades away.
/// Every other card renders untouched.
class BoardLandingCard extends StatefulWidget {
  const BoardLandingCard({
    super.key,
    required this.issueId,
    required this.accent,
    required this.child,
  });

  final String issueId;
  final Color accent;
  final Widget child;

  @override
  State<BoardLandingCard> createState() => _BoardLandingCardState();
}

class _BoardLandingCardState extends State<BoardLandingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BoardDragMotion.landing,
  );

  @override
  void initState() {
    super.initState();
    _playIfLanded();
  }

  @override
  void didUpdateWidget(BoardLandingCard old) {
    super.didUpdateWidget(old);
    // List items are recycled by index, so a landed card can arrive as an
    // update to an existing row rather than a fresh one.
    if (old.issueId != widget.issueId) _playIfLanded();
  }

  void _playIfLanded() {
    if (boardDrag.landedId != widget.issueId) return;
    boardDrag.clearLanded(widget.issueId);
    if (BoardDragMotion.reducedMotion) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      if (_controller.value == 0 || _controller.isCompleted) return child!;
      final t = Curves.easeOutCubic.transform(_controller.value);
      return Transform.scale(
        scale: 0.96 + 0.04 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.45 * (1 - t)),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
      );
    },
  );
}
