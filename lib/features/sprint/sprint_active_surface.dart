import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/subtask_widgets.dart';
import '../board/board_drag.dart';
import '../board/board_filter.dart';
import '../board/board_swimlanes.dart';
import '../board/issue_quick_create.dart';
import 'widgets/glass_sprint_header.dart';

/// Active-sprint surface: the Liquid-Glass sprint header above a sprint-scoped
/// Kanban board (To Do → In Progress → In Review → Done, WIP limits, drag).
class SprintActiveSurface extends StatelessWidget {
  const SprintActiveSurface({
    super.key,
    required this.sprint,
    required this.columns,
    required this.issues,
    required this.filter,
    required this.onOpenIssue,
    required this.onMoveState,
    required this.quickCreateSeed,
    required this.onCreated,
    this.grouping = BoardGrouping.none,
    this.issuesById = const {},
    this.epics = const [],
    this.names = const {},
    this.avatars = const {},
    this.projectNames = const {},
    this.projectsById = const {},
  });

  final Sprint sprint;
  final List<BoardColumnView> columns;
  final List<Issue> issues;
  final BoardFilter filter;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue, String) onMoveState;

  /// Seeds the inline composer at the foot of a column: the sprint is this
  /// surface's own, [stateFor] resolves the column's workflow state for the
  /// project a ticket lands in.
  final IssueQuickCreateSeed Function(
    String? Function(Project project) stateFor,
  )
  quickCreateSeed;

  /// Fired once a composer created an issue, so the surface reloads.
  final ValueChanged<Issue> onCreated;

  /// Swimlane grouping for the sprint board (none = flat columns).
  final BoardGrouping grouping;
  final Map<String, Issue> issuesById;
  final List<Issue> epics;
  final Map<String, String> names;
  final Map<String, String> avatars;

  /// Project names by id — lane headers for the project grouping on a Scrum
  /// board that spans several projects.
  final Map<String, String> projectNames;

  /// The spanned projects, needed to resolve which of a merged column's states
  /// belongs to a dropped card's own project.
  final Map<String, Project> projectsById;

  /// Every active facet plus the epic facet (resolved per issue).
  bool _passes(Issue i) =>
      filter.matches(i) && filter.matchesEpic(boardEpicOf(i, issuesById));

  /// Seeds the composer under [column]: a ticket written there starts in this
  /// column's own workflow state. On a merged board the column carries one state
  /// per spanned project, so the state is resolved against the project the
  /// ticket actually lands in.
  IssueQuickCreateSeed _seedFor(BoardColumnView column) => quickCreateSeed(
    (project) => column.states.isEmpty
        ? null
        : column.states.firstWhere(
            (s) => project.stateNames.any(
              (own) => own.toLowerCase() == s.toLowerCase(),
            ),
            orElse: () => column.states.first,
          ),
  );

  bool _isBacklogColumn(BoardColumnView c) =>
      c.name.trim().toLowerCase() == 'backlog' ||
      c.states.any((s) => s.toUpperCase() == 'BACKLOG');

  /// Swimlane board for the active sprint — reuses the shared [BoardSwimlanes]
  /// with the sprint card column so it matches the Kanban board's grouping.
  Widget _grouped(
    BuildContext context,
    List<BoardColumnView> boardColumns,
    double gutter,
  ) {
    final lanes = computeBoardLanes(
      context: context,
      grouping: grouping,
      issues: issues.where(_passes).toList(),
      issuesById: issuesById,
      epics: epics,
      names: names,
      avatars: avatars,
      palette: ProjectPalette.empty,
      projectNames: projectNames,
      onOpenIssue: onOpenIssue,
    );
    if (lanes.isEmpty) {
      return Center(
        child: Text(
          context.t('board.empty'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    return BoardSwimlanes(
      columns: boardColumns,
      lanes: lanes,
      padding: EdgeInsets.fromLTRB(
        gutter,
        0,
        gutter,
        gutter + context.bottomGutter,
      ),
      columnBuilder: (column, colIssues, lane, width) => _SprintColumn(
        column: column,
        issues: colIssues,
        names: names,
        avatars: avatars,
        laneMode: true,
        width: width,
        projectsById: projectsById,
        onAccept: (issue) => onMoveState(
          issue,
          boardDropState(issue, column.states, projectsById) ?? issue.state,
        ),
        onOpenIssue: onOpenIssue,
        quickCreate: _seedFor(column),
        onCreated: onCreated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    final boardColumns = columns
        .where((c) => !_isBacklogColumn(c))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
          child: GlassSprintHeader(sprint: sprint),
        ),
        Expanded(
          child: boardColumns.isEmpty
              ? Center(
                  child: Text(
                    context.t('board.empty'),
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                )
              : grouping == BoardGrouping.none
              ? LayoutBuilder(
                  // Columns share the room the wall actually got, so a sprint
                  // with many states still shows them all where there is space.
                  builder: (context, constraints) {
                    final width = boardColumnWidth(
                      constraints.maxWidth - gutter * 2,
                      boardColumns.length,
                    );
                    final snap = boardSnapStride(context, columnWidth: width);
                    return BoardDragScroller(
                      snapStride: snap,
                      builder: (context, _, horizontal) => ListView.separated(
                        controller: horizontal,
                        scrollDirection: Axis.horizontal,
                        physics: BoardColumnSnapPhysics.maybe(snap),
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          0,
                          gutter,
                          gutter + context.bottomGutter,
                        ),
                        itemCount: boardColumns.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: BoardWall.columnGap),
                        itemBuilder: (context, index) {
                          final column = boardColumns[index];
                          final colIssues = issues
                              .where(
                                (i) =>
                                    column.states.contains(i.state) &&
                                    _passes(i) &&
                                    boardCardVisible(i, grouping),
                              )
                              .toList();
                          return _SprintColumn(
                            column: column,
                            width: width,
                            projectsById: projectsById,
                            issues: colIssues,
                            names: names,
                            avatars: avatars,
                            onAccept: (issue) => onMoveState(
                              issue,
                              boardDropState(
                                    issue,
                                    column.states,
                                    projectsById,
                                  ) ??
                                  issue.state,
                            ),
                            onOpenIssue: onOpenIssue,
                            quickCreate: _seedFor(column),
                            onCreated: onCreated,
                          );
                        },
                      ),
                    );
                  },
                )
              : _grouped(context, boardColumns, gutter),
        ),
      ],
    );
  }
}

class _SprintColumn extends StatelessWidget {
  const _SprintColumn({
    required this.column,
    required this.issues,
    required this.names,
    required this.avatars,
    required this.onAccept,
    required this.onOpenIssue,
    required this.quickCreate,
    required this.onCreated,
    this.laneMode = false,
    this.width = BoardWall.columnWidth,
    this.projectsById = const {},
  });

  final BoardColumnView column;
  final List<Issue> issues;

  /// Display name / avatar URL per user id — a card carries only the assignee
  /// id, which is not something to render at a person.
  final Map<String, String> names;
  final Map<String, String> avatars;
  final void Function(Issue) onAccept;
  final void Function(Issue) onOpenIssue;

  /// What an issue written in this column's inline composer inherits.
  final IssueQuickCreateSeed quickCreate;
  final ValueChanged<Issue> onCreated;

  /// The board's projects by id — see [_BoardColumn.projectsById]. Needed here
  /// for the same reason: a sprint board may span several projects, and a
  /// column only some of them have can't take everyone's cards.
  final Map<String, Project> projectsById;

  /// The key of [issue]'s project when this column refused it for a reason
  /// worth explaining — its workflow has no state here.
  String? _refusedProject(Issue issue, bool accepted) {
    if (accepted || column.states.contains(issue.state)) return null;
    return projectsById[issue.projectId]?.key;
  }

  /// In a swimlane the board scrolls as one unit, so the column sizes to its
  /// content (no [Flexible], which needs a bounded height). The lane also sizes
  /// the column itself, so [width] only follows it there.
  final bool laneMode;

  /// Set by the wall from the space it has — see [boardColumnWidth].
  final double width;

  @override
  Widget build(BuildContext context) {
    final overWip = column.wipLimit != null && issues.length > column.wipLimit!;
    // Prefer the project's configured state hue; fall back to the global palette.
    final dotColor = column.hue != null
        ? hueColor(column.hue!)
        : AppColors.stateColor(
            column.states.isNotEmpty ? column.states.first : column.name,
          );
    final countLabel = column.wipLimit != null
        ? '${issues.length}/${column.wipLimit}'
        : '${issues.length}';

    // Touch platforms get no drag — it fights the scroll gesture; state changes
    // happen in the issue detail sheet instead.
    final platform = Theme.of(context).platform;
    final isTouch =
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.fuchsia;

    return SizedBox(
      width: width,
      child: DragTarget<Issue>(
        // Was `!column.states.contains(state)` alone, with no project check: a
        // card from a project this column doesn't serve was *accepted*, then
        // resolved to its own state and silently did nothing. A gesture that
        // looks like it worked and didn't is worse than a refusal.
        onWillAcceptWithDetails: (d) {
          final accepted =
              !column.states.contains(d.data.state) &&
              boardDropState(d.data, column.states, projectsById) != null;
          boardDrag.blockedFor = _refusedProject(d.data, accepted);
          return accepted;
        },
        onAcceptWithDetails: (d) => onAccept(d.data),
        builder: (context, candidate, rejected) {
          final dropping = candidate.isNotEmpty;
          final blockedFor = dropping
              ? null
              : rejected
                    .whereType<Issue>()
                    .map((i) => _refusedProject(i, false))
                    .firstWhere((key) => key != null, orElse: () => null);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dropping ? AppColors.accentSoft : AppColors.canvas2,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: dropping
                    ? AppColors.accentLine
                    : blockedFor != null
                    ? AppColors.danger.withValues(alpha: 0.8)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                Column(
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
                          BoardColumnOwnerMark(
                            owners: boardColumnOwners(column, projectsById),
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
                      laneMode: laneMode,
                      child: issues.isEmpty
                          ? const SizedBox(height: 8)
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: laneMode
                                  ? const NeverScrollableScrollPhysics()
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              itemCount: issues.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 9),
                              itemBuilder: (context, index) {
                                final issue = issues[index];
                                return BoardDragCard(
                                  issue: issue,
                                  columnWidth: width,
                                  // Touch platforms: no drag — it fights the scroll
                                  // gesture; state changes happen in the sheet.
                                  enabled: !isTouch,
                                  ghost: _SprintCard(
                                    issue: issue,
                                    assigneeName: names[issue.assigneeId],
                                    assigneeAvatar: avatars[issue.assigneeId],
                                    accent: dotColor,
                                  ),
                                  child: BoardLandingCard(
                                    issueId: issue.id,
                                    accent: dotColor,
                                    child: _SprintCard(
                                      issue: issue,
                                      assigneeName: names[issue.assigneeId],
                                      assigneeAvatar: avatars[issue.assigneeId],
                                      accent: dotColor,
                                      onOpen: () => onOpenIssue(issue),
                                      onOpenIssue: onOpenIssue,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // The card's future home: opens at the foot of the column in
                    // the dragged card's own height, so nothing already on the wall
                    // has to move aside.
                    BoardDropSlot(open: dropping, hasCards: issues.isNotEmpty),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: IssueQuickCreate(
                        label: context.t('board.addIssue'),
                        seed: quickCreate,
                        onCreated: onCreated,
                      ),
                    ),
                  ],
                ),
                // Over the cards, never above them — the wall does not move
                // aside for a drag. Clears the header row.
                if (blockedFor != null)
                  Positioned(
                    left: 4,
                    right: 4,
                    top: 38,
                    child: BoardColumnBlockedNote(projectKey: blockedFor),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SprintCard extends StatelessWidget {
  const _SprintCard({
    required this.issue,
    this.assigneeName,
    this.assigneeAvatar,
    this.accent,
    this.onOpen,
    this.onOpenIssue,
  });

  final Issue issue;

  /// The assignee's display name and avatar, resolved from the board's user
  /// directory — the issue only carries the assignee id.
  final String? assigneeName;
  final String? assigneeAvatar;

  /// Project-configured state color for this card's column; falls back to the
  /// global palette when unknown.
  final Color? accent;
  final VoidCallback? onOpen;

  /// Opens an arbitrary issue (used by the sub-task expander to navigate to a
  /// child); mirrors the board's own card-open handler.
  final void Function(Issue)? onOpenIssue;

  @override
  Widget build(BuildContext context) {
    final accent =
        this.accent ?? AppColors.stateColor(issue.state.toUpperCase());
    final due = dueLabel(context, issue.dueDate);
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
          onTap: onOpen,
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
                        const Spacer(),
                        PriorityFlag(priority: issue.priority),
                        const SizedBox(width: 8),
                        _PointsPill(points: issue.storyPoints),
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
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (due != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.calendar,
                                size: 13,
                                color: due.late
                                    ? AppColors.danger
                                    : AppColors.inkFaint,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                due.text,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMono,
                                  fontSize: 11,
                                  color: due.late
                                      ? AppColors.danger
                                      : AppColors.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        const Spacer(),
                        if (issue.assigneeId != null)
                          Tooltip(
                            message: assigneeName ?? issue.assigneeId!,
                            child: HiveAvatar(
                              name: assigneeName ?? issue.assigneeId!,
                              imageUrl: assigneeAvatar,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // On-demand sub-task list + progress below the body. Only on the
              // interactive card (onOpenIssue set) — never the drag ghost.
              if (onOpenIssue != null && issue.hasSubtasks)
                SubtaskExpander(issue: issue, onOpenChild: onOpenIssue!),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points});

  final int? points;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        points == null ? '—' : '$points',
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: points == null ? AppColors.inkFaint : AppColors.ink,
        ),
      ),
    );
  }
}
