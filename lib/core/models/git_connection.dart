import 'package:equatable/equatable.dart';
import '../util/dates.dart';

/// Per-project Git repository connection, embedded on [Project.git].
///
/// Git integration is strictly per project: each project owns its provider +
/// repository and its own automation rules (expressed against *this* project's
/// workflow-state ids). The provider is stored as a raw id
/// (`github` | `gitlab` | `bitbucket`); the feature layer maps it to
/// provider-adaptive terminology (PR ↔ MR). The provider access token lives
/// server-side (encrypted) and never reaches the client, so it is absent here.
class GitConnection extends Equatable {
  const GitConnection({
    this.id,
    required this.provider,
    required this.owner,
    required this.repo,
    this.defaultBranch = 'main',
    this.connectedBy,
    this.connectedAt,
    this.lastSyncAt,
    this.method = 'oauth',
    this.branchTemplate = '{key}-{summary}',
    this.automation = const GitAutomation(),
  });

  /// Stable per-connection id (multi-repo); null on legacy pre-id connections.
  final String? id;
  final String provider;
  final String owner;
  final String repo;
  final String defaultBranch;
  final String? connectedBy;
  final DateTime? connectedAt;
  final DateTime? lastSyncAt;

  /// How the repo was linked: `oauth` | `token`.
  final String method;

  /// Suggested branch name; `{key}` / `{summary}` are filled in per issue.
  final String branchTemplate;
  final GitAutomation automation;

  bool get isOAuth => method != 'token';

  /// Parses the nested `git` object off a project payload; `null` when the
  /// project has no repository connected.
  static GitConnection? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final provider = json['provider'] as String?;
    if (provider == null || provider.isEmpty) return null;
    return GitConnection(
      id: json['id'] as String?,
      provider: provider,
      owner: json['owner'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      defaultBranch: json['defaultBranch'] as String? ?? 'main',
      connectedBy: json['connectedBy'] as String?,
      connectedAt: _ts(json['connectedAt']),
      lastSyncAt: _ts(json['lastSyncAt']),
      method: json['method'] as String? ?? 'oauth',
      branchTemplate: json['branchTemplate'] as String? ?? '{key}-{summary}',
      automation: GitAutomation.fromJson(
        json['automation'] as Map<String, dynamic>?,
      ),
    );
  }

  GitConnection copyWith({
    String? branchTemplate,
    GitAutomation? automation,
    DateTime? lastSyncAt,
  }) => GitConnection(
    id: id,
    provider: provider,
    owner: owner,
    repo: repo,
    defaultBranch: defaultBranch,
    connectedBy: connectedBy,
    connectedAt: connectedAt,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    method: method,
    branchTemplate: branchTemplate ?? this.branchTemplate,
    automation: automation ?? this.automation,
  );

  @override
  List<Object?> get props => [
    id,
    provider,
    owner,
    repo,
    defaultBranch,
    connectedBy,
    connectedAt,
    lastSyncAt,
    method,
    branchTemplate,
    automation,
  ];
}

/// Repo-event → workflow-transition rules for a project, plus the smart-commits
/// toggle. Rules default to *off*.
class GitAutomation extends Equatable {
  const GitAutomation({
    this.branchCreated = const GitRule(),
    this.commitPushed = const GitRule(),
    this.prOpened = const GitRule(),
    this.prMerged = const GitRule(),
    this.smartCommits = true,
  });

  final GitRule branchCreated;
  final GitRule commitPushed;
  final GitRule prOpened;
  final GitRule prMerged;
  final bool smartCommits;

  factory GitAutomation.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const {};
    return GitAutomation(
      branchCreated: GitRule.fromJson(map['branchCreated']),
      commitPushed: GitRule.fromJson(map['commitPushed']),
      prOpened: GitRule.fromJson(map['prOpened']),
      prMerged: GitRule.fromJson(map['prMerged']),
      smartCommits: map['smartCommits'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'branchCreated': branchCreated.toJson(),
    'commitPushed': commitPushed.toJson(),
    'prOpened': prOpened.toJson(),
    'prMerged': prMerged.toJson(),
    'smartCommits': smartCommits,
  };

  GitAutomation copyWith({
    GitRule? branchCreated,
    GitRule? commitPushed,
    GitRule? prOpened,
    GitRule? prMerged,
    bool? smartCommits,
  }) => GitAutomation(
    branchCreated: branchCreated ?? this.branchCreated,
    commitPushed: commitPushed ?? this.commitPushed,
    prOpened: prOpened ?? this.prOpened,
    prMerged: prMerged ?? this.prMerged,
    smartCommits: smartCommits ?? this.smartCommits,
  );

  @override
  List<Object?> get props => [
    branchCreated,
    commitPushed,
    prOpened,
    prMerged,
    smartCommits,
  ];
}

/// A single automation rule: whether it is enabled and, if so, the target
/// workflow-state **id** (never a name — survives renames/reordering).
class GitRule extends Equatable {
  const GitRule({this.on = false, this.toStateId});

  final bool on;
  final String? toStateId;

  factory GitRule.fromJson(dynamic json) {
    if (json is! Map) return const GitRule();
    return GitRule(
      on: json['on'] as bool? ?? false,
      toStateId: json['toStateId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'on': on, 'toStateId': toStateId};

  GitRule copyWith({bool? on, Object? toStateId = _noChange}) => GitRule(
    on: on ?? this.on,
    toStateId: toStateId == _noChange ? this.toStateId : toStateId as String?,
  );

  @override
  List<Object?> get props => [on, toStateId];
}

const Object _noChange = Object();

DateTime? _ts(dynamic value) => parseInstant(value);
