import 'package:flutter/material.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_widgets.dart';
import 'board_drag.dart';

/// Swimlane grouping for a board, Jira-style: each group becomes a horizontal
/// lane that still shows the full set of status columns.
enum BoardGrouping { none, epic, assignee, subtask, project }

String boardGroupingLabel(BuildContext context, BoardGrouping g) => switch (g) {
  BoardGrouping.none => context.t('board.group.none'),
  BoardGrouping.epic => context.t('board.group.epic'),
  BoardGrouping.assignee => context.t('board.group.assignee'),
  BoardGrouping.subtask => context.t('board.group.subtask'),
  BoardGrouping.project => context.t('board.group.project'),
};

/// Grouping options that make sense for a given board. Grouping by project is
/// only meaningful — and only offered — when the board actually spans more than
/// one project.
List<BoardGrouping> boardGroupingsFor({required bool crossProject}) => [
  for (final g in BoardGrouping.values)
    if (crossProject || g != BoardGrouping.project) g,
];

/// The "Group by" control shared by the Kanban board and the Scrum active
/// surface — a glass dropdown that mirrors the board's filter-button styling.
class BoardGroupByButton extends StatelessWidget {
  const BoardGroupByButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.options,
  });

  final BoardGrouping value;
  final ValueChanged<BoardGrouping> onChanged;

  /// Phone layouts show only the icon + chevron to save room.
  final bool compact;

  /// Which groupings to offer; defaults to all. Boards spanning a single
  /// project pass a list without [BoardGrouping.project], which would otherwise
  /// produce exactly one lane and just waste vertical space.
  final List<BoardGrouping>? options;

  @override
  Widget build(BuildContext context) {
    // Icon-only on phones so the header row still fits the view switcher and
    // the filter button. An active grouping would otherwise become invisible
    // once its label is gone, so the icon carries the accent instead.
    final narrow = compact || context.isCompact;
    final active = value != BoardGrouping.none;
    final label = active
        ? boardGroupingLabel(context, value)
        : context.t('board.groupBy');
    return GlassPopupMenu<BoardGrouping>(
      value: value,
      width: 220,
      onSelected: onChanged,
      items: [
        for (final g in options ?? BoardGrouping.values)
          GlassMenuItem(value: g, label: boardGroupingLabel(context, g)),
      ],
      child: Tooltip(
        message: label,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 11 : 14,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.rows3,
                  size: 16,
                  color: narrow && active
                      ? AppColors.accent
                      : AppColors.inkSoft,
                ),
                if (!narrow) ...[
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 15,
                    color: AppColors.inkFaint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The workflow state to write when [issue] is dropped into a column offering
/// [columnStates].
///
/// On a cross-project board a column merges equivalent states of several
/// projects (e.g. "Open" and "Neu"), so writing the first one blindly would
/// send a state the card's own project doesn't define — which the server rightly
/// rejects with `error.issue.unknownState`. Returns the one state of the column
/// that this issue's project actually has, or null when the drop isn't valid for
/// this card. Mirrors the server-side `WorkflowMapping.stateInColumn`.
///
/// [projectsById] may be empty (single-project board), in which case the first
/// state is used — the historical behaviour.
String? boardDropState(
  Issue issue,
  List<String> columnStates,
  Map<String, Project> projectsById,
) {
  if (columnStates.isEmpty) return null;
  final project = projectsById[issue.projectId];
  if (project == null) return columnStates.first;
  for (final state in columnStates) {
    for (final own in project.stateNames) {
      if (own.toLowerCase() == state.toLowerCase()) return own;
    }
  }
  return null;
}

/// Whether [column] holds a state [project]'s own workflow defines.
bool boardColumnCarries(Project project, BoardColumnView column) {
  for (final own in project.stateNames) {
    for (final state in column.states) {
      if (own.toLowerCase() == state.toLowerCase()) return true;
    }
  }
  return false;
}

/// Keys of the projects whose workflow this column carries — empty when every
/// project on the board has it, and on a single-project board.
///
/// A merged column stands for one step across several projects, but a step only
/// some of them took — a review stage another project never adopted — still
/// gets a column, and a card from a project without it can't go there. Saying
/// up front which projects a column belongs to turns that refusal from a
/// surprise into something the board already told you. A column they all share
/// says nothing, so it stays unmarked.
List<String> boardColumnOwners(
  BoardColumnView column,
  Map<String, Project> projectsById,
) {
  if (projectsById.length < 2) return const [];
  final owners = [
    for (final project in projectsById.values)
      if (boardColumnCarries(project, column)) project.key,
  ];
  return owners.length == projectsById.length ? const [] : owners;
}

/// The project keys of a column only some of the board's projects have.
/// Renders nothing when [owners] is empty — see [boardColumnOwners].
class BoardColumnOwnerMark extends StatelessWidget {
  const BoardColumnOwnerMark({super.key, required this.owners});

  final List<String> owners;

  @override
  Widget build(BuildContext context) {
    if (owners.isEmpty) return const SizedBox.shrink();
    final label = owners.join(' · ');
    return Tooltip(
      message: context.t(
        'board.columnOnlyIn',
        variables: {'projects': owners.join(', ')},
      ),
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// Says why a column in the air refuses the card: the card's project has no
/// state in it. Drawn over the column's cards rather than above them — the
/// board's rule is that nothing on the wall moves aside for a drag.
class BoardColumnBlockedNote extends StatelessWidget {
  const BoardColumnBlockedNote({super.key, required this.projectKey});

  final String projectKey;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.ban, size: 14, color: AppColors.danger),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            context.t(
              'board.dropBlockedShort',
              variables: {'project': projectKey},
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Lane key of the catch-all "no epic / no assignee / stand-alone" lane —
/// lanes with this key carry no group issue to pre-fill on create.
const String kBoardLaneNoneKey = '__none__';

/// One swimlane: a stable [key], a rendered [header] and the issues that belong
/// to the group (already passed through the board's filter).
class BoardLane {
  const BoardLane({
    required this.key,
    required this.header,
    required this.issues,
  });

  final String key;
  final Widget header;
  final List<Issue> issues;
}

/// The epic an issue ultimately rolls up to (null = none): a standard issue's
/// epic is its parent, a sub-task's epic is its grandparent. [byId] must index
/// every project issue so a sub-task can reach its grandparent.
String? boardEpicOf(Issue i, Map<String, Issue> byId) {
  final pid = i.parentId;
  if (pid == null) return null;
  final parent = byId[pid];
  if (parent == null) return null;
  if (parent.isEpic) return parent.id;
  final gp = parent.parentId != null ? byId[parent.parentId!] : null;
  return (gp != null && gp.isEpic) ? gp.id : null;
}

/// Jira-style board visibility — which issues surface as cards for the active
/// [grouping]. An **epic** is a container: it drives the epic swimlanes and the
/// epic filter, but never appears as a board card. A **sub-task** lives inside
/// its parent and becomes a card only under the "Sub-task" grouping, where it
/// sits beneath that parent's lane. Everything else — the Story / Task / Bug /
/// Feature work items — is always a card.
bool boardCardVisible(Issue i, BoardGrouping grouping) {
  if (i.isEpic) return false;
  if (i.isSubtask) return grouping == BoardGrouping.subtask;
  return true;
}

/// Groups [issues] into ordered lanes for [grouping]. Shared by the Kanban
/// board and the Scrum active surface so both behave identically.
List<BoardLane> computeBoardLanes({
  required BuildContext context,
  required BoardGrouping grouping,
  required List<Issue> issues,
  required Map<String, Issue> issuesById,
  required List<Issue> epics,
  required Map<String, String> names,
  required ProjectPalette palette,
  required void Function(Issue) onOpenIssue,
  Map<String, String> avatars = const {},
  Map<String, String> pronouns = const {},
  Map<String, String> projectNames = const {},
}) {
  // Drop issues that aren't board cards for this grouping (epics are always
  // headers/filters; sub-tasks are cards only under the sub-task grouping).
  final visible = [
    for (final i in issues)
      if (boardCardVisible(i, grouping)) i,
  ];
  switch (grouping) {
    case BoardGrouping.none:
      return const [];
    case BoardGrouping.epic:
      final byEpic = <String?, List<Issue>>{};
      for (final i in visible) {
        byEpic.putIfAbsent(boardEpicOf(i, issuesById), () => []).add(i);
      }
      final lanes = <BoardLane>[];
      for (final epic in epics) {
        final group = byEpic[epic.id];
        if (group == null || group.isEmpty) continue;
        lanes.add(
          BoardLane(
            key: epic.id,
            header: _issueLaneHeader(epic, group.length, palette, onOpenIssue),
            issues: group,
          ),
        );
      }
      _appendNone(
        lanes,
        byEpic[null],
        context.t('board.noEpic'),
        LucideIcons.zapOff,
      );
      return lanes;
    case BoardGrouping.assignee:
      final byUser = <String?, List<Issue>>{};
      for (final i in visible) {
        final a = (i.assigneeId?.isNotEmpty ?? false) ? i.assigneeId : null;
        byUser.putIfAbsent(a, () => []).add(i);
      }
      final ids = byUser.keys.whereType<String>().toList()
        ..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));
      final lanes = <BoardLane>[];
      for (final id in ids) {
        final name = names[id] ?? id;
        lanes.add(
          BoardLane(
            key: id,
            header: _avatarLaneHeader(
              name,
              byUser[id]!.length,
              imageUrl: avatars[id],
              pronouns: pronouns[id],
            ),
            issues: byUser[id]!,
          ),
        );
      }
      _appendNone(
        lanes,
        byUser[null],
        context.t('board.noAssignee'),
        LucideIcons.userX,
      );
      return lanes;
    case BoardGrouping.subtask:
      // Jira "Group by sub-task": every standard issue that owns sub-tasks
      // becomes a lane whose cards are those sub-tasks (the parent is the lane
      // header, not a card). Standard issues without sub-tasks — plus any
      // sub-task whose parent isn't on this board — gather in one "stand-alone"
      // lane as their own cards.
      final byParent = <String, List<Issue>>{};
      final orphans = <Issue>[];
      for (final i in visible) {
        if (!i.isSubtask) continue;
        final parent = i.parentId != null ? issuesById[i.parentId!] : null;
        if (parent != null && parent.isStandard) {
          byParent.putIfAbsent(parent.id, () => []).add(i);
        } else {
          orphans.add(i);
        }
      }
      final standalone = <Issue>[
        for (final i in visible)
          if (i.isStandard && !byParent.containsKey(i.id)) i,
        ...orphans,
      ];
      final parentIds = byParent.keys.toList()
        ..sort(
          (a, b) => (issuesById[a]?.readableId ?? a).compareTo(
            issuesById[b]?.readableId ?? b,
          ),
        );
      final lanes = <BoardLane>[];
      for (final id in parentIds) {
        lanes.add(
          BoardLane(
            key: id,
            header: _issueLaneHeader(
              issuesById[id]!,
              byParent[id]!.length,
              palette,
              onOpenIssue,
            ),
            issues: byParent[id]!,
          ),
        );
      }
      _appendNone(
        lanes,
        standalone,
        context.t('board.standalone'),
        LucideIcons.minus,
      );
      return lanes;
    case BoardGrouping.project:
      // Cross-project board: one lane per spanned project, so "Vorstand" and
      // "Ersti-Woche" work side by side on the same wall while each keeps its
      // own row. Lanes are ordered by project name for a stable layout.
      final byProject = <String, List<Issue>>{};
      for (final i in visible) {
        byProject.putIfAbsent(i.projectId, () => []).add(i);
      }
      final projectIds = byProject.keys.toList()
        ..sort(
          (a, b) => (projectNames[a] ?? a).toLowerCase().compareTo(
            (projectNames[b] ?? b).toLowerCase(),
          ),
        );
      return [
        for (final id in projectIds)
          BoardLane(
            key: id,
            header: _plainLaneHeader(
              projectNames[id] ?? id,
              byProject[id]!.length,
              LucideIcons.folderKanban,
            ),
            issues: byProject[id]!,
          ),
      ];
  }
}

void _appendNone(
  List<BoardLane> lanes,
  List<Issue>? group,
  String label,
  IconData icon,
) {
  if (group == null || group.isEmpty) return;
  lanes.add(
    BoardLane(
      key: kBoardLaneNoneKey,
      header: _plainLaneHeader(label, group.length, icon),
      issues: group,
    ),
  );
}

// ── lane headers ──────────────────────────────────────────────────────────

Widget _issueLaneHeader(
  Issue parent,
  int count,
  ProjectPalette palette,
  void Function(Issue) onOpenIssue,
) => Padding(
  padding: const EdgeInsets.only(bottom: 8, top: 4),
  child: Row(
    children: [
      InkWell(
        onTap: () => onOpenIssue(parent),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TypeGlyph(type: parent.type, size: 20),
              const SizedBox(width: 8),
              IdMono(parent.readableId, fontSize: 13),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  parent.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 10),
      StateDotBadge(
        state: parent.state,
        color: palette.stateColor(parent.state),
      ),
      const SizedBox(width: 10),
      _laneCount(count),
    ],
  ),
);

Widget _avatarLaneHeader(
  String name,
  int count, {
  String? imageUrl,
  String? pronouns,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 8, top: 4),
  child: Row(
    children: [
      HiveAvatar(name: name, imageUrl: imageUrl, pronouns: pronouns, size: 24),
      const SizedBox(width: 9),
      Text(
        name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 10),
      _laneCount(count),
    ],
  ),
);

Widget _plainLaneHeader(String label, int count, IconData icon) => Padding(
  padding: const EdgeInsets.only(bottom: 8, top: 4),
  child: Row(
    children: [
      Icon(icon, size: 18, color: AppColors.inkFaint),
      const SizedBox(width: 9),
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
      const SizedBox(width: 10),
      _laneCount(count),
    ],
  ),
);

Widget _laneCount(int count) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(99),
    border: Border.all(color: AppColors.hairline),
  ),
  child: Text(
    '$count',
    style: TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.inkSoft,
    ),
  ),
);

/// Wraps a column's card list in a [Flexible] on the flat board (bounded
/// viewport height) but renders it bare inside a swimlane, where the whole
/// board scrolls as one unit and a [Flexible] would have no bounded height.
class LaneAwareFlexible extends StatelessWidget {
  const LaneAwareFlexible({
    super.key,
    required this.laneMode,
    required this.child,
  });

  final bool laneMode;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      laneMode ? child : Flexible(child: child);
}

/// Renders [lanes] as one synced 2-D scroll: the vertical scroll stacks the
/// lanes, a single horizontal scroll moves every lane's columns together, and
/// columns size to their content so the whole board scrolls as one unit. Lanes
/// collapse/expand via a chevron on their header (state kept here).
class BoardSwimlanes extends StatefulWidget {
  const BoardSwimlanes({
    super.key,
    required this.columns,
    required this.lanes,
    required this.columnBuilder,
    this.padding = EdgeInsets.zero,
  });

  final List<BoardColumnView> columns;
  final List<BoardLane> lanes;

  /// Renders one column of a lane from the issues that fall in it. The [lane]
  /// carries the group context (e.g. the epic id as its key) so builders can
  /// pre-fill it when creating an issue from within the lane. The lane sizes
  /// the column itself and passes that width on, so what is drawn inside it —
  /// a carried card, say — can follow.
  final Widget Function(
    BoardColumnView column,
    List<Issue> laneColumnIssues,
    BoardLane lane,
    double columnWidth,
  )
  columnBuilder;

  final EdgeInsets padding;

  @override
  State<BoardSwimlanes> createState() => _BoardSwimlanesState();
}

class _BoardSwimlanesState extends State<BoardSwimlanes> {
  final Set<String> _collapsed = {};

  @override
  void didUpdateWidget(BoardSwimlanes old) {
    super.didUpdateWidget(old);
    // Drop collapse state for lanes that no longer exist (e.g. after a grouping
    // change) so the set doesn't leak keys.
    final keys = {for (final l in widget.lanes) l.key};
    _collapsed.removeWhere((k) => !keys.contains(k));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Columns share the room the lanes actually got, so a grouped board with
    // many columns still shows them all where there is space for it.
    builder: (context, constraints) => _wall(
      context,
      boardColumnWidth(
        constraints.maxWidth - widget.padding.horizontal,
        widget.columns.length,
      ),
    ),
  );

  Widget _wall(BuildContext context, double columnWidth) {
    final columns = widget.columns;
    const gap = BoardWall.columnGap;
    final boardWidth =
        columns.length * columnWidth + (columns.length - 1) * gap;
    // Vertical padding lives on the outer scroll view, but the horizontal
    // gutters must live INSIDE the horizontal scroll view — otherwise the
    // lanes are clipped at the gutter edge instead of scrolling under it.
    //
    // Both scroll views are driven by [BoardDragScroller] as well, so a card
    // carried to an edge pulls the wall along and can reach a lane or column
    // that is currently off-screen.
    final snap = boardSnapStride(context, columnWidth: columnWidth);
    return BoardDragScroller(
      snapStride: snap,
      builder: (context, vertical, horizontal) => SingleChildScrollView(
        controller: vertical,
        padding: EdgeInsets.only(
          top: widget.padding.top,
          bottom: widget.padding.bottom,
        ),
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          physics: BoardColumnSnapPhysics.maybe(snap),
          padding: EdgeInsetsDirectional.only(
            start: widget.padding.left,
            end: widget.padding.right,
          ),
          child: SizedBox(
            width: boardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final lane in widget.lanes) ...[
                  _laneHeaderBar(lane),
                  if (!_collapsed.contains(lane.key))
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < columns.length; i++) ...[
                          if (i > 0) const SizedBox(width: gap),
                          SizedBox(
                            width: columnWidth,
                            child: widget.columnBuilder(
                              columns[i],
                              lane.issues
                                  .where(
                                    (x) => columns[i].states.contains(x.state),
                                  )
                                  .toList(),
                              lane,
                              columnWidth,
                            ),
                          ),
                        ],
                      ],
                    ),
                  SizedBox(height: _collapsed.contains(lane.key) ? 6 : 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _laneHeaderBar(BoardLane lane) {
    final collapsed = _collapsed.contains(lane.key);
    return InkWell(
      onTap: () => setState(() {
        if (!_collapsed.remove(lane.key)) _collapsed.add(lane.key);
      }),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          Flexible(child: lane.header),
        ],
      ),
    );
  }
}
