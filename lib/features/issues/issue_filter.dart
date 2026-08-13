import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import '../../core/models/work_models.dart';

/// The facets the Issues overview can filter on. Mirrors the board filter but
/// swaps the board-only facets (sprint / author / label / epic) for the
/// cross-project facets that make sense on a global task list.
enum IssueFilterFacet { state, priority, assignee, project, type }

/// A preset the Issues overview can open pre-filtered on — used by dashboard
/// KPI deep-links (`/issues?view=…`). Bucket presets ([inProgress], [backlog],
/// [done]) resolve to concrete workflow-state names once projects are loaded;
/// [today] applies the "due today" time range.
enum IssuesInitialView { today, inProgress, backlog, done }

/// Swimlane-style grouping for the Issues list. [none] renders one flat list;
/// every other value buckets the (already filtered) issues under section
/// headers.
enum IssueGrouping { none, state, priority, assignee, project, type }

/// Server-side ordering for the Issues list. Sorting runs on the backend so it
/// is correct across the *whole* paginated result set (not just the pages
/// currently scrolled into view); changing it refetches from page 0. Each value
/// carries the [wire] token the backend `?sort=` param understands.
///
/// [updatedDesc] is the default — it preserves the historical "most recently
/// touched first" ordering, so existing behaviour is unchanged until the user
/// picks something else.
enum IssueSort {
  createdDesc('created'),
  createdAsc('created_asc'),
  updatedDesc('updated'),
  updatedAsc('updated_asc');

  const IssueSort(this.wire);

  /// The backend `?sort=` token.
  final String wire;

  static const defaultSort = IssueSort.updatedDesc;

  bool get isDefault => this == defaultSort;
}

/// Multi-criteria filter for the Issues overview. Empty sets mean "no
/// restriction" for that facet. State / priority / type are stored as
/// UPPER-CASE backend codes; [assignees] hold user ids and [projects] hold
/// project ids. Facets combine with AND across facets and OR within a facet —
/// identical semantics to the board filter so the UX reads the same.
@immutable
class IssueFilter {
  const IssueFilter({
    this.states = const {},
    this.priorities = const {},
    this.assignees = const {},
    this.projects = const {},
    this.types = const {},
    this.archivedOnly = false,
  });

  final Set<String> states;
  final Set<String> priorities;
  final Set<String> assignees;
  final Set<String> projects;
  final Set<String> types;

  /// Server-side facet: show archived (soft-deleted) issues instead of the
  /// active ones. Toggling it triggers a refetch, not a client-side filter.
  final bool archivedOnly;

  /// Sentinel used in [assignees] to match issues with no assignee.
  static const noAssignee = '__none__';

  bool get isEmpty =>
      states.isEmpty &&
      priorities.isEmpty &&
      assignees.isEmpty &&
      projects.isEmpty &&
      types.isEmpty &&
      !archivedOnly;

  int get activeCount =>
      states.length +
      priorities.length +
      assignees.length +
      projects.length +
      types.length +
      (archivedOnly ? 1 : 0);

  Set<String> facet(IssueFilterFacet f) => switch (f) {
    IssueFilterFacet.state => states,
    IssueFilterFacet.priority => priorities,
    IssueFilterFacet.assignee => assignees,
    IssueFilterFacet.project => projects,
    IssueFilterFacet.type => types,
  };

  /// Whether [issue] passes every active facet (AND across facets, OR within).
  bool matches(Issue issue) {
    if (states.isNotEmpty && !states.contains(issue.state.toUpperCase())) {
      return false;
    }
    if (priorities.isNotEmpty &&
        !priorities.contains(issue.priority.toUpperCase())) {
      return false;
    }
    if (assignees.isNotEmpty) {
      // Match any assignee (primary or secondary), mirroring the backend which
      // checks both assigneeIds and the legacy assigneeId.
      final ids = issue.assigneeIds.isNotEmpty
          ? issue.assigneeIds
          : (issue.assigneeId != null && issue.assigneeId!.isNotEmpty
                ? [issue.assigneeId!]
                : const <String>[]);
      final matchesId = ids.any(assignees.contains);
      final matchesNone = ids.isEmpty && assignees.contains(noAssignee);
      if (!matchesId && !matchesNone) return false;
    }
    if (projects.isNotEmpty && !projects.contains(issue.projectId)) {
      return false;
    }
    if (types.isNotEmpty && !types.contains(issue.type.toUpperCase())) {
      return false;
    }
    return true;
  }

  IssueFilter copyWith({
    Set<String>? states,
    Set<String>? priorities,
    Set<String>? assignees,
    Set<String>? projects,
    Set<String>? types,
    bool? archivedOnly,
  }) => IssueFilter(
    states: states ?? this.states,
    priorities: priorities ?? this.priorities,
    assignees: assignees ?? this.assignees,
    projects: projects ?? this.projects,
    types: types ?? this.types,
    archivedOnly: archivedOnly ?? this.archivedOnly,
  );

  /// Returns a copy with [value] toggled in [facet].
  IssueFilter toggle(IssueFilterFacet facet, String value) {
    Set<String> next(Set<String> current) {
      final updated = {...current};
      if (!updated.remove(value)) updated.add(value);
      return updated;
    }

    return switch (facet) {
      IssueFilterFacet.state => copyWith(states: next(states)),
      IssueFilterFacet.priority => copyWith(priorities: next(priorities)),
      IssueFilterFacet.assignee => copyWith(assignees: next(assignees)),
      IssueFilterFacet.project => copyWith(projects: next(projects)),
      IssueFilterFacet.type => copyWith(types: next(types)),
    };
  }

  static const empty = IssueFilter();
}

/// Canonical facet code lists, display-ordered, mirroring the backend enums
/// (`Issue.Type` / `Issue.Priority`). Used so the filter can always offer every
/// value even though the loaded list is now server-filtered and would
/// otherwise only surface the codes present in the current result page.
const kIssueTypeCodes = ['EPIC', 'STORY', 'TASK', 'BUG', 'FEATURE', 'SUBTASK'];
const kIssuePriorityCodes = [
  'SHOWSTOPPER',
  'CRITICAL',
  'MAJOR',
  'NORMAL',
  'MINOR',
  'TRIVIAL',
];

/// The distinct facet values available to filter on, derived from the issues
/// currently loaded (plus the known projects so the project facet resolves
/// names). Preserves first-seen order.
class IssueFilterOptions {
  IssueFilterOptions({
    required this.states,
    required this.priorities,
    required this.assignees,
    required this.projects,
    required this.types,
    required this.hasUnassigned,
  });

  /// UPPER-CASE workflow-state codes.
  final List<String> states;

  /// UPPER-CASE priority codes.
  final List<String> priorities;

  /// Assignee user ids (the "Unassigned" sentinel is added by the UI when
  /// [hasUnassigned] is set).
  final List<String> assignees;

  /// Project ids that own at least one loaded issue.
  final List<String> projects;

  /// UPPER-CASE issue-type codes.
  final List<String> types;

  /// Whether at least one loaded issue has no assignee.
  final bool hasUnassigned;

  bool get isEmpty =>
      states.isEmpty &&
      priorities.isEmpty &&
      assignees.isEmpty &&
      projects.isEmpty &&
      types.isEmpty;

  /// Builds the full facet value space from reference data (all workflow states
  /// across projects, the whole directory, every project) plus the fixed type /
  /// priority enums — independent of which issues are currently loaded, so
  /// server-side filtering never shrinks the pickable options.
  factory IssueFilterOptions.reference({
    required List<String> states,
    required List<String> assignees,
    required List<String> projects,
  }) => IssueFilterOptions(
    states: states,
    priorities: kIssuePriorityCodes,
    assignees: assignees,
    projects: projects,
    types: kIssueTypeCodes,
    hasUnassigned: true,
  );

  factory IssueFilterOptions.from(Iterable<Issue> issues) {
    final states = <String>{};
    final priorities = <String>{};
    final assignees = <String>{};
    final projects = <String>{};
    final types = <String>{};
    var hasUnassigned = false;
    for (final issue in issues) {
      if (issue.state.isNotEmpty) states.add(issue.state.toUpperCase());
      if (issue.priority.isNotEmpty) {
        priorities.add(issue.priority.toUpperCase());
      }
      // Collect every assignee (primary AND secondary), mirroring
      // IssueFilter.matches — otherwise someone who is only a co-assignee never
      // shows up as a selectable filter value.
      final ids = issue.assigneeIds.isNotEmpty
          ? issue.assigneeIds
          : (issue.assigneeId != null && issue.assigneeId!.isNotEmpty
                ? [issue.assigneeId!]
                : const <String>[]);
      if (ids.isEmpty) {
        hasUnassigned = true;
      } else {
        assignees.addAll(ids);
      }
      if (issue.projectId.isNotEmpty) projects.add(issue.projectId);
      if (issue.type.isNotEmpty) types.add(issue.type.toUpperCase());
    }
    return IssueFilterOptions(
      states: states.toList(),
      priorities: priorities.toList(),
      assignees: assignees.toList(),
      projects: projects.toList(),
      types: types.toList(),
      hasUnassigned: hasUnassigned,
    );
  }
}

// ─────────────────────────── time range ───────────────────────────────────

/// Preset windows offered by the time-range picker. [all] disables the filter;
/// [custom] defers to a user-picked [DateTimeRange]; [overdue] is special-cased
/// (past-due, still open) since it has no clean upper bound.
enum IssueTimePreset {
  all,
  overdue,

  /// Due today or overdue (due date on/before today, still open). Powers the
  /// dashboard "Today's tasks" deep-link so its count matches this list exactly.
  dueByToday,
  today,
  thisWeek,
  thisMonth,
  last7,
  last30,
  next7,
  next30,
  custom,
}

/// A selected time window plus the logic that decides whether an issue falls
/// inside it.
///
/// Matching is schedule-aware so it stays intuitive: an issue with both a start
/// and a due date matches when that interval *overlaps* the window; an issue
/// with only one of the two matches when that date is inside the window; an
/// issue with neither falls back to its last-activity date ([Issue.updatedAt])
/// so freshly-touched but unscheduled work still surfaces.
@immutable
class IssueTimeRange {
  const IssueTimeRange({this.preset = IssueTimePreset.all, this.custom});

  final IssueTimePreset preset;

  /// Only set when [preset] is [IssueTimePreset.custom].
  final DateTimeRange? custom;

  bool get isActive => preset != IssueTimePreset.all;

  static const none = IssueTimeRange();

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The concrete inclusive day-bounds for a window, or null when the preset
  /// carries no fixed range ([all] / [overdue]).
  DateTimeRange? resolve(DateTime now) {
    final today = _dayOf(now);
    DateTimeRange r(DateTime from, DateTime to) =>
        DateTimeRange(start: from, end: to);
    switch (preset) {
      case IssueTimePreset.all:
      case IssueTimePreset.overdue:
      case IssueTimePreset.dueByToday:
        return null;
      case IssueTimePreset.today:
        return r(today, today);
      case IssueTimePreset.thisWeek:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return r(monday, monday.add(const Duration(days: 6)));
      case IssueTimePreset.thisMonth:
        final first = DateTime(today.year, today.month, 1);
        final last = DateTime(today.year, today.month + 1, 0);
        return r(first, last);
      case IssueTimePreset.last7:
        return r(today.subtract(const Duration(days: 6)), today);
      case IssueTimePreset.last30:
        return r(today.subtract(const Duration(days: 29)), today);
      case IssueTimePreset.next7:
        return r(today, today.add(const Duration(days: 6)));
      case IssueTimePreset.next30:
        return r(today, today.add(const Duration(days: 29)));
      case IssueTimePreset.custom:
        final c = custom;
        if (c == null) return null;
        return r(_dayOf(c.start), _dayOf(c.end));
    }
  }

  bool matches(Issue issue, {DateTime? clock}) {
    if (!isActive) return true;
    final now = clock ?? DateTime.now();
    if (preset == IssueTimePreset.overdue) {
      final due = issue.dueDate;
      return due != null &&
          _dayOf(due).isBefore(_dayOf(now)) &&
          !issue.resolved;
    }
    if (preset == IssueTimePreset.dueByToday) {
      // Due today or overdue, still open — mirrors the backend "today's tasks".
      final due = issue.dueDate;
      return due != null &&
          !_dayOf(due).isAfter(_dayOf(now)) &&
          !issue.resolved;
    }
    final range = resolve(now);
    if (range == null) return true;
    final from = range.start;
    final to = range.end;
    bool inRange(DateTime? d) {
      if (d == null) return false;
      final day = _dayOf(d);
      return !day.isBefore(from) && !day.isAfter(to);
    }

    final start = issue.startDate;
    final due = issue.dueDate;
    if (start != null && due != null) {
      // Interval overlap: starts on/before the window ends AND ends on/after it
      // begins.
      return !_dayOf(start).isAfter(to) && !_dayOf(due).isBefore(from);
    }
    if (due != null) return inRange(due);
    if (start != null) return inRange(start);
    return inRange(issue.updatedAt);
  }
}
