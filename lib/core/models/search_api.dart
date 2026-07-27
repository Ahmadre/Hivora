/// DTOs for the `/api/v1/search` response (mirrors the server's `SearchHit` /
/// `SearchResponse`). Kept raw — the controller maps these onto [SearchEntry]
/// and composes/localises the display strings client-side.
library;

import '../util/dates.dart';

class SearchApiHit {
  SearchApiHit({
    required this.category,
    required this.id,
    required this.route,
    required this.title,
    this.subtitle,
    this.readableId,
    this.type,
    this.state,
    this.assigneeName,
    this.assigneeAvatarUrl,
    this.avatarUrl,
    this.projectKey,
    this.projectColor,
    this.openCount,
    this.doneCount,
    this.memberNames = const [],
    this.space,
    this.updatedAt,
    this.archived = false,
  });

  final String category;
  final String id;
  final String route;
  final String title;
  final String? subtitle;
  final String? readableId;
  final String? type;
  final String? state;
  final String? assigneeName;
  final String? assigneeAvatarUrl;
  final String? avatarUrl;
  final String? projectKey;
  final String? projectColor;
  final int? openCount;
  final int? doneCount;
  final List<String> memberNames;
  final String? space;
  final DateTime? updatedAt;

  /// Archived (soft-deleted) issue or archived project — badged in the UI.
  final bool archived;

  factory SearchApiHit.fromJson(Map<String, dynamic> json) => SearchApiHit(
    category: json['category'] as String? ?? '',
    id: json['id'] as String? ?? '',
    route: json['route'] as String? ?? '/',
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String?,
    readableId: json['readableId'] as String?,
    type: json['type'] as String?,
    state: json['state'] as String?,
    assigneeName: json['assigneeName'] as String?,
    assigneeAvatarUrl: json['assigneeAvatarUrl'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    projectKey: json['projectKey'] as String?,
    projectColor: json['projectColor'] as String?,
    openCount: json['openCount'] as int?,
    doneCount: json['doneCount'] as int?,
    memberNames: ((json['memberNames'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    space: json['space'] as String?,
    updatedAt: parseInstant(json['updatedAt']),
    archived: json['archived'] as bool? ?? false,
  );
}

class SearchApiGroup {
  SearchApiGroup({required this.category, required this.items});
  final String category;
  final List<SearchApiHit> items;

  factory SearchApiGroup.fromJson(Map<String, dynamic> json) => SearchApiGroup(
    category: json['category'] as String? ?? '',
    items: ((json['items'] as List<dynamic>?) ?? const [])
        .map((e) => SearchApiHit.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class SearchApiResponse {
  SearchApiResponse({required this.groups, required this.counts});
  final List<SearchApiGroup> groups;

  /// Total entity count per category (UPPERCASE keys), for the chip badges.
  final Map<String, int> counts;

  factory SearchApiResponse.fromJson(Map<String, dynamic> json) =>
      SearchApiResponse(
        groups: ((json['groups'] as List<dynamic>?) ?? const [])
            .map((e) => SearchApiGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        counts: ((json['counts'] as Map<String, dynamic>?) ?? const {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      );
}
