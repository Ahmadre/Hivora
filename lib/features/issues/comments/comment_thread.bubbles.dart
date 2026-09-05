part of 'comment_thread.dart';

/// One comment in the feed — flat text (or a playable voice bubble) on a
/// transparent background, always left-aligned: avatar, an author · date header,
/// the body, reaction chips and a persistent action row (Reply · react · more).
class CommentBubbleRow extends StatelessWidget {
  const CommentBubbleRow({
    super.key,
    required this.comment,
    required this.interactions,
    this.isReply = false,
    this.pinned = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.highlight = false,
    this.trunkBelow = false,
  });

  final IssueComment comment;
  final CommentInteractions interactions;

  /// A reply row: a smaller avatar and no reply-thread of its own.
  final bool isReply;
  final bool pinned;
  final bool selectionMode;
  final bool selected;
  final void Function(IssueComment comment)? onToggleSelected;
  final bool highlight;

  /// Draw a "main branch" line down from this (root) comment's avatar to its
  /// reply thread below — set when the thread is expanded with replies.
  final bool trunkBelow;

  IssueComment get _c => comment;
  CommentInteractions get _x => interactions;
  bool get _canManage => _x.canManage(_c);

  @override
  Widget build(BuildContext context) {
    final avatarSize = isReply ? 26.0 : 32.0;
    final name = _x.nameFor(_c.authorId);

    final leading = selectionMode
        ? (_canManage
              ? Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _SelectDot(selected: selected),
                )
              : SizedBox(width: avatarSize))
        : HiveAvatar(
            name: name,
            imageUrl: _x.avatarFor(_c.authorId),
            size: avatarSize,
          );

    final body = _c.isVoice
        ? VoiceBubble(voice: _c.voice!, loader: _x.loadVoice(_c))
        : _TextBody(comment: _c);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, name),
        const SizedBox(height: 5),
        // A subtle wash flashes the row on a deep-link / reply jump.
        AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: body,
        ),
        if (_c.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: _ReactionChips(
              comment: _c,
              meId: _x.meId,
              onTap: (emoji) => _x.onReact(_c, emoji),
            ),
          ),
        if (!selectionMode) ...[
          const SizedBox(height: 3),
          _CommentActions(comment: _c, interactions: _x, canManage: _canManage),
        ],
      ],
    );

    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(child: content),
      ],
    );

    // A root with visible replies grows a vertical "main branch" line from just
    // below its 32px avatar (centre x = 16) down to the reply thread; the reply
    // rows continue it at the same x. Painted in a Stack so no IntrinsicHeight
    // is needed — the Positioned line stretches to the row's height.
    if (trunkBelow) {
      row = Stack(
        children: [
          row,
          Positioned(
            left: 15.25, // 32/2 − half of the 1.5px stroke
            top: 35, // just below the 32px avatar
            bottom: 0,
            child: Container(width: 1.5, color: _branchLineColor()),
          ),
        ],
      );
    }

    // In selection mode the whole row toggles the checkbox for own comments.
    if (selectionMode && _canManage) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggleSelected?.call(_c),
        child: row,
      );
    }
    return row;
  }

  Widget _header(BuildContext context, String name) {
    final dt = _c.createdAt?.toLocal();
    final when = dt == null
        ? ''
        : '${MaterialLocalizations.of(context).formatMediumDate(dt)} '
              '${context.t('comments.at')} ${hhmm(dt)}';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      children: [
        if (pinned)
          const Icon(LucideIcons.pin, size: 12, color: AppColors.accentStrong),
        Text(
          name,
          style: TextStyle(
            fontSize: isReply ? 12.5 : 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        PronounsLabel(
          pronouns: _x.pronounsFor(_c.authorId),
          fontSize: isReply ? 11 : 11.5,
        ),
        if (when.isNotEmpty)
          Text(
            when,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
          ),
        if (_c.isEdited)
          Text(
            '· ${context.t('issues.commentEdited')}',
            style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
          ),
      ],
    );
  }
}

/// The persistent action row under a comment: Reply, a reaction popover and a
/// "more" popover (edit/copy/pin/…). Left-aligned to the body on every platform.
class _CommentActions extends StatefulWidget {
  const _CommentActions({
    required this.comment,
    required this.interactions,
    required this.canManage,
  });

  final IssueComment comment;
  final CommentInteractions interactions;
  final bool canManage;

  @override
  State<_CommentActions> createState() => _CommentActionsState();
}

class _CommentActionsState extends State<_CommentActions> {
  // Screen rect of the react button, captured when the quick-reactions pill
  // opens. The full emoji picker anchors here (its ORIGINAL trigger), not the
  // "…" button inside the pill. Captured from the trigger's own render box —
  // NOT a GlobalKey: a GlobalKey wrapping the Tooltip (an OverlayPortal) inside
  // GlassPopover's animated triggerBuilder crashed on hover with a re-entrant
  // overlay layout (`!_skipMarkNeedsLayout`). See [[reference_web_hover_transform_assert]].
  Rect? _reactAnchor;

  IssueComment get _c => widget.comment;
  CommentInteractions get _x => widget.interactions;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: LucideIcons.reply,
          label: context.t('comments.reply'),
          onTap: () => _x.onReply(_c),
        ),
        const SizedBox(width: 2),
        // Quick reactions (emoji row + "…" for the full picker).
        GlassPopover(
          alignment: GlassMenuAlignment.topLeft,
          popoverWidth: (kQuickReactions.length + 1) * 40 + 12,
          popoverBorderRadius: 27,
          settings: _navGlass(dark),
          quality: GlassQuality.standard,
          triggerBuilder: (context, toggle) => _ActionButton(
            icon: LucideIcons.smilePlus,
            tooltip: context.t('comments.react'),
            // Capture the react button's own render box (GlassPopover builds the
            // trigger as its topmost render object, so this context IS the button)
            // the moment the pill opens, then hand it to the emoji picker.
            onTap: () {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                _reactAnchor = box.localToGlobal(Offset.zero) & box.size;
              }
              toggle();
            },
          ),
          contentBuilder: (_, close) => _QuickReactionsBar(
            selected: _c.myReaction(_x.meId),
            onPick: (emoji) {
              close();
              _x.onReact(_c, emoji);
            },
            // "…" → the full glass emoji picker. Anchor it to the REACT button
            // (its original trigger), not the "…" button, so it opens where the
            // user first tapped. Capture the rect before closing the quick pill.
            onMore: () async {
              final anchor = _reactAnchor;
              close();
              final picked = await _pickEmojiGlass(context, anchor: anchor);
              if (picked != null && context.mounted) {
                _x.onReact(_c, picked);
              }
            },
          ),
        ),
        const SizedBox(width: 2),
        // Overflow menu.
        GlassPopover(
          alignment: GlassMenuAlignment.topLeft,
          popoverWidth: 236,
          popoverBorderRadius: 22,
          settings: _navGlass(dark),
          quality: GlassQuality.standard,
          triggerBuilder: (context, toggle) => _ActionButton(
            icon: LucideIcons.chevronDown,
            tooltip: context.t('comments.more'),
            onTap: toggle,
          ),
          contentBuilder: (context, close) =>
              _ContextMenuCard(rows: _menuRows(context, close)),
        ),
      ],
    );
  }

  List<_MenuRowData> _menuRows(BuildContext context, VoidCallback close) {
    final isVoice = _c.isVoice;
    void run(void Function() action) {
      close();
      action();
    }

    return [
      _MenuRowData(
        LucideIcons.reply,
        context.t('comments.reply'),
        () => run(() => _x.onReply(_c)),
      ),
      if (!isVoice)
        _MenuRowData(
          LucideIcons.copy,
          context.t('comments.copy'),
          () => run(() => _x.onCopy(_c)),
        ),
      if (widget.canManage)
        _MenuRowData(
          LucideIcons.circleCheck,
          context.t('comments.select'),
          () => run(() => _x.onEnterSelection(_c)),
        ),
      if (widget.canManage && !isVoice)
        _MenuRowData(
          LucideIcons.pencil,
          context.t('common.edit'),
          () => run(() => _x.onEdit(_c)),
        ),
      _MenuRowData(
        LucideIcons.link,
        context.t('comments.copyLink'),
        () => run(() => _x.onCopyLink(_c)),
      ),
      _MenuRowData(
        _c.pinned ? LucideIcons.pinOff : LucideIcons.pin,
        _c.pinned ? context.t('comments.unpin') : context.t('comments.pin'),
        () => run(() => _x.onTogglePin(_c)),
      ),
      if (widget.canManage)
        _MenuRowData(
          LucideIcons.trash2,
          context.t('common.delete'),
          () => run(() => _x.onDelete(_c)),
          danger: true,
        ),
    ];
  }
}

/// A compact text/icon action button (Reply) or icon-only button (react/more).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: AppColors.accent.withValues(alpha: 0.10),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label != null ? 8 : 6,
            vertical: 5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.inkSoft),
              if (label != null) ...[
                const SizedBox(width: 5),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// The collapsible reply thread under a root comment: a "show replies (N)"
/// affordance, then the flat replies (oldest-first) with connector lines, a
/// "load more" control and a "hide replies" control.
class _ReplyThreadView extends StatelessWidget {
  const _ReplyThreadView({
    required this.root,
    required this.interactions,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelected,
    required this.highlightedId,
    required this.commentKeys,
  });

  final IssueComment root;
  final CommentInteractions interactions;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(IssueComment comment)? onToggleSelected;
  final String? highlightedId;
  final Map<String, GlobalKey>? commentKeys;

  /// Indent of the reply block; the connector line lives in this gutter.
  static const double _indent = 40;

  @override
  Widget build(BuildContext context) {
    final thread = interactions.threadOf(root.id);
    // Nothing to show: no known replies and never expanded.
    if (root.replyCount == 0 && thread.replies.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!thread.expanded) {
      final count = root.replyCount;
      return Padding(
        padding: const EdgeInsets.only(left: _indent, top: 8),
        child: _ThreadControl(
          icon: LucideIcons.messageCircle,
          loading: thread.loading,
          label: context.t(
            'comments.showReplies',
            count: count,
            variables: {'count': '$count'},
          ),
          onTap: () => interactions.onToggleReplies(root),
        ),
      );
    }

    final replies = thread.replies;
    // No top gap: the first reply's rail must continue the root's branch stem.
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < replies.length; i++)
            _replyRow(
              replies[i],
              last: i == replies.length - 1 && !thread.hasMore,
            ),
          Padding(
            padding: const EdgeInsets.only(left: _indent, top: 6),
            child: Row(
              children: [
                if (thread.hasMore)
                  _ThreadControl(
                    icon: LucideIcons.chevronDown,
                    loading: thread.loading,
                    label: context.t('comments.loadMoreReplies'),
                    onTap: () => interactions.onLoadMoreReplies(root),
                  ),
                if (thread.hasMore) const SizedBox(width: 8),
                _ThreadControl(
                  icon: LucideIcons.chevronUp,
                  loading: false,
                  label: context.t('comments.hideReplies'),
                  onTap: () => interactions.onToggleReplies(root),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyRow(IssueComment reply, {required bool last}) {
    final row = CommentBubbleRow(
      comment: reply,
      interactions: interactions,
      isReply: true,
      selectionMode: selectionMode,
      selected: selectedIds.contains(reply.id),
      onToggleSelected: onToggleSelected,
      highlight: highlightedId == reply.id,
    );
    final keyed = commentKeys?[reply.id];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _indent,
            child: CustomPaint(
              painter: _ReplyConnectorPainter(
                last: last,
                color: _branchLineColor(),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: RepaintBoundary(
                child: keyed == null
                    ? row
                    : KeyedSubtree(key: keyed, child: row),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reply connector / branch-line colour — subtle but legible in BOTH
/// themes. [AppColors.hairline] is too close to the dark canvas to read, and
/// nearly invisible on the light warm-paper canvas, so both use faded ink.
Color _branchLineColor() {
  final dark = AppColors.brightness == Brightness.dark;
  return dark
      ? AppColors.inkFaint.withValues(alpha: 0.7)
      : AppColors.inkFaint.withValues(alpha: 0.5);
}

/// Draws the reply connector: a vertical rail down the gutter with a curved
/// elbow into each reply's avatar. The rail stops at the elbow on the last row.
class _ReplyConnectorPainter extends CustomPainter {
  _ReplyConnectorPainter({required this.last, required this.color});

  final bool last;
  final Color color;

  // Where the elbow meets the avatar row (aligns with the reply avatar centre:
  // 8px top padding + ~13 to the avatar's vertical middle).
  static const double _elbowY = 21;
  // Rail x = the ROOT avatar's centre (32/2), so the branch continues the root's
  // main-branch stem in a straight, unbroken line.
  static const double _railX = 16;
  // The elbow reaches across the gutter to the reply avatar's left edge.
  static const double _avatarEdgeX = 36;
  // Radius of the rounded corner where the rail turns into the elbow. A TRUE
  // quarter-circle (see arcToPoint below) — a bezier squeezed over unequal
  // spans reads flat/squashed, YouTube-style threads use a perfect round.
  static const double _corner = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Vertical rail (continues the root's main branch). For the LAST reply it
    // stops exactly where the rounded corner begins — no straight overshoot — so
    // the branch closes with a clean quarter-round; otherwise it runs full
    // height down to the next reply.
    canvas.drawLine(
      const Offset(_railX, 0),
      Offset(_railX, last ? _elbowY - _corner : size.height),
      paint,
    );
    // Rounded corner from the rail across to the reply avatar.
    final elbow = Path()
      ..moveTo(_railX, _elbowY - _corner)
      ..quadraticBezierTo(_railX, _elbowY, _avatarEdgeX, _elbowY);
    canvas.drawPath(elbow, paint);
  }

  @override
  bool shouldRepaint(_ReplyConnectorPainter old) =>
      old.last != last || old.color != color;
}

/// A subtle text-button used by the reply thread ("show replies", "load more",
/// "hide replies"), with an optional inline spinner.
class _ThreadControl extends StatelessWidget {
  const _ThreadControl({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(1),
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : Icon(icon, size: 14, color: AppColors.accentStrong),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The circular selection indicator shown on own comments in selection mode.
class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.hairline,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(LucideIcons.check, size: 13, color: Color(0xFF2A2410))
          : null,
    );
  }
}

/// Reaction chips (emoji + count) shown under a comment. The user's own reaction
/// is tinted; tapping a chip toggles it.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips({
    required this.comment,
    required this.meId,
    required this.onTap,
  });

  final IssueComment comment;
  final String? meId;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final mine = comment.myReaction(meId);
    final counts = comment.reactionCounts;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final entry in counts.entries)
          _chip(
            emoji: entry.key,
            count: entry.value,
            selected: entry.key == mine,
            dark: dark,
          ),
      ],
    );
  }

  Widget _chip({
    required String emoji,
    required int count,
    required bool selected,
    required bool dark,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: () => onTap(emoji),
        customBorder: const StadiumBorder(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: dark ? 0.26 : 0.18)
                : (dark ? const Color(0xFF23222F) : AppColors.surface),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              if (count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.accentStrong
                        : AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
