import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_bulk_bar.dart';
import '../../core/widgets/hive_widgets.dart';
import '../search/search_tokens.dart';
import '../board/board_filter.dart';
import '../board/issue_quick_create.dart';
import 'sprint_format.dart';
import 'widgets/plan_row.dart';
import 'widgets/sprint_widgets.dart';

/// Planning (backlog) surface: stacked sprint containers above the paginated
/// product backlog. Drag issues between any container; multi-select + bulk
/// move; per-row story-point estimate; start / complete a sprint.
class SprintPlanningSurface extends StatelessWidget {
  const SprintPlanningSurface({
    super.key,
    required this.sprints,
    required this.activeSprintId,
    required this.issuesBySprint,
    required this.names,
    this.pronouns = const {},
    required this.avatars,
    required this.filter,
    required this.backlog,
    required this.backlogTotal,
    required this.backlogPage,
    required this.backlogPages,
    required this.pageSize,
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onPage,
    required this.onToggleSelect,
    required this.onClearSelection,
    required this.onOpenIssue,
    required this.onEstimate,
    required this.onMoveToSprint,
    required this.onBulkMove,
    required this.quickCreateSeed,
    required this.onCreated,
    required this.onCreateSprint,
    required this.onStartSprint,
    required this.onCompleteSprint,
  });

  final List<Sprint> sprints;
  final String? activeSprintId;
  final Map<String, List<Issue>> issuesBySprint;

  /// Display name / avatar URL per user id, so a row can show *who* an issue is
  /// assigned to. Without them a row only has the raw assignee id, which is not
  /// something to render at a person.
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final BoardFilter filter;
  final List<Issue> backlog;
  final int backlogTotal;
  final int backlogPage;
  final int backlogPages;
  final int pageSize;
  final Set<String> selected;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<int> onPage;
  final ValueChanged<String> onToggleSelect;
  final VoidCallback onClearSelection;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue) onEstimate;
  final void Function(Issue, String?) onMoveToSprint;
  final void Function(String?) onBulkMove;

  /// Seeds the inline composer of a section: the sprint it belongs to (null for
  /// the backlog) decides what a ticket written there inherits.
  final IssueQuickCreateSeed Function(String? sprintId) quickCreateSeed;

  /// Fired once a composer created an issue, so the surface reloads.
  final ValueChanged<Issue> onCreated;
  final VoidCallback onCreateSprint;
  final void Function(Sprint) onStartSprint;
  final void Function(Sprint) onCompleteSprint;

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            0,
            gutter,
            gutter + context.bottomGutter + (selected.isNotEmpty ? 72 : 0),
          ),
          children: [
            _toolbar(context),
            const SizedBox(height: 14),
            for (final s in sprints) ...[
              _SprintGroup(
                sprint: s,
                isActive: s.id == activeSprintId,
                names: names,
                avatars: avatars,
                pronouns: pronouns,
                issues: (issuesBySprint[s.id] ?? const [])
                    .where(filter.matches)
                    .where(_matchesQuery)
                    .toList(),
                selected: selected,
                onToggleSelect: onToggleSelect,
                onOpenIssue: onOpenIssue,
                onEstimate: onEstimate,
                onAccept: (issue) => onMoveToSprint(issue, s.id),
                quickCreate: quickCreateSeed(s.id),
                onCreated: onCreated,
                action: s.id == activeSprintId
                    ? GhostButton(
                        label: context.t('sprint.completeSprint'),
                        icon: LucideIcons.flag,
                        onPressed: () => onCompleteSprint(s),
                      )
                    : PrimaryButton(
                        label: context.t('sprint.startSprint'),
                        icon: LucideIcons.play,
                        onPressed: (issuesBySprint[s.id] ?? const []).isEmpty
                            ? null
                            : () => onStartSprint(s),
                      ),
              ),
              const SizedBox(height: 16),
            ],
            _BacklogGroup(
              issues: backlog.where(filter.matches).toList(),
              names: names,
              avatars: avatars,
              pronouns: pronouns,
              total: backlogTotal,
              page: backlogPage,
              pages: backlogPages,
              pageSize: pageSize,
              query: query,
              selected: selected,
              onToggleSelect: onToggleSelect,
              onOpenIssue: onOpenIssue,
              onEstimate: onEstimate,
              onAccept: (issue) => onMoveToSprint(issue, null),
              quickCreate: quickCreateSeed(null),
              onCreated: onCreated,
              onPage: onPage,
            ),
          ],
        ),
        if (selected.isNotEmpty)
          Positioned(
            left: gutter,
            right: gutter,
            bottom: context.bottomGutter + 12,
            child: Center(
              child: _BulkBar(
                count: selected.length,
                sprints: sprints,
                onMove: onBulkMove,
                onClose: onClearSelection,
              ),
            ),
          ),
      ],
    );
  }

  /// Free-text match used to filter sprint issues in-memory, mirroring the
  /// server-side backlog search (id / title / tags). The backlog list is
  /// already query-filtered upstream, so this only narrows the sprint groups.
  bool _matchesQuery(Issue issue) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return issue.readableId.toLowerCase().contains(q) ||
        issue.title.toLowerCase().contains(q) ||
        issue.tags.any((t) => t.toLowerCase().contains(q));
  }

  Widget _toolbar(BuildContext context) {
    final createButton = PrimaryButton(
      label: context.t('sprint.createSprint'),
      onPressed: onCreateSprint,
    );
    final search = _SearchField(query: query, onQuery: onQuery);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      // Phone: button + search share a single row, search flexes into the
      // remaining width so it never overflows the viewport. Desktop keeps the
      // button left and a fixed-width search pinned to the right.
      child: context.isCompact
          ? Row(
              children: [
                createButton,
                const SizedBox(width: 12),
                Expanded(child: search),
              ],
            )
          : Row(
              children: [
                createButton,
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: search,
                ),
              ],
            ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.query, required this.onQuery});

  final String query;
  final ValueChanged<String> onQuery;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.query,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onQuery,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(
          LucideIcons.search,
          size: 18,
          color: AppColors.inkFaint,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        hintText: context.t('sprint.filterIssues'),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          borderSide: BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          borderSide: BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}

/// A collapsible sprint container that is a drop target for issues.
class _SprintGroup extends StatefulWidget {
  const _SprintGroup({
    required this.sprint,
    required this.isActive,
    required this.issues,
    required this.names,
    required this.avatars,
    this.pronouns = const {},
    required this.selected,
    required this.onToggleSelect,
    required this.onOpenIssue,
    required this.onEstimate,
    required this.onAccept,
    required this.quickCreate,
    required this.onCreated,
    required this.action,
  });

  final Sprint sprint;
  final bool isActive;
  final List<Issue> issues;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final Set<String> selected;
  final ValueChanged<String> onToggleSelect;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue) onEstimate;
  final void Function(Issue) onAccept;
  final IssueQuickCreateSeed quickCreate;
  final ValueChanged<Issue> onCreated;
  final Widget action;

  @override
  State<_SprintGroup> createState() => _SprintGroupState();
}

class _SprintGroupState extends State<_SprintGroup> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.sprint;
    return DragTarget<Issue>(
      onWillAcceptWithDetails: (d) => d.data.sprintId != s.id,
      onAcceptWithDetails: (d) => widget.onAccept(d.data),
      builder: (context, candidate, rejected) {
        final dropping = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: dropping ? AppColors.accentSoft : AppColors.canvas2,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: dropping
                  ? AppColors.accentLine
                  : (widget.isActive
                        ? AppColors.accentLine
                        : AppColors.hairline),
              width: dropping ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SprintGroupHeader(
                sprint: s,
                isActive: widget.isActive,
                issues: widget.issues,
                collapsed: _collapsed,
                onToggleCollapse: () =>
                    setState(() => _collapsed = !_collapsed),
                action: widget.action,
              ),
              if (!_collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    children: [
                      if (widget.issues.isEmpty)
                        _EmptyDropHint(text: context.t('sprint.dragHere'))
                      else
                        for (final issue in widget.issues)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _DraggableRow(
                              issue: issue,
                              assigneeName: widget.names[issue.assigneeId],
                              assigneeAvatar: widget.avatars[issue.assigneeId],
                              selected: widget.selected.contains(issue.id),
                              onToggleSelect: () =>
                                  widget.onToggleSelect(issue.id),
                              onOpen: () => widget.onOpenIssue(issue),
                              onEstimate: () => widget.onEstimate(issue),
                            ),
                          ),
                      IssueQuickCreate(
                        label: context.t('sprint.addIssue'),
                        seed: widget.quickCreate,
                        onCreated: widget.onCreated,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SprintGroupHeader extends StatelessWidget {
  const _SprintGroupHeader({
    required this.sprint,
    required this.isActive,
    required this.issues,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.action,
  });

  final Sprint sprint;
  final bool isActive;
  final List<Issue> issues;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final title = Row(
      children: [
        InkWell(
          onTap: onToggleCollapse,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 180),
              turns: collapsed ? -0.25 : 0,
              child: Icon(
                LucideIcons.chevronDown,
                size: 18,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            sprint.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _StateBadge(active: isActive),
        if ((sprint.startDate != null && sprint.endDate != null)) ...[
          const SizedBox(width: 8),
          Text(
            dateRange(sprint.startDate, sprint.endDate),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ],
    );

    final issuesLabel = Text(
      issues.length == 1
          ? context.t('sprint.issueOne', variables: {'count': '1'})
          : context.t(
              'sprint.issuesMany',
              variables: {'count': '${issues.length}'},
            ),
      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: compact
          // Phone: stacked — count + buckets, full-width capacity, full-width
          // action (mirrors sprint.css body[data-bp="phone"] .sg-meta).
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if ((sprint.goal ?? '').isNotEmpty) _goal(context),
                const SizedBox(height: 12),
                Row(
                  children: [
                    issuesLabel,
                    const SizedBox(width: 12),
                    PointBuckets(issues: issues),
                  ],
                ),
                const SizedBox(height: 10),
                CapacityBar(
                  issues: issues,
                  capacity: sprint.capacityPoints,
                  width: double.infinity,
                ),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: action),
              ],
            )
          // Desktop: a single right-aligned row, action pinned to the far right.
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if ((sprint.goal ?? '').isNotEmpty) _goal(context),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                issuesLabel,
                const SizedBox(width: 14),
                PointBuckets(issues: issues),
                const SizedBox(width: 14),
                CapacityBar(
                  issues: issues,
                  capacity: sprint.capacityPoints,
                  width: context.isExpanded ? 188 : 150,
                ),
                const SizedBox(width: 14),
                action,
              ],
            ),
    );
  }

  Widget _goal(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 2, 0, 0),
    child: Text(
      sprint.goal!,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
    ),
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.accentSoft : AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? LucideIcons.zap : LucideIcons.clock,
            size: 12,
            color: active ? AppColors.accentStrong : AppColors.inkSoft,
          ),
          const SizedBox(width: 4),
          Text(
            context.t(active ? 'board.active' : 'sprint.planned'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _BacklogGroup extends StatefulWidget {
  const _BacklogGroup({
    required this.issues,
    required this.names,
    required this.avatars,
    this.pronouns = const {},
    required this.total,
    required this.page,
    required this.pages,
    required this.pageSize,
    required this.query,
    required this.selected,
    required this.onToggleSelect,
    required this.onOpenIssue,
    required this.onEstimate,
    required this.onAccept,
    required this.quickCreate,
    required this.onCreated,
    required this.onPage,
  });

  final List<Issue> issues;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final int total;
  final int page;
  final int pages;
  final int pageSize;
  final String query;
  final Set<String> selected;
  final ValueChanged<String> onToggleSelect;
  final void Function(Issue) onOpenIssue;
  final void Function(Issue) onEstimate;
  final void Function(Issue) onAccept;
  final IssueQuickCreateSeed quickCreate;
  final ValueChanged<Issue> onCreated;
  final ValueChanged<int> onPage;

  @override
  State<_BacklogGroup> createState() => _BacklogGroupState();
}

class _BacklogGroupState extends State<_BacklogGroup> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Issue>(
      onWillAcceptWithDetails: (d) => d.data.sprintId != null,
      onAcceptWithDetails: (d) => widget.onAccept(d.data),
      builder: (context, candidate, rejected) {
        final dropping = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: dropping ? AppColors.accentSoft : AppColors.canvas2,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: dropping ? AppColors.accentLine : AppColors.hairline,
              width: dropping ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 10),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _collapsed = !_collapsed),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 180),
                          turns: _collapsed ? -0.25 : 0,
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 18,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.t('sprint.backlog'),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Text(
                        '${widget.total}',
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: IssueQuickCreate(
                          label: context.t('sprint.addBacklogItem'),
                          seed: widget.quickCreate,
                          onCreated: widget.onCreated,
                        ),
                      ),
                      if (widget.issues.isEmpty)
                        _EmptyDropHint(
                          text: widget.query.isEmpty
                              ? context.t('sprint.backlogEmpty')
                              : context.t(
                                  'sprint.noMatches',
                                  variables: {'query': widget.query},
                                ),
                        )
                      else
                        for (final issue in widget.issues)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: _DraggableRow(
                              issue: issue,
                              assigneeName: widget.names[issue.assigneeId],
                              assigneeAvatar: widget.avatars[issue.assigneeId],
                              selected: widget.selected.contains(issue.id),
                              onToggleSelect: () =>
                                  widget.onToggleSelect(issue.id),
                              onOpen: () => widget.onOpenIssue(issue),
                              onEstimate: () => widget.onEstimate(issue),
                            ),
                          ),
                      if (widget.pages > 1)
                        _Pager(
                          page: widget.page,
                          pages: widget.pages,
                          total: widget.total,
                          pageSize: widget.pageSize,
                          onPage: widget.onPage,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Wraps a [PlanRow] in a [Draggable] so it can be dragged between containers.
class _DraggableRow extends StatelessWidget {
  const _DraggableRow({
    required this.issue,
    required this.assigneeName,
    required this.assigneeAvatar,
    required this.selected,
    required this.onToggleSelect,
    required this.onOpen,
    required this.onEstimate,
  });

  final Issue issue;
  final String? assigneeName;
  final String? assigneeAvatar;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onOpen;
  final VoidCallback onEstimate;

  @override
  Widget build(BuildContext context) {
    final row = PlanRow(
      issue: issue,
      assigneeName: assigneeName,
      assigneeAvatar: assigneeAvatar,
      selected: selected,
      onToggleSelect: onToggleSelect,
      onOpen: onOpen,
      onEstimate: onEstimate,
    );
    // Touch platforms get no drag — it fights the scroll gesture. Sprint
    // assignment happens via multi-select + bulk move or the detail sheet.
    final platform = Theme.of(context).platform;
    final isTouch =
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.fuchsia;
    if (isTouch) return row;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Draggable<Issue>(
          data: issue,
          dragAnchorStrategy: childDragAnchorStrategy,
          maxSimultaneousDrags: 1,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: width, child: row),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        );
      },
    );
  }
}

class _EmptyDropHint extends StatelessWidget {
  const _EmptyDropHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline, style: BorderStyle.solid),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  final int page;
  final int pages;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    // Window of up to 5 page buttons around the current page.
    final start = (page - 2).clamp(0, (pages - 5).clamp(0, pages));
    final visible = [
      for (var i = start; i < (start + 5).clamp(0, pages); i++) i,
    ];
    final from = page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pageBtn(
            child: const Icon(LucideIcons.chevronLeft, size: 18),
            enabled: page > 0,
            onTap: () => onPage(page - 1),
          ),
          const SizedBox(width: 6),
          for (final i in visible) ...[
            _pageBtn(
              child: Text('${i + 1}'),
              selected: i == page,
              enabled: true,
              onTap: () => onPage(i),
            ),
            const SizedBox(width: 6),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$from–$to ${context.t('common.of')} $total',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.inkSoft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _pageBtn(
            child: const Icon(LucideIcons.chevronRight, size: 18),
            enabled: page < pages - 1,
            onTap: () => onPage(page + 1),
          ),
        ],
      ),
    );
  }

  Widget _pageBtn({
    required Widget child,
    required bool enabled,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: selected ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppColors.navy : AppColors.hairline,
                ),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.inkSoft,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: selected ? Colors.white : AppColors.inkSoft,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.sprints,
    required this.onMove,
    required this.onClose,
  });

  final int count;
  final List<Sprint> sprints;
  final void Function(String?) onMove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    return GlassBulkBar(
      countLabel: context.t(
        'sprint.selectedCount',
        variables: {'count': '$count'},
      ),
      onClear: onClose,
      actions: [
        Container(
          decoration: BoxDecoration(
            color: tokens.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              hint: Text(
                context.t('sprint.moveTo'),
                style: TextStyle(color: tokens.inkSoft, fontSize: 12.5),
              ),
              dropdownColor: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              isDense: true,
              iconEnabledColor: tokens.inkSoft,
              style: TextStyle(color: tokens.ink, fontSize: 12.5),
              items: [
                for (final s in sprints)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
                DropdownMenuItem(
                  value: '__backlog',
                  child: Text(context.t('sprint.backlog')),
                ),
              ],
              onChanged: (v) {
                if (v != null) onMove(v == '__backlog' ? null : v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
