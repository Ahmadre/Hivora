import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'work_models.dart';

/// The caller's Weekly Summary: the team's work over the past week
/// ([WeeklyTeam]) and the caller's own upcoming to-dos ([WeeklyUpcoming]).
/// Mirrors the server `WeeklySummaryService.WeeklySummary` record and powers both
/// the in-app page and the Monday digest e-mail.
class WeeklySummary extends Equatable {
  const WeeklySummary({
    required this.weekStart,
    required this.weekEnd,
    required this.team,
    required this.upcoming,
  });

  final DateTime? weekStart;
  final DateTime? weekEnd;
  final WeeklyTeam team;
  final WeeklyUpcoming upcoming;

  factory WeeklySummary.fromJson(Map<String, dynamic> json) => WeeklySummary(
    weekStart: parseDate(json['weekStart']),
    weekEnd: parseDate(json['weekEnd']),
    team: WeeklyTeam.fromJson(
      (json['team'] as Map<String, dynamic>?) ?? const {},
    ),
    upcoming: WeeklyUpcoming.fromJson(
      (json['upcoming'] as Map<String, dynamic>?) ?? const {},
    ),
  );

  @override
  List<Object?> get props => [weekStart, weekEnd, team, upcoming];
}

/// The week behind: aggregate team activity plus the caller's personal share.
class WeeklyTeam extends Equatable {
  const WeeklyTeam({
    this.completed = 0,
    this.created = 0,
    this.myCompleted = 0,
    this.focusMinutes = 0,
    this.contributors = const [],
    this.highlights = const [],
    this.sprint,
  });

  final int completed;
  final int created;
  final int myCompleted;
  final int focusMinutes;
  final List<WeeklyContributor> contributors;
  final List<Issue> highlights;
  final WeeklySprint? sprint;

  factory WeeklyTeam.fromJson(Map<String, dynamic> json) => WeeklyTeam(
    completed: (json['completed'] as num?)?.toInt() ?? 0,
    created: (json['created'] as num?)?.toInt() ?? 0,
    myCompleted: (json['myCompleted'] as num?)?.toInt() ?? 0,
    focusMinutes: (json['focusMinutes'] as num?)?.toInt() ?? 0,
    contributors: ((json['contributors'] as List<dynamic>?) ?? const [])
        .map((c) => WeeklyContributor.fromJson(c as Map<String, dynamic>))
        .toList(),
    highlights: ((json['highlights'] as List<dynamic>?) ?? const [])
        .map((i) => Issue.fromJson(i as Map<String, dynamic>))
        .toList(),
    sprint: json['sprint'] is Map<String, dynamic>
        ? WeeklySprint.fromJson(json['sprint'] as Map<String, dynamic>)
        : null,
  );

  @override
  List<Object?> get props => [
    completed,
    created,
    myCompleted,
    focusMinutes,
    contributors,
    highlights,
    sprint,
  ];
}

/// A teammate and how many issues they resolved in the window (leaderboard row).
class WeeklyContributor extends Equatable {
  const WeeklyContributor({
    required this.userId,
    required this.displayName,
    required this.completed,
    this.title,
    this.avatarUrl,
    this.pronouns,
  });

  final String userId;
  final String displayName;
  final int completed;
  final String? title;
  final String? avatarUrl;
  final String? pronouns;

  factory WeeklyContributor.fromJson(Map<String, dynamic> json) =>
      WeeklyContributor(
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        title: json['title'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        pronouns: json['pronouns'] as String?,
      );

  @override
  List<Object?> get props => [userId, completed];
}

/// Snapshot of the caller's active sprint (if any) for the summary hero.
class WeeklySprint extends Equatable {
  const WeeklySprint({
    required this.boardId,
    required this.name,
    this.goal,
    this.day = 0,
    this.days = 0,
    this.issuesDone = 0,
    this.issuesTotal = 0,
    this.points = 0,
    this.pointsTotal = 0,
  });

  final String boardId;
  final String name;
  final String? goal;
  final int day;
  final int days;
  final int issuesDone;
  final int issuesTotal;
  final int points;
  final int pointsTotal;

  /// Ring progress: story points when estimated, else issue completion.
  double get progressPercent {
    final ratio = pointsTotal > 0
        ? points / pointsTotal
        : (issuesTotal == 0 ? 0.0 : issuesDone / issuesTotal);
    return ratio.clamp(0.0, 1.0);
  }

  factory WeeklySprint.fromJson(Map<String, dynamic> json) => WeeklySprint(
    boardId: json['boardId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    goal: json['goal'] as String?,
    day: (json['day'] as num?)?.toInt() ?? 0,
    days: (json['days'] as num?)?.toInt() ?? 0,
    issuesDone: (json['issuesDone'] as num?)?.toInt() ?? 0,
    issuesTotal: (json['issuesTotal'] as num?)?.toInt() ?? 0,
    points: (json['points'] as num?)?.toInt() ?? 0,
    pointsTotal: (json['pointsTotal'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [
    boardId,
    name,
    day,
    days,
    issuesDone,
    issuesTotal,
    points,
    pointsTotal,
  ];
}

/// The week ahead: the caller's open assigned work, overdue called out.
class WeeklyUpcoming extends Equatable {
  const WeeklyUpcoming({
    this.total = 0,
    this.overdue = 0,
    this.items = const [],
  });

  final int total;
  final int overdue;
  final List<Issue> items;

  factory WeeklyUpcoming.fromJson(Map<String, dynamic> json) => WeeklyUpcoming(
    total: (json['total'] as num?)?.toInt() ?? 0,
    overdue: (json['overdue'] as num?)?.toInt() ?? 0,
    items: ((json['items'] as List<dynamic>?) ?? const [])
        .map((i) => Issue.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [total, overdue, items];
}
