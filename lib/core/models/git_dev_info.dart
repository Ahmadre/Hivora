/// Git integration models — the provider-adaptive [GitProvider] and the
/// per-issue [DevInfo] (branches / commits / pull-or-merge requests / builds).
///
/// Pure Dart (no Flutter): colors/icons for these live in `git_tokens.dart`.
/// The connection itself ([GitConnection]) lives on `Project.git`
/// (see `core/models/git_connection.dart`).
library;

import '../util/dates.dart';

/// A supported Git provider. Terminology is **provider-adaptive**: GitHub &
/// Bitbucket say "Pull request / PR"; GitLab says "Merge request / MR". Every
/// label in the UI derives from the connected provider via these getters.
enum GitProvider {
  github,
  gitlab,
  bitbucket;

  String get id => name;

  String get label => switch (this) {
    GitProvider.github => 'GitHub',
    GitProvider.gitlab => 'GitLab',
    GitProvider.bitbucket => 'Bitbucket',
  };

  String get host => switch (this) {
    GitProvider.github => 'github.com',
    GitProvider.gitlab => 'gitlab.com',
    GitProvider.bitbucket => 'bitbucket.org',
  };

  /// "Pull request" for GitHub/Bitbucket, "Merge request" for GitLab.
  String get prTerm =>
      this == GitProvider.gitlab ? 'Merge request' : 'Pull request';

  String get prTermPlural =>
      this == GitProvider.gitlab ? 'Merge requests' : 'Pull requests';

  /// "PR" for GitHub/Bitbucket, "MR" for GitLab.
  String get prShort => this == GitProvider.gitlab ? 'MR' : 'PR';

  /// What the account owner is called: organization / group / workspace.
  String get ownerWord => switch (this) {
    GitProvider.github => 'organization',
    GitProvider.gitlab => 'group',
    GitProvider.bitbucket => 'workspace',
  };

  /// What a repository is called: "repository" or (GitLab) "project".
  String get unit => this == GitProvider.gitlab ? 'project' : 'repository';

  /// Two-letter monogram used by the brand glyph when there is no octocat.
  String get mono => switch (this) {
    GitProvider.github => 'GH',
    GitProvider.gitlab => 'GL',
    GitProvider.bitbucket => 'BB',
  };
}

/// Resolves a raw provider id (as stored on [GitConnection.provider]).
GitProvider? gitProviderFrom(String? id) => switch (id) {
  'github' => GitProvider.github,
  'gitlab' => GitProvider.gitlab,
  'bitbucket' => GitProvider.bitbucket,
  _ => null,
};

/// Browser URL for a branch on [provider], scoped to the `owner/repo` [slug].
/// Returns null when the slug or branch is missing. Slashes in the branch name
/// stay as path segments (providers resolve `feat/x` correctly).
String? gitBranchUrl(GitProvider provider, String slug, String branch) {
  if (slug.isEmpty || branch.isEmpty) return null;
  final host = provider.host;
  return switch (provider) {
    GitProvider.gitlab => 'https://$host/$slug/-/tree/$branch',
    GitProvider.bitbucket => 'https://$host/$slug/branch/$branch',
    GitProvider.github => 'https://$host/$slug/tree/$branch',
  };
}

/// Browser URL for a single commit by [sha] on [provider]/[slug].
String? gitCommitUrl(GitProvider provider, String slug, String sha) {
  if (slug.isEmpty || sha.isEmpty) return null;
  final host = provider.host;
  return switch (provider) {
    GitProvider.gitlab => 'https://$host/$slug/-/commit/$sha',
    GitProvider.bitbucket => 'https://$host/$slug/commits/$sha',
    GitProvider.github => 'https://$host/$slug/commit/$sha',
  };
}

/// Browser URL for a pull/merge request [number] on [provider]/[slug].
String? gitPrUrl(GitProvider provider, String slug, int number) {
  if (slug.isEmpty || number <= 0) return null;
  final host = provider.host;
  return switch (provider) {
    GitProvider.gitlab => 'https://$host/$slug/-/merge_requests/$number',
    GitProvider.bitbucket => 'https://$host/$slug/pull-requests/$number',
    GitProvider.github => 'https://$host/$slug/pull/$number',
  };
}

/// PR/MR lifecycle state.
enum PrState {
  open,
  draft,
  merged,
  closed;

  static PrState fromJson(String? raw) => switch (raw) {
    'DRAFT' => PrState.draft,
    'MERGED' => PrState.merged,
    'CLOSED' => PrState.closed,
    _ => PrState.open,
  };

  String get wire => switch (this) {
    PrState.open => 'OPEN',
    PrState.draft => 'DRAFT',
    PrState.merged => 'MERGED',
    PrState.closed => 'CLOSED',
  };

  String get label => switch (this) {
    PrState.open => 'Open',
    PrState.draft => 'Draft',
    PrState.merged => 'Merged',
    PrState.closed => 'Closed',
  };
}

/// Checks / build roll-up state.
enum CheckState {
  passing,
  failing,
  pending,
  running;

  static CheckState fromJson(String? raw) => switch (raw) {
    'failing' => CheckState.failing,
    'pending' => CheckState.pending,
    'running' => CheckState.running,
    _ => CheckState.passing,
  };

  String get label => switch (this) {
    CheckState.passing => 'Passing',
    CheckState.failing => 'Failing',
    CheckState.pending => 'Pending',
    CheckState.running => 'Running',
  };
}

/// The auto-linked development information for a single issue.
class DevInfo {
  const DevInfo({
    required this.connected,
    this.provider,
    this.owner,
    this.repo,
    this.branches = const [],
    this.commits = const [],
    this.prs = const [],
    this.builds = const [],
  });

  /// Whether the issue's project has a repository connected at all.
  final bool connected;
  final String? provider;
  final String? owner;
  final String? repo;
  final List<GitBranch> branches;
  final List<GitCommit> commits;
  final List<GitPullRequest> prs;
  final List<GitBuild> builds;

  bool get hasAny =>
      branches.isNotEmpty ||
      commits.isNotEmpty ||
      prs.isNotEmpty ||
      builds.isNotEmpty;

  factory DevInfo.fromJson(Map<String, dynamic> json) => DevInfo(
    connected: json['connected'] as bool? ?? false,
    provider: json['provider'] as String?,
    owner: json['owner'] as String?,
    repo: json['repo'] as String?,
    branches: _list(json['branches'], GitBranch.fromJson),
    commits: _list(json['commits'], GitCommit.fromJson),
    prs: _list(json['prs'], GitPullRequest.fromJson),
    builds: _list(json['builds'], GitBuild.fromJson),
  );

  /// Returns a copy with [pr] swapped in by number — for optimistic PR updates.
  DevInfo withPr(GitPullRequest pr) => DevInfo(
    connected: connected,
    provider: provider,
    owner: owner,
    repo: repo,
    branches: branches,
    commits: commits,
    prs: [for (final p in prs) p.number == pr.number ? pr : p],
    builds: builds,
  );
}

class GitBranch {
  const GitBranch({
    required this.name,
    required this.base,
    required this.ahead,
    required this.behind,
    this.updatedAt,
    this.authorId,
    this.provider,
    this.repo,
  });

  final String name;
  final String base;
  final int ahead;
  final int behind;
  final DateTime? updatedAt;
  final String? authorId;

  /// Source repo attribution (multi-repo): provider id + `owner/repo`.
  final String? provider;
  final String? repo;

  factory GitBranch.fromJson(Map<String, dynamic> json) => GitBranch(
    name: json['name'] as String? ?? '',
    base: json['base'] as String? ?? 'main',
    ahead: json['ahead'] as int? ?? 0,
    behind: json['behind'] as int? ?? 0,
    updatedAt: _ts(json['updatedAt']),
    authorId: json['authorId'] as String?,
    provider: json['provider'] as String?,
    repo: json['repo'] as String?,
  );
}

class GitCommit {
  const GitCommit({
    required this.sha,
    required this.message,
    this.authorId,
    this.at,
    this.additions = 0,
    this.deletions = 0,
    this.verified = false,
    this.provider,
    this.repo,
  });

  final String sha;
  final String message;
  final String? authorId;
  final DateTime? at;
  final int additions;
  final int deletions;
  final bool verified;
  final String? provider;
  final String? repo;

  factory GitCommit.fromJson(Map<String, dynamic> json) => GitCommit(
    sha: json['sha'] as String? ?? '',
    message: json['message'] as String? ?? '',
    authorId: json['authorId'] as String?,
    at: _ts(json['at']),
    additions: json['additions'] as int? ?? 0,
    deletions: json['deletions'] as int? ?? 0,
    verified: json['verified'] as bool? ?? false,
    provider: json['provider'] as String?,
    repo: json['repo'] as String?,
  );
}

class GitPullRequest {
  const GitPullRequest({
    required this.number,
    required this.title,
    required this.state,
    this.authorId,
    this.reviewerIds = const [],
    this.approvals = 0,
    this.changesRequested = 0,
    this.comments = 0,
    this.sourceBranch,
    this.targetBranch,
    this.at,
    this.checks = CheckState.passing,
    this.provider,
    this.repo,
  });

  final int number;
  final String title;
  final PrState state;
  final String? authorId;
  final List<String> reviewerIds;
  final int approvals;
  final int changesRequested;
  final int comments;
  final String? sourceBranch;
  final String? targetBranch;
  final DateTime? at;
  final CheckState checks;
  final String? provider;
  final String? repo;

  factory GitPullRequest.fromJson(Map<String, dynamic> json) => GitPullRequest(
    number: json['number'] as int? ?? 0,
    title: json['title'] as String? ?? '',
    state: PrState.fromJson(json['state'] as String?),
    authorId: json['authorId'] as String?,
    reviewerIds: ((json['reviewerIds'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    approvals: json['approvals'] as int? ?? 0,
    changesRequested: json['changesRequested'] as int? ?? 0,
    comments: json['comments'] as int? ?? 0,
    sourceBranch: json['sourceBranch'] as String?,
    targetBranch: json['targetBranch'] as String?,
    at: _ts(json['at']),
    checks: CheckState.fromJson(json['checks'] as String?),
    provider: json['provider'] as String?,
    repo: json['repo'] as String?,
  );

  GitPullRequest copyWith({PrState? state}) => GitPullRequest(
    number: number,
    title: title,
    state: state ?? this.state,
    authorId: authorId,
    reviewerIds: reviewerIds,
    approvals: approvals,
    changesRequested: changesRequested,
    comments: comments,
    sourceBranch: sourceBranch,
    targetBranch: targetBranch,
    at: at,
    checks: checks,
    provider: provider,
    repo: repo,
  );
}

class GitBuild {
  const GitBuild({
    required this.name,
    required this.workflow,
    required this.branch,
    required this.status,
    this.duration,
    this.at,
    this.provider,
    this.repo,
  });

  final String name;
  final String workflow;
  final String branch;
  final CheckState status;
  final String? duration;
  final DateTime? at;
  final String? provider;
  final String? repo;

  factory GitBuild.fromJson(Map<String, dynamic> json) => GitBuild(
    name: json['name'] as String? ?? '',
    workflow: json['workflow'] as String? ?? '',
    branch: json['branch'] as String? ?? '',
    status: CheckState.fromJson(json['status'] as String?),
    duration: json['duration'] as String?,
    at: _ts(json['at']),
    provider: json['provider'] as String?,
    repo: json['repo'] as String?,
  );
}

/// An org / group / workspace surfaced during the connect wizard.
class GitOwner {
  const GitOwner({
    required this.id,
    required this.name,
    required this.kind,
    this.repos = 0,
  });

  final String id;
  final String name;
  final String kind;
  final int repos;

  factory GitOwner.fromJson(Map<String, dynamic> json) => GitOwner(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    repos: json['repos'] as int? ?? 0,
  );
}

/// A repository surfaced during the connect wizard.
class GitRepo {
  const GitRepo({
    required this.name,
    this.isPrivate = true,
    this.lang,
    this.langColor,
    this.updated,
  });

  final String name;
  final bool isPrivate;
  final String? lang;
  final String? langColor;
  final String? updated;

  factory GitRepo.fromJson(Map<String, dynamic> json) => GitRepo(
    name: json['name'] as String? ?? '',
    isPrivate: json['priv'] as bool? ?? true,
    lang: json['lang'] as String?,
    langColor: json['langColor'] as String?,
    updated: json['updated'] as String?,
  );
}

/// Result of kicking off the real OAuth flow.
class GitOAuthStart {
  const GitOAuthStart({this.authorizeUrl, required this.available, this.state});

  /// Provider consent URL to open in the browser (null when unavailable).
  final String? authorizeUrl;

  /// Whether the admin has configured a provider app (real OAuth possible). When
  /// false the client falls back to the URL + access-token method.
  final bool available;

  /// The OAuth `state` used to poll the server-side session for completion.
  final String? state;

  factory GitOAuthStart.fromJson(Map<String, dynamic> json) => GitOAuthStart(
    authorizeUrl: json['authorizeUrl'] as String?,
    available: json['available'] as bool? ?? false,
    state: json['state'] as String?,
  );
}

/// Status of an in-flight OAuth session, polled after opening the consent page.
class GitOAuthSessionStatus {
  const GitOAuthSessionStatus({
    required this.status,
    this.provider,
    this.error,
  });

  final String status; // PENDING · AUTHORIZED · ERROR
  final String? provider;
  final String? error;

  bool get authorized => status == 'AUTHORIZED';
  bool get failed => status == 'ERROR';

  factory GitOAuthSessionStatus.fromJson(Map<String, dynamic> json) =>
      GitOAuthSessionStatus(
        status: json['status'] as String? ?? 'PENDING',
        provider: json['provider'] as String?,
        error: json['error'] as String?,
      );
}

/// Short relative label, e.g. `2h`, `3d`, `just now`.
String agoShort(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
  if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
  return '${(d.inDays / 365).floor()}y';
}

/// Relative label with an "ago" suffix, e.g. `2h ago` (or just `just now`).
String agoSuffixed(DateTime? at) {
  final s = agoShort(at);
  return (s.isEmpty || s == 'just now') ? s : '$s ago';
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) build) =>
    ((value as List<dynamic>?) ?? const [])
        .map((e) => build(e as Map<String, dynamic>))
        .toList();

DateTime? _ts(dynamic value) => parseInstant(value);
