part of 'board_screen.dart';

// ─────────────────────────── Board list card ──────────────────────────────

class _BoardListCard extends StatelessWidget {
  const _BoardListCard({
    required this.board,
    required this.index,
    required this.projects,
    required this.canManage,
    required this.onChanged,
  });

  final AgileBoard board;
  final int index;
  final List<Project> projects;
  final bool canManage;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final projectNames = board.projectIds
        .map(
          (id) => projects.firstWhere(
            (p) => p.id == id,
            orElse: () => Project(id: id, key: id, name: id),
          ),
        )
        .map((p) => p.name)
        .join(', ');

    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: () => context.push('/boards/${board.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      board.isScrum ? LucideIcons.zap : LucideIcons.columns3,
                      size: 13,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.t(
                        board.isScrum ? 'board.typeScrum' : 'board.typeKanban',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (canManage)
                Builder(
                  builder: (btnContext) => IconButton(
                    tooltip: context.t('board.manageBoard'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => openBoardManageMenu(
                      btnContext,
                      board: board,
                      onChanged: onChanged,
                    ),
                    icon: Icon(
                      LucideIcons.ellipsisVertical,
                      size: 16,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              board.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (projectNames.isNotEmpty)
            Text(
              projectNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Icon(
              LucideIcons.arrowRight,
              size: 14,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Project filter chip ──────────────────────────

class _ProjectFilterChip extends StatelessWidget {
  const _ProjectFilterChip({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? projects
              .firstWhere((p) => p.id == selected, orElse: () => projects.first)
              .name
        : context.t('board.allProjects');

    return GlassPopupMenu<String?>(
      value: selected,
      onSelected: onChanged,
      items: [
        GlassMenuItem(value: null, label: context.t('board.allProjects')),
        ...projects.map((p) => GlassMenuItem(value: p.id, label: p.name)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Kanban column ────────────────────────────────

class _BoardColumn extends StatefulWidget {
  const _BoardColumn({
    required this.column,
    required this.issues,
    required this.palette,
    required this.names,
    required this.avatars,
    required this.onAccept,
    required this.canAccept,
    required this.onAddIssue,
    required this.onOpenIssue,
    this.laneMode = false,
    this.projectNames = const {},
  });

  final BoardColumnView column;
  final List<Issue> issues;
  final ProjectPalette palette;
  final Map<String, String> names;
  final Map<String, String> avatars;

  /// Project name by id — non-empty only on a board spanning several projects,
  /// where each card is tagged with the project it comes from. Empty on a
  /// single-project board, so nothing redundant is drawn.
  final Map<String, String> projectNames;
  final void Function(Issue) onAccept;

  /// Whether this column is a legal home for [issue] — false for the column it
  /// already sits in and for a merged cross-project column that doesn't carry
  /// the card's own workflow. Drives the drop affordance so an impossible drop
  /// is refused while it's still in the air, not with a toast afterwards.
  final bool Function(Issue) canAccept;
  final VoidCallback onAddIssue;
  final void Function(Issue) onOpenIssue;

  /// In a swimlane the board scrolls as one unit, so the column sizes to its
  /// content (no [Flexible], which needs a bounded height) instead of filling
  /// the viewport like the flat board's horizontally-scrolled columns.
  final bool laneMode;

  @override
  State<_BoardColumn> createState() => _BoardColumnState();
}

class _BoardColumnState extends State<_BoardColumn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final column = widget.column;
    final issues = widget.issues;
    final overWip = column.wipLimit != null && issues.length > column.wipLimit!;
    // Tint from the column's first workflow state, falling back to its display
    // name so the header dot still matches the theme when `states` is empty.
    // stateColor normalises case/separators, so either form resolves correctly.
    final dotColor = widget.palette.stateColor(
      column.states.isNotEmpty ? column.states.first : column.name,
    );
    final countLabel = column.wipLimit != null
        ? '${issues.length}/${column.wipLimit}'
        : '${issues.length}';

    // On mouse-driven platforms the "add issue" button stays hidden until the
    // column is hovered; on touch platforms (no hover) it's always visible.
    final platform = Theme.of(context).platform;
    final isTouch =
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.fuchsia;
    final revealAdd = isTouch || _hovered;

    return SizedBox(
      width: 300,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: DragTarget<Issue>(
          onWillAcceptWithDetails: (details) => widget.canAccept(details.data),
          onAcceptWithDetails: (details) => widget.onAccept(details.data),
          builder: (context, candidates, rejected) {
            final dropping = candidates.isNotEmpty;
            // A card hovering the column it already sits in is just home, so it
            // stays neutral; only a column that could never hold this card —
            // a merged cross-project column without its workflow — says no.
            final blocked =
                !dropping &&
                rejected.whereType<Issue>().any(
                  (i) => !column.states.contains(i.state),
                );
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: dropping ? AppColors.accentSoft : AppColors.canvas2,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(
                  width: 2,
                  color: dropping
                      ? AppColors.accentLine
                      : blocked
                      ? AppColors.danger.withValues(alpha: 0.35)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            column.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: overWip
                                ? AppColors.dangerSoft
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: overWip
                                  ? AppColors.danger.withValues(alpha: 0.3)
                                  : AppColors.hairline,
                            ),
                          ),
                          child: Text(
                            countLabel,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: overWip
                                  ? AppColors.danger
                                  : AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LaneAwareFlexible(
                    laneMode: widget.laneMode,
                    child: issues.isEmpty
                        ? const SizedBox(height: 8)
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: widget.laneMode
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            itemCount: issues.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final issue = issues[index];
                              // Plays only for the card that just completed a
                              // drop; every other card renders untouched.
                              final card = BoardLandingCard(
                                issueId: issue.id,
                                accent: widget.palette.stateColor(issue.state),
                                child: _BoardCard(
                                  issue: issue,
                                  palette: widget.palette,
                                  assigneeName: widget.names[issue.assigneeId],
                                  assigneeAvatar:
                                      widget.avatars[issue.assigneeId],
                                  projectName:
                                      widget.projectNames[issue.projectId],
                                  onOpen: () => widget.onOpenIssue(issue),
                                  onOpenIssue: widget.onOpenIssue,
                                ),
                              );
                              return BoardDragCard(
                                issue: issue,
                                // Touch platforms: no drag — it fights the
                                // scroll gesture. State changes happen in the
                                // detail sheet.
                                enabled: !isTouch,
                                ghost: _BoardCard(
                                  issue: issue,
                                  palette: widget.palette,
                                  assigneeName: widget.names[issue.assigneeId],
                                  assigneeAvatar:
                                      widget.avatars[issue.assigneeId],
                                  projectName:
                                      widget.projectNames[issue.projectId],
                                  dragging: true,
                                ),
                                child: card,
                              );
                            },
                          ),
                  ),
                  // The card's future home: opens at the foot of the column in
                  // the dragged card's own height, so nothing already on the
                  // wall has to move aside.
                  BoardDropSlot(open: dropping, hasCards: issues.isNotEmpty),
                  const SizedBox(height: 8),
                  // Reveal the add button on hover (mouse) / always (touch); keep
                  // its space reserved so columns don't resize.
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      opacity: revealAdd ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !revealAdd,
                        child: DottedAddButton(
                          label: context.t('board.addIssue'),
                          onTap: widget.onAddIssue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.issue,
    required this.palette,
    this.assigneeName,
    this.assigneeAvatar,
    this.projectName,
    this.dragging = false,
    this.onOpen,
    this.onOpenIssue,
  });

  final Issue issue;
  final ProjectPalette palette;
  final String? assigneeName;
  final String? assigneeAvatar;

  /// Set only on a cross-project board: which project this card belongs to. The
  /// readable id already encodes the project key, but on a merged wall the name
  /// is what makes two projects tellable apart at a glance.
  final String? projectName;
  final bool dragging;
  final VoidCallback? onOpen;

  /// Opens an arbitrary issue (used by the sub-task expander to navigate to a
  /// child); mirrors the board's own card-open handler.
  final void Function(Issue)? onOpenIssue;

  @override
  Widget build(BuildContext context) {
    final accent = palette.stateColor(issue.state);
    final due = dueLabel(issue.dueDate);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D191637),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: dragging ? null : onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 2, color: accent),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TypeGlyph(type: issue.type, size: 18),
                        const SizedBox(width: 8),
                        IdMono(issue.readableId),
                        if (projectName != null) ...[
                          const SizedBox(width: 7),
                          Flexible(child: _ProjectChip(name: projectName!)),
                        ],
                        const Spacer(),
                        PriorityFlag(priority: issue.priority),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      issue.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (issue.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final t in issue.tags.take(3))
                            LabelTag(t, hue: palette.labelHue(t)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (issue.estimateMinutes != null &&
                            issue.estimateMinutes! > 0)
                          _MiniMeta(
                            icon: LucideIcons.timer,
                            text: fmtDuration(issue.spentMinutes),
                          ),
                        if (due != null) ...[
                          if (issue.estimateMinutes != null)
                            const SizedBox(width: 10),
                          _MiniMeta(
                            icon: LucideIcons.calendar,
                            text: due.text,
                            color: due.late ? AppColors.danger : null,
                          ),
                        ],
                        const Spacer(),
                        if (issue.assigneeId != null)
                          HiveAvatar(
                            name: assigneeName ?? issue.assigneeId!,
                            imageUrl: assigneeAvatar,
                            size: 24,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // On-demand sub-task list + progress, full card width below the
              // body. Only on the interactive card (onOpenIssue set, not
              // dragging) — never the drag ghost/placeholder.
              if (!dragging && onOpenIssue != null && issue.hasSubtasks)
                SubtaskExpander(issue: issue, onOpenChild: onOpenIssue!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small neutral chip naming the project a card belongs to. Deliberately quiet
/// (no colour of its own): the card's accent stripe already carries the state
/// colour, and a second strong colour would fight it on a merged board.
class _ProjectChip extends StatelessWidget {
  const _ProjectChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            color: c,
          ),
        ),
      ],
    );
  }
}

/// Dashed "Add issue" button used at the foot of board columns.
class DottedAddButton extends StatefulWidget {
  const DottedAddButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<DottedAddButton> createState() => _DottedAddButtonState();
}

class _DottedAddButtonState extends State<DottedAddButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusControl);
    final accent = _hovered ? AppColors.accentStrong : AppColors.inkFaint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: _hovered ? AppColors.accentSoft : null,
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _hovered ? AppColors.accent : AppColors.hairline,
              radius: AppTheme.radiusControl,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.plus, size: 15, color: accent),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a rounded-rectangle border made of evenly spaced dashes.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double dashWidth = 5;
  static const double dashGap = 4;
  static const double strokeWidth = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
