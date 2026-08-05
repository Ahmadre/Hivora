import 'package:flutter/foundation.dart';

/// Domain models for the security **Audit log** — a read-only feed of
/// security-relevant events plus the catalogue that drives the per-event
/// capture toggles. Mirrors the server `AuditController` DTOs and the
/// `AuditAction` / `AuditCategory` / `AuditSeverity` enums.

/// Broad grouping of audit actions (mirrors server `AuditCategory`).
enum AuditCategory {
  authentication,
  account,
  administration,
  configuration,
  data,
  integration,
  // Mirrors the server's AuditCategory.MODERATION. Without it every moderation
  // event — a report filed, a queue item reviewed, a user blocked — falls into
  // `unknown` and the audit filter cannot select the one category an operator
  // has a legal reason to review.
  moderation,
  unknown;

  String get wire => this == AuditCategory.unknown ? '' : name.toUpperCase();

  static AuditCategory fromWire(String? value) => switch (value) {
    'AUTHENTICATION' => AuditCategory.authentication,
    'ACCOUNT' => AuditCategory.account,
    'ADMINISTRATION' => AuditCategory.administration,
    'CONFIGURATION' => AuditCategory.configuration,
    'DATA' => AuditCategory.data,
    'INTEGRATION' => AuditCategory.integration,
    'MODERATION' => AuditCategory.moderation,
    _ => AuditCategory.unknown,
  };

  /// i18n key for the human label.
  String get labelKey => 'audit.category.$name';
}

/// Relative importance of an event (mirrors server `AuditSeverity`).
enum AuditSeverity {
  info,
  notice,
  warning,
  unknown;

  String get wire => this == AuditSeverity.unknown ? '' : name.toUpperCase();

  static AuditSeverity fromWire(String? value) => switch (value) {
    'INFO' => AuditSeverity.info,
    'NOTICE' => AuditSeverity.notice,
    'WARNING' => AuditSeverity.warning,
    _ => AuditSeverity.unknown,
  };

  String get labelKey => 'audit.severity.$name';
}

enum AuditOutcome {
  success,
  failure,
  unknown;

  static AuditOutcome fromWire(String? value) => switch (value) {
    'SUCCESS' => AuditOutcome.success,
    'FAILURE' => AuditOutcome.failure,
    _ => AuditOutcome.unknown,
  };
}

/// One persisted audit record.
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.category,
    required this.severity,
    required this.outcome,
    this.actorId,
    this.actorLabel,
    this.targetId,
    this.targetLabel,
    this.ip,
    this.userAgent,
    this.metadata = const {},
  });

  final String id;
  final DateTime timestamp;

  /// Stable event key, e.g. `LOGIN_SUCCESS`. Use [actionLabelKey] for display.
  final String action;
  final AuditCategory category;
  final AuditSeverity severity;
  final AuditOutcome outcome;
  final String? actorId;
  final String? actorLabel;
  final String? targetId;
  final String? targetLabel;
  final String? ip;
  final String? userAgent;
  final Map<String, String> metadata;

  /// i18n key for the action's human label, e.g. `audit.action.LOGIN_SUCCESS`.
  String get actionLabelKey => 'audit.action.$action';

  static AuditEntry fromJson(Map<String, dynamic> json) => AuditEntry(
    id: json['id'] as String,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    action: json['action'] as String? ?? 'UNKNOWN',
    category: AuditCategory.fromWire(json['category'] as String?),
    severity: AuditSeverity.fromWire(json['severity'] as String?),
    outcome: AuditOutcome.fromWire(json['outcome'] as String?),
    actorId: json['actorId'] as String?,
    actorLabel: json['actorLabel'] as String?,
    targetId: json['targetId'] as String?,
    targetLabel: json['targetLabel'] as String?,
    ip: json['ip'] as String?,
    userAgent: json['userAgent'] as String?,
    metadata:
        (json['metadata'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, '$v'),
        ) ??
        const {},
  );
}

/// One page of audit records plus the total count for pagination.
@immutable
class AuditPage {
  const AuditPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<AuditEntry> items;
  final int total;
  final int page;
  final int perPage;

  int get pageCount => total == 0 ? 1 : ((total + perPage - 1) ~/ perPage);

  static AuditPage fromJson(Map<String, dynamic> json) => AuditPage(
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: (json['total'] as num?)?.toInt() ?? 0,
    page: (json['page'] as num?)?.toInt() ?? 1,
    perPage: (json['perPage'] as num?)?.toInt() ?? 30,
  );
}

/// A selectable event type from the catalogue, used to render the per-event
/// capture toggles in the admin audit settings.
@immutable
class AuditEventType {
  const AuditEventType({
    required this.action,
    required this.category,
    required this.severity,
    required this.defaultEnabled,
  });

  final String action;
  final AuditCategory category;
  final AuditSeverity severity;
  final bool defaultEnabled;

  String get labelKey => 'audit.action.$action';

  static AuditEventType fromJson(Map<String, dynamic> json) => AuditEventType(
    action: json['action'] as String,
    category: AuditCategory.fromWire(json['category'] as String?),
    severity: AuditSeverity.fromWire(json['severity'] as String?),
    defaultEnabled: json['defaultEnabled'] as bool? ?? true,
  );
}
