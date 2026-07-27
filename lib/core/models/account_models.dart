import 'package:equatable/equatable.dart';
import '../util/dates.dart';

/// How an account was provisioned. SSO origins make email + password
/// read-only ("managed by your identity provider").
enum AuthOrigin {
  local,
  oidc,
  saml,
  ldap;

  static AuthOrigin fromWire(String? value) => switch (value?.toUpperCase()) {
    'OIDC' => AuthOrigin.oidc,
    'SAML' => AuthOrigin.saml,
    'LDAP' => AuthOrigin.ldap,
    _ => AuthOrigin.local,
  };

  bool get isSso => this != AuthOrigin.local;

  String get label => switch (this) {
    AuthOrigin.local => 'Local account',
    AuthOrigin.oidc => 'OpenID Connect',
    AuthOrigin.saml => 'SAML',
    AuthOrigin.ldap => 'LDAP',
  };
}

/// The signed-in user as seen by the self-service `/me` surface.
class Me extends Equatable {
  const Me({
    required this.id,
    required this.displayName,
    required this.username,
    required this.email,
    required this.emailVerified,
    required this.origin,
    required this.roles,
    required this.active,
    required this.twoFactor,
    required this.notificationPreferences,
    this.pendingEmail,
    this.title,
    this.locale = 'en',
    this.avatarUrl,
    this.createdAt,
    this.passwordChangedAt,
  });

  final String id;
  final String displayName;
  final String username;
  final String email;
  final bool emailVerified;
  final String? pendingEmail;
  final String? title;
  final String locale;
  final String? avatarUrl;
  final AuthOrigin origin;
  final List<String> roles;
  final bool active;
  final DateTime? createdAt;
  final DateTime? passwordChangedAt;
  final TwoFactor twoFactor;
  final NotifPrefs notificationPreferences;

  Me copyWith({
    String? displayName,
    String? title,
    String? avatarUrl,
    bool clearAvatar = false,
  }) => Me(
    id: id,
    displayName: displayName ?? this.displayName,
    username: username,
    email: email,
    emailVerified: emailVerified,
    pendingEmail: pendingEmail,
    title: title ?? this.title,
    locale: locale,
    avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
    origin: origin,
    roles: roles,
    active: active,
    createdAt: createdAt,
    passwordChangedAt: passwordChangedAt,
    twoFactor: twoFactor,
    notificationPreferences: notificationPreferences,
  );

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      final first = parts.first;
      return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory Me.fromJson(Map<String, dynamic> json) => Me(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? json['username'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    emailVerified: json['emailVerified'] as bool? ?? true,
    pendingEmail: json['pendingEmail'] as String?,
    title: json['title'] as String?,
    locale: json['locale'] as String? ?? 'en',
    avatarUrl: json['avatarUrl'] as String?,
    origin: AuthOrigin.fromWire(json['origin'] as String?),
    roles: ((json['roles'] as List<dynamic>?) ?? const []).cast<String>(),
    active: json['active'] as bool? ?? true,
    createdAt: _date(json['createdAt']),
    passwordChangedAt: _date(json['passwordChangedAt']),
    twoFactor: TwoFactor.fromJson(
      (json['twoFactor'] as Map<String, dynamic>?) ?? const {},
    ),
    notificationPreferences: NotifPrefs.fromJson(
      (json['notificationPreferences'] as Map<String, dynamic>?) ?? const {},
    ),
  );

  @override
  List<Object?> get props => [
    id,
    displayName,
    email,
    emailVerified,
    pendingEmail,
    title,
    locale,
    twoFactor,
  ];
}

class TwoFactor extends Equatable {
  const TwoFactor({
    required this.enabled,
    this.method = 'TOTP',
    this.recoveryRemaining = 0,
    this.enabledAt,
  });

  final bool enabled;
  final String method;
  final int recoveryRemaining;
  final DateTime? enabledAt;

  factory TwoFactor.fromJson(Map<String, dynamic> json) => TwoFactor(
    enabled: json['enabled'] as bool? ?? false,
    method: json['method'] as String? ?? 'TOTP',
    recoveryRemaining: (json['recoveryRemaining'] as num?)?.toInt() ?? 0,
    enabledAt: _date(json['enabledAt']),
  );

  @override
  List<Object?> get props => [enabled, method, recoveryRemaining];
}

/// A signed-in device. The [current] device cannot be revoked from the list.
class DeviceSession extends Equatable {
  const DeviceSession({
    required this.id,
    required this.current,
    required this.kind,
    this.os,
    this.client,
    this.app,
    this.location,
    this.ipMasked,
    this.lastActive,
  });

  final String id;
  final bool current;
  final String kind; // desktop | phone | tablet
  final String? os;
  final String? client;
  final String? app;
  final String? location;
  final String? ipMasked;
  final DateTime? lastActive;

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
    id: json['id'] as String,
    current: json['current'] as bool? ?? false,
    kind: json['kind'] as String? ?? 'desktop',
    os: json['os'] as String?,
    client: json['client'] as String?,
    app: json['app'] as String?,
    location: json['location'] as String?,
    ipMasked: json['ipMasked'] as String?,
    lastActive: _date(json['lastActive']),
  );

  @override
  List<Object?> get props => [id, current, kind, lastActive];
}

/// Per-event delivery toggles for one notification channel pair.
class ChannelPair extends Equatable {
  const ChannelPair({required this.email, required this.push});

  final bool email;
  final bool push;

  ChannelPair copyWith({bool? email, bool? push}) =>
      ChannelPair(email: email ?? this.email, push: push ?? this.push);

  factory ChannelPair.fromJson(Map<String, dynamic> json) => ChannelPair(
    email: json['email'] as bool? ?? false,
    push: json['push'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'email': email, 'push': push};

  @override
  List<Object?> get props => [email, push];
}

/// Notification matrix + two master channel switches.
class NotifPrefs extends Equatable {
  const NotifPrefs({
    required this.emailEnabled,
    required this.pushEnabled,
    required this.events,
  });

  final bool emailEnabled;
  final bool pushEnabled;
  final Map<String, ChannelPair> events;

  NotifPrefs copyWith({
    bool? emailEnabled,
    bool? pushEnabled,
    Map<String, ChannelPair>? events,
  }) => NotifPrefs(
    emailEnabled: emailEnabled ?? this.emailEnabled,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    events: events ?? this.events,
  );

  factory NotifPrefs.fromJson(Map<String, dynamic> json) {
    final raw = (json['events'] as Map<String, dynamic>?) ?? const {};
    return NotifPrefs(
      emailEnabled: json['emailEnabled'] as bool? ?? true,
      pushEnabled: json['pushEnabled'] as bool? ?? true,
      events: raw.map(
        (k, v) => MapEntry(k, ChannelPair.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'emailEnabled': emailEnabled,
    'pushEnabled': pushEnabled,
    'events': events.map((k, v) => MapEntry(k, v.toJson())),
  };

  @override
  List<Object?> get props => [emailEnabled, pushEnabled, events];
}

/// TOTP enrolment payload returned by the setup endpoint.
class TotpSetup extends Equatable {
  const TotpSetup({required this.secret, required this.otpauthUri});

  final String secret;
  final String otpauthUri;

  /// The secret grouped in 4s for manual entry into an authenticator app.
  String get groupedSecret {
    final buffer = StringBuffer();
    for (var i = 0; i < secret.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(secret.substring(i, (i + 4).clamp(0, secret.length)));
    }
    return buffer.toString();
  }

  factory TotpSetup.fromJson(Map<String, dynamic> json) => TotpSetup(
    secret: json['secret'] as String,
    otpauthUri: json['otpauthUri'] as String,
  );

  @override
  List<Object?> get props => [secret, otpauthUri];
}

/// A team membership shown in the read-only Access overview.
class AccessTeam extends Equatable {
  const AccessTeam({
    required this.id,
    required this.key,
    required this.name,
    required this.hue,
    required this.role,
    required this.members,
  });

  final String id;
  final String key;
  final String name;
  final int hue;
  final String role;
  final int members;

  factory AccessTeam.fromJson(Map<String, dynamic> json) => AccessTeam(
    id: json['id'] as String,
    key: json['key'] as String? ?? '',
    name: json['name'] as String? ?? '',
    hue: (json['hue'] as num?)?.toInt() ?? 70,
    role: json['role'] as String? ?? 'Member',
    members: (json['members'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [id, role];
}

/// A project membership shown in the read-only Access overview.
class AccessProject extends Equatable {
  const AccessProject({
    required this.id,
    required this.key,
    required this.name,
    required this.color,
    required this.role,
  });

  final String id;
  final String key;
  final String name;
  final String color; // hex
  final String role;

  factory AccessProject.fromJson(Map<String, dynamic> json) => AccessProject(
    id: json['id'] as String,
    key: json['key'] as String? ?? '',
    name: json['name'] as String? ?? '',
    color: json['color'] as String? ?? '#AEC6F4',
    role: json['role'] as String? ?? 'Viewer',
  );

  @override
  List<Object?> get props => [id, role];
}

DateTime? _date(dynamic value) => parseInstant(value);
