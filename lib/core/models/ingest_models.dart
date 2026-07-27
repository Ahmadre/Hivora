import 'package:equatable/equatable.dart';

/// One managed e-mail-to-ticket connection: an IMAP mailbox/folder whose
/// unseen messages become issues in the linked project.
class IngestConnection extends Equatable {
  const IngestConnection({
    this.id,
    this.name,
    this.enabled = false,
    this.host = '',
    this.port = 993,
    this.ssl = true,
    this.username = '',
    this.password,
    this.folder = 'INBOX',
    this.projectId,
    this.pollSeconds = 60,
    this.passwordSet = false,
  });

  factory IngestConnection.fromJson(Map<String, dynamic> json) =>
      IngestConnection(
        id: json['id'] as String?,
        name: json['name'] as String?,
        enabled: json['enabled'] == true,
        host: (json['host'] as String?) ?? '',
        port: (json['port'] as num?)?.toInt() ?? 993,
        ssl: json['ssl'] != false,
        username: (json['username'] as String?) ?? '',
        folder: (json['folder'] as String?) ?? 'INBOX',
        projectId: json['projectId'] as String?,
        pollSeconds: (json['pollSeconds'] as num?)?.toInt() ?? 60,
        passwordSet: json['passwordSet'] == true,
      );

  final String? id;
  final String? name;
  final bool enabled;
  final String host;
  final int port;
  final bool ssl;
  final String username;

  /// Write-only: sent when (re)setting; the server never echoes it back.
  final String? password;
  final String folder;
  final String? projectId;
  final int pollSeconds;

  /// Read-only server flag: whether a password is stored for this connection.
  final bool passwordSet;

  Map<String, dynamic> toJson() => {
    'name': ?name,
    'enabled': enabled,
    'host': host,
    'port': port,
    'ssl': ssl,
    'username': username,
    if (password != null && password!.isNotEmpty) 'password': password,
    'folder': folder,
    'projectId': ?projectId,
    'pollSeconds': pollSeconds,
  };

  IngestConnection copyWith({
    String? id,
    String? name,
    bool? enabled,
    String? host,
    int? port,
    bool? ssl,
    String? username,
    String? password,
    String? folder,
    String? projectId,
    int? pollSeconds,
    bool? passwordSet,
  }) => IngestConnection(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    host: host ?? this.host,
    port: port ?? this.port,
    ssl: ssl ?? this.ssl,
    username: username ?? this.username,
    password: password ?? this.password,
    folder: folder ?? this.folder,
    projectId: projectId ?? this.projectId,
    pollSeconds: pollSeconds ?? this.pollSeconds,
    passwordSet: passwordSet ?? this.passwordSet,
  );

  /// Display label: explicit name, else mailbox identity.
  String get label => (name != null && name!.trim().isNotEmpty)
      ? name!.trim()
      : (username.isNotEmpty ? username : host);

  @override
  List<Object?> get props => [
    id,
    name,
    enabled,
    host,
    port,
    ssl,
    username,
    password,
    folder,
    projectId,
    pollSeconds,
    passwordSet,
  ];
}

/// Lightweight project option for the connection editor's project picker.
class IngestProjectOption extends Equatable {
  const IngestProjectOption({
    required this.id,
    required this.key,
    required this.name,
    required this.color,
  });

  factory IngestProjectOption.fromJson(Map<String, dynamic> json) =>
      IngestProjectOption(
        id: json['id'] as String,
        key: (json['key'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        color: (json['color'] as String?) ?? '#AEC6F4',
      );

  final String id;
  final String key;
  final String name;
  final String color;

  @override
  List<Object?> get props => [id, key, name, color];
}
