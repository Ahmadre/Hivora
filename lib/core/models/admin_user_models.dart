import 'package:flutter/foundation.dart';

/// Domain model for the admin **User management** board — the platform-level
/// account (role, auth origin, lifecycle status), distinct from per-team
/// membership. Mirrors the server `AdminUserResponse`/`AdminUserListResponse`.

enum AdminRole {
  user,
  admin;

  String get wire => this == AdminRole.admin ? 'ADMIN' : 'USER';

  static AdminRole fromWire(String? value) =>
      value == 'ADMIN' ? AdminRole.admin : AdminRole.user;
}

enum UserOrigin {
  local,
  oidc,
  saml,
  ldap;

  /// OIDC/SAML/LDAP are governed by an external identity provider.
  bool get isSso => this != UserOrigin.local;

  String get wire => name.toUpperCase();

  static UserOrigin fromWire(String? value) => switch (value) {
    'OIDC' => UserOrigin.oidc,
    'SAML' => UserOrigin.saml,
    'LDAP' => UserOrigin.ldap,
    _ => UserOrigin.local,
  };
}

enum UserStatus {
  active,
  disabled,
  invited,
  pendingApproval;

  String get wire =>
      this == UserStatus.pendingApproval ? 'PENDING' : name.toUpperCase();

  static UserStatus fromWire(String? value) => switch (value) {
    'DISABLED' => UserStatus.disabled,
    'INVITED' => UserStatus.invited,
    'PENDING' => UserStatus.pendingApproval,
    _ => UserStatus.active,
  };
}

enum UserSortKey { name, role, origin, status, lastActive, joinedAt }

extension UserSortKeyX on UserSortKey {
  String get wire => switch (this) {
    UserSortKey.name => 'name',
    UserSortKey.role => 'role',
    UserSortKey.origin => 'origin',
    UserSortKey.status => 'status',
    UserSortKey.lastActive => 'lastActive',
    UserSortKey.joinedAt => 'joinedAt',
  };
}

@immutable
class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    this.avatarUrl,
    required this.title,
    this.pronouns,
    required this.role,
    required this.origin,
    required this.status,
    required this.twoFA,
    required this.sso,
    required this.sessions,
    this.lastActive,
    this.invitedAt,
    this.invitedBy,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String username;
  final String email;
  final String? avatarUrl;
  final String title;
  final String? pronouns;
  final AdminRole role;
  final UserOrigin origin;
  final UserStatus status;
  final bool twoFA;
  final bool sso;
  final int sessions;
  final DateTime? lastActive;
  final DateTime? invitedAt;
  final String? invitedBy;
  final DateTime? joinedAt;

  /// Invitation links live 7 days; anything older is expired and must be re-sent.
  bool get inviteExpired =>
      status == UserStatus.invited &&
      invitedAt != null &&
      DateTime.now().difference(invitedAt!).inDays > 7;

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    username: (json['username'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    title: (json['title'] as String?) ?? '',
    pronouns: json['pronouns'] as String?,
    role: AdminRole.fromWire(json['role'] as String?),
    origin: UserOrigin.fromWire(json['origin'] as String?),
    status: UserStatus.fromWire(json['status'] as String?),
    twoFA: json['twoFA'] == true,
    sso: json['sso'] == true,
    sessions: (json['sessions'] as num?)?.toInt() ?? 0,
    lastActive: _date(json['lastActive']),
    invitedAt: _date(json['invitedAt']),
    invitedBy: json['invitedBy'] as String?,
    joinedAt: _date(json['joinedAt']),
  );
}

/// Global KPI tallies, independent of the active filters.
@immutable
class AdminUserCounts {
  const AdminUserCounts({
    required this.total,
    required this.admins,
    required this.active,
    required this.invited,
    required this.expiredInvites,
    required this.disabled,
    required this.activeAdmins,
    this.pendingApproval = 0,
  });

  final int total;
  final int admins;
  final int active;
  final int invited;
  final int expiredInvites;
  final int disabled;
  final int activeAdmins;
  final int pendingApproval;

  static int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory AdminUserCounts.fromJson(Map<String, dynamic> json) =>
      AdminUserCounts(
        total: _int(json['total']),
        admins: _int(json['admins']),
        active: _int(json['active']),
        invited: _int(json['invited']),
        expiredInvites: _int(json['expiredInvites']),
        disabled: _int(json['disabled']),
        activeAdmins: _int(json['activeAdmins']),
        pendingApproval: _int(json['pendingApproval']),
      );

  static const empty = AdminUserCounts(
    total: 0,
    admins: 0,
    active: 0,
    invited: 0,
    expiredInvites: 0,
    disabled: 0,
    activeAdmins: 0,
  );
}

/// One page of the directory plus the unpaged [total] and global [counts].
@immutable
class AdminUserPage {
  const AdminUserPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.counts,
  });

  final List<AdminUser> items;
  final int total;
  final int page;
  final int perPage;
  final AdminUserCounts counts;

  factory AdminUserPage.fromJson(Map<String, dynamic> json) => AdminUserPage(
    items: ((json['items'] as List<dynamic>?) ?? [])
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: (json['total'] as num?)?.toInt() ?? 0,
    page: (json['page'] as num?)?.toInt() ?? 1,
    perPage: (json['perPage'] as num?)?.toInt() ?? 25,
    counts: json['counts'] is Map<String, dynamic>
        ? AdminUserCounts.fromJson(json['counts'] as Map<String, dynamic>)
        : AdminUserCounts.empty,
  );

  /// The sole remaining active admin can't be demoted or deleted.
  bool isLastActiveAdmin(AdminUser u) =>
      u.role == AdminRole.admin &&
      u.status == UserStatus.active &&
      counts.activeAdmins <= 1;
}
