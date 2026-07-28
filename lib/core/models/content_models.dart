import 'package:equatable/equatable.dart';

import '../util/dates.dart';

import 'work_models.dart';

class Article extends Equatable {
  const Article({
    required this.id,
    required this.title,
    this.content,
    this.contentDoc,
    this.projectId,
    this.teamId,
    this.parentId,
    this.space,
    this.icon,
    this.authorId,
    this.tags = const [],
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;

  /// Plain text of [contentDoc]. Excerpts, search previews and the tree read
  /// this; the server derives it on every write.
  final String? content;

  /// The Lexical document — the source of truth, and what the reader renders.
  final String? contentDoc;

  /// Project the article is scoped to (visible only with project access).
  final String? projectId;

  /// Team the article belongs to (team-wide, no project). Null otherwise.
  final String? teamId;
  final String? parentId;

  /// Knowledge-base space (e.g. "Engineering"); null for ungrouped articles.
  final String? space;

  /// Lucide icon name (kebab-case) for the article glyph.
  final String? icon;
  final String? authorId;
  final List<String> tags;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Article.fromJson(Map<String, dynamic> json) => Article(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    content: json['content'] as String?,
    contentDoc: json['contentDoc'] as String?,
    projectId: json['projectId'] as String?,
    teamId: json['teamId'] as String?,
    parentId: json['parentId'] as String?,
    space: json['space'] as String?,
    icon: json['icon'] as String?,
    authorId: json['authorId'] as String?,
    tags: ((json['tags'] as List<dynamic>?) ?? const []).cast<String>(),
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: parseInstant(json['createdAt']),
    updatedAt: parseInstant(json['updatedAt']),
  );

  @override
  List<Object?> get props => [id, title, parentId, space, updatedAt];
}

/// A knowledge-base space ("Bereich"). Its [name] is the key articles reference
/// through [Article.space]; icon/hue/description carry the space's chrome.
class Space extends Equatable {
  const Space({
    required this.id,
    required this.name,
    this.icon,
    this.hue = 250,
    this.description = '',
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? icon;
  final int hue;
  final String description;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Space.fromJson(Map<String, dynamic> json) => Space(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    icon: json['icon'] as String?,
    hue: (json['hue'] as num?)?.toInt() ?? 250,
    description: json['description'] as String? ?? '',
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    createdAt: parseInstant(json['createdAt']),
    updatedAt: parseInstant(json['updatedAt']),
  );

  @override
  List<Object?> get props => [id, name, icon, hue, description, sortOrder];
}

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.read,
    this.body,
    this.link,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final bool read;
  final String? body;
  final String? link;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'SYSTEM',
        title: json['title'] as String? ?? '',
        read: json['read'] as bool? ?? false,
        body: json['body'] as String?,
        link: json['link'] as String?,
        createdAt: parseInstant(json['createdAt']),
      );

  @override
  List<Object?> get props => [id, read, title];
}

class ProjectCompletion extends Equatable {
  const ProjectCompletion({
    required this.done,
    required this.inProgress,
    required this.backlog,
    required this.total,
  });

  final int done;
  final int inProgress;
  final int backlog;
  final int total;

  double get donePercent => total == 0 ? 0 : done / total;
  double get inProgressPercent => total == 0 ? 0 : inProgress / total;
  double get backlogPercent => total == 0 ? 0 : backlog / total;

  factory ProjectCompletion.fromJson(Map<String, dynamic> json) =>
      ProjectCompletion(
        done: json['done'] as int? ?? 0,
        inProgress: json['inProgress'] as int? ?? 0,
        backlog: json['backlog'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [done, inProgress, backlog, total];
}

class RankEntry extends Equatable {
  const RankEntry({
    required this.userId,
    required this.displayName,
    required this.points,
    this.title,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final int points;
  final String? title;
  final String? avatarUrl;

  factory RankEntry.fromJson(Map<String, dynamic> json) => RankEntry(
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    points: json['points'] as int? ?? 0,
    title: json['title'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );

  @override
  List<Object?> get props => [userId, points];
}

class TrackerDay extends Equatable {
  const TrackerDay({required this.date, required this.focusMinutes});

  final DateTime date;
  final int focusMinutes;

  factory TrackerDay.fromJson(Map<String, dynamic> json) => TrackerDay(
    date: parseDate(json['date'])!,
    focusMinutes: json['focusMinutes'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [date, focusMinutes];
}

/// One day in the created-vs-resolved trend used to derive a burndown.
class TrendPoint extends Equatable {
  const TrendPoint({
    required this.date,
    required this.created,
    required this.resolved,
  });

  final DateTime date;
  final int created;
  final int resolved;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    date: parseDate(json['date'])!,
    created: (json['created'] as num?)?.toInt() ?? 0,
    resolved: (json['resolved'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [date, created, resolved];
}

/// One ISO calendar week of tracked focus time (the "Month" tracker range).
class TrackerWeek extends Equatable {
  const TrackerWeek({required this.week, required this.focusMinutes});

  final int week;
  final int focusMinutes;

  factory TrackerWeek.fromJson(Map<String, dynamic> json) => TrackerWeek(
    week: (json['week'] as num?)?.toInt() ?? 0,
    focusMinutes: (json['focusMinutes'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [week, focusMinutes];
}

/// A member of the active sprint, resolved for avatar display.
class SprintMember extends Equatable {
  const SprintMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;

  factory SprintMember.fromJson(Map<String, dynamic> json) => SprintMember(
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
  );

  @override
  List<Object?> get props => [userId, displayName, avatarUrl];
}

/// Snapshot of the caller's active board powering the dashboard hero — either a
/// running sprint (`kind == 'SPRINT'`) or a Kanban-board overview
/// (`kind == 'KANBAN'`). Sprint-only fields are 0 for Kanban.
class DashboardBoard extends Equatable {
  const DashboardBoard({
    required this.kind,
    required this.boardId,
    required this.name,
    required this.day,
    required this.days,
    required this.points,
    required this.pointsTotal,
    required this.issuesDone,
    required this.issuesTotal,
    required this.members,
    this.goal,
  });

  /// `SPRINT` (running sprint) or `KANBAN` (board overview).
  final String kind;
  final String boardId;
  final String name;
  final String? goal;
  final int day;
  final int days;
  final int points;
  final int pointsTotal;
  final int issuesDone;
  final int issuesTotal;
  final List<SprintMember> members;

  bool get isSprint => kind == 'SPRINT';

  /// Ring progress: story points for sprints, issue completion for Kanban.
  double get progressPercent {
    final ratio = isSprint
        ? (pointsTotal == 0 ? 0.0 : points / pointsTotal)
        : (issuesTotal == 0 ? 0.0 : issuesDone / issuesTotal);
    return ratio.clamp(0.0, 1.0);
  }

  factory DashboardBoard.fromJson(Map<String, dynamic> json) => DashboardBoard(
    kind: json['kind'] as String? ?? 'SPRINT',
    boardId: json['boardId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    goal: json['goal'] as String?,
    day: (json['day'] as num?)?.toInt() ?? 0,
    days: (json['days'] as num?)?.toInt() ?? 0,
    points: (json['points'] as num?)?.toInt() ?? 0,
    pointsTotal: (json['pointsTotal'] as num?)?.toInt() ?? 0,
    issuesDone: (json['issuesDone'] as num?)?.toInt() ?? 0,
    issuesTotal: (json['issuesTotal'] as num?)?.toInt() ?? 0,
    members: ((json['members'] as List<dynamic>?) ?? const [])
        .map((m) => SprintMember.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [
    kind,
    boardId,
    day,
    points,
    pointsTotal,
    issuesDone,
    issuesTotal,
  ];
}

/// A recent development event (commit / PR / deploy / merge) for the git feed.
class GitEvent extends Equatable {
  const GitEvent({
    required this.kind,
    required this.ref,
    required this.text,
    this.repo,
    this.authorName,
    this.at,
    this.issueKey,
  });

  /// One of: `commit`, `pr`, `deploy`, `merge`.
  final String kind;
  final String ref;
  final String text;
  final String? repo;
  final String? authorName;
  final DateTime? at;
  final String? issueKey;

  factory GitEvent.fromJson(Map<String, dynamic> json) => GitEvent(
    kind: json['kind'] as String? ?? 'commit',
    ref: json['ref'] as String? ?? '',
    text: json['text'] as String? ?? '',
    repo: json['repo'] as String?,
    authorName: json['authorName'] as String?,
    at: parseInstant(json['at']),
    issueKey: json['issueKey'] as String?,
  );

  @override
  List<Object?> get props => [kind, ref, text, at, issueKey];
}

/// A board the user can pin to the dashboard hero (populates the picker).
class DashboardBoardOption extends Equatable {
  const DashboardBoardOption({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;

  /// `KANBAN` or `SCRUM`.
  final String type;

  bool get isScrum => type == 'SCRUM';

  factory DashboardBoardOption.fromJson(Map<String, dynamic> json) =>
      DashboardBoardOption(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'KANBAN',
      );

  @override
  List<Object?> get props => [id, name, type];
}

/// The user's saved dashboard personalisation (hero board, data scope, hidden
/// cards). Empty [projectIds]/[teamIds] mean "all" (the default view).
class DashboardPrefs extends Equatable {
  const DashboardPrefs({
    this.boardId,
    this.projectIds = const [],
    this.teamIds = const [],
    this.hiddenCards = const [],
  });

  final String? boardId;
  final List<String> projectIds;
  final List<String> teamIds;
  final List<String> hiddenCards;

  static const empty = DashboardPrefs();

  bool isHidden(String card) => hiddenCards.contains(card);

  DashboardPrefs copyWith({
    String? boardId,
    bool clearBoard = false,
    List<String>? projectIds,
    List<String>? teamIds,
    List<String>? hiddenCards,
  }) => DashboardPrefs(
    boardId: clearBoard ? null : (boardId ?? this.boardId),
    projectIds: projectIds ?? this.projectIds,
    teamIds: teamIds ?? this.teamIds,
    hiddenCards: hiddenCards ?? this.hiddenCards,
  );

  DashboardPrefs toggleCard(String card, {required bool hidden}) {
    final next = List<String>.from(hiddenCards)..remove(card);
    if (hidden) next.add(card);
    return copyWith(hiddenCards: next);
  }

  factory DashboardPrefs.fromJson(Map<String, dynamic> json) => DashboardPrefs(
    boardId: (json['boardId'] as String?)?.isEmpty ?? true
        ? null
        : json['boardId'] as String?,
    projectIds: ((json['projectIds'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    teamIds: ((json['teamIds'] as List<dynamic>?) ?? const []).cast<String>(),
    hiddenCards: ((json['hiddenCards'] as List<dynamic>?) ?? const [])
        .cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'boardId': boardId,
    'projectIds': projectIds,
    'teamIds': teamIds,
    'hiddenCards': hiddenCards,
  };

  @override
  List<Object?> get props => [boardId, projectIds, teamIds, hiddenCards];
}

class DashboardData extends Equatable {
  const DashboardData({
    required this.todayTasks,
    required this.completion,
    required this.ranking,
    required this.tracker,
    this.todayCount = 0,
    this.trackerMonth = const [],
    this.activeBoard,
    this.gitActivity = const [],
    this.boards = const [],
    this.prefs = DashboardPrefs.empty,
  });

  final List<Issue> todayTasks;

  /// Exact count of "today's tasks" (my open issues due today or overdue) — may
  /// exceed [todayTasks] since that list is capped for display.
  final int todayCount;
  final ProjectCompletion completion;
  final List<RankEntry> ranking;
  final List<TrackerDay> tracker;
  final List<TrackerWeek> trackerMonth;
  final DashboardBoard? activeBoard;
  final List<GitEvent> gitActivity;
  final List<DashboardBoardOption> boards;
  final DashboardPrefs prefs;

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    todayTasks: ((json['todayTasks'] as List<dynamic>?) ?? [])
        .map((i) => Issue.fromJson(i as Map<String, dynamic>))
        .toList(),
    todayCount:
        (json['todayCount'] as num?)?.toInt() ??
        ((json['todayTasks'] as List<dynamic>?) ?? const []).length,
    completion: ProjectCompletion.fromJson(
      (json['completion'] as Map<String, dynamic>?) ?? const {},
    ),
    ranking: ((json['ranking'] as List<dynamic>?) ?? [])
        .map((r) => RankEntry.fromJson(r as Map<String, dynamic>))
        .toList(),
    tracker: ((json['tracker'] as List<dynamic>?) ?? [])
        .map((t) => TrackerDay.fromJson(t as Map<String, dynamic>))
        .toList(),
    trackerMonth: ((json['trackerMonth'] as List<dynamic>?) ?? [])
        .map((t) => TrackerWeek.fromJson(t as Map<String, dynamic>))
        .toList(),
    activeBoard: json['activeBoard'] is Map<String, dynamic>
        ? DashboardBoard.fromJson(json['activeBoard'] as Map<String, dynamic>)
        : null,
    gitActivity: ((json['gitActivity'] as List<dynamic>?) ?? [])
        .map((g) => GitEvent.fromJson(g as Map<String, dynamic>))
        .toList(),
    boards: ((json['boards'] as List<dynamic>?) ?? [])
        .map((b) => DashboardBoardOption.fromJson(b as Map<String, dynamic>))
        .toList(),
    prefs: json['prefs'] is Map<String, dynamic>
        ? DashboardPrefs.fromJson(json['prefs'] as Map<String, dynamic>)
        : DashboardPrefs.empty,
  );

  @override
  List<Object?> get props => [
    todayTasks,
    todayCount,
    completion,
    ranking,
    tracker,
    trackerMonth,
    activeBoard,
    gitActivity,
    boards,
    prefs,
  ];
}
