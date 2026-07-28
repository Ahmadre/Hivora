import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Domain models for the Confluence-style Knowledge Base.
///
/// The feature is a faithful port of the standalone design reference
/// (`Design/Hivora-Knowledge-Package`). It carries its own self-contained
/// dataset (spaces, an article tree, and the issues / people that the smart-link
/// tokens resolve against) so the seeded articles render exactly as the
/// reference shows — no backend round-trip required. Edits persist locally.

/// A teammate referenced by a `{{user:…}}` chip, byline or assignee.
class KbUser {
  const KbUser({
    required this.id,
    required this.name,
    required this.title,
    required this.hue,
  });

  final String id;
  final String name;
  final String title;
  final int hue;

  String get firstName => name.split(' ').first;
}

/// A wiki space (Engineering · Product · Design · Operations).
class KbSpace {
  const KbSpace({
    required this.id,
    required this.key,
    required this.name,
    required this.hue,
    required this.icon,
    required this.desc,
  });

  final String id;
  final String key;
  final String name;
  final int hue;
  final String icon;
  final String desc;
}

/// A knowledge article. [body] is markdown that may embed `{{…}}` smart-link
/// tokens; the issue⇄article relationship is *derived* from those tokens, never
/// stored separately.
class KbArticle {
  const KbArticle({
    required this.id,
    required this.spaceId,
    required this.parentId,
    required this.title,
    required this.icon,
    required this.authorId,
    required this.contributorIds,
    required this.updated,
    required this.created,
    required this.reads,
    required this.labels,
    required this.status,
    required this.body,
    this.doc,
  });

  final String id;
  final String spaceId;
  final String? parentId;
  final String title;
  final String icon;
  final String authorId;
  final List<String> contributorIds;
  final String updated;
  final String created;
  final int reads;
  final List<String> labels;
  final String status; // published | draft
  /// Plain text of [doc]. Excerpts and the search preview read this.
  final String body;

  /// The Lexical document — what the reader renders and the editor opens.
  final String? doc;

  KbArticle copyWith({
    String? spaceId,
    String? title,
    String? body,
    String? doc,
    String? updated,
  }) => KbArticle(
    id: id,
    spaceId: spaceId ?? this.spaceId,
    parentId: parentId,
    title: title ?? this.title,
    icon: icon,
    authorId: authorId,
    contributorIds: contributorIds,
    updated: updated ?? this.updated,
    created: created,
    reads: reads,
    labels: labels,
    status: status,
    body: body ?? this.body,
    doc: doc ?? this.doc,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceId': spaceId,
    'parentId': parentId,
    'title': title,
    'icon': icon,
    'authorId': authorId,
    'contributorIds': contributorIds,
    'updated': updated,
    'created': created,
    'reads': reads,
    'labels': labels,
    'status': status,
    'body': body,
    'doc': doc,
  };

  factory KbArticle.fromJson(Map<String, dynamic> json) => KbArticle(
    id: json['id'] as String,
    spaceId: json['spaceId'] as String,
    parentId: json['parentId'] as String?,
    title: json['title'] as String? ?? '',
    icon: json['icon'] as String? ?? 'file-text',
    authorId: json['authorId'] as String? ?? '',
    contributorIds: ((json['contributorIds'] as List?) ?? const [])
        .cast<String>(),
    updated: json['updated'] as String? ?? 'just now',
    created: json['created'] as String? ?? 'Today',
    reads: (json['reads'] as num?)?.toInt() ?? 0,
    labels: ((json['labels'] as List?) ?? const []).cast<String>(),
    status: json['status'] as String? ?? 'published',
    body: json['body'] as String? ?? '',
    doc: json['doc'] as String?,
  );
}

// ─────────────────────────── metadata maps ───────────────────────────

/// Issue-type glyph + hue. Mirrors `TYPE_META` in the reference `data.js`.
class TypeMeta {
  const TypeMeta(this.label, this.icon, this.hue);
  final String label;
  final String icon;
  final int hue;
}

const Map<String, TypeMeta> kTypeMeta = {
  'STORY': TypeMeta('Story', 'bookmark', 155),
  'TASK': TypeMeta('Task', 'circle-check', 250),
  'BUG': TypeMeta('Bug', 'bug', 20),
  'EPIC': TypeMeta('Epic', 'zap', 300),
};

TypeMeta typeMeta(String type) => kTypeMeta[type] ?? kTypeMeta['TASK']!;

/// Priority glyph + hue. Mirrors `PRIORITY_META`.
class PriorityMeta {
  const PriorityMeta(this.label, this.icon, this.hue);
  final String label;
  final String icon;
  final int hue;
}

const Map<String, PriorityMeta> kPriorityMeta = {
  'URGENT': PriorityMeta('Urgent', 'chevrons-up', 20),
  'HIGH': PriorityMeta('High', 'chevron-up', 45),
  'NORMAL': PriorityMeta('Normal', 'equal', 250),
  'LOW': PriorityMeta('Low', 'chevron-down', 255),
};

PriorityMeta priorityMeta(String priority) =>
    kPriorityMeta[priority] ?? kPriorityMeta['NORMAL']!;

/// Workflow-state display name + hue. Mirrors `WORKFLOW` / `stateMeta`.
class StateMeta {
  const StateMeta(this.name, this.hue);
  final String name;
  final int hue;
}

const Map<String, StateMeta> kStateMeta = {
  'BACKLOG': StateMeta('Backlog', 255),
  'TODO': StateMeta('To Do', 250),
  'IN_PROGRESS': StateMeta('In Progress', 70),
  'IN_REVIEW': StateMeta('In Review', 300),
  'DONE': StateMeta('Done', 155),
};

StateMeta stateMeta(String state) =>
    kStateMeta[state] ?? kStateMeta['BACKLOG']!;

// ─────────────────────────── lucide icon lookup ───────────────────────────

/// Resolves a kebab-case lucide icon name (as used in the reference data &
/// toolbar) to its [IconData]. Frontend convention: only Lucide icons.
IconData lucideIcon(String? name) {
  switch (name) {
    // article / space icons
    case 'image':
      return LucideIcons.image;
    case 'image-off':
      return LucideIcons.imageOff;
    case 'container':
      return LucideIcons.container;
    case 'lock':
      return LucideIcons.lock;
    case 'database-backup':
      return LucideIcons.databaseBackup;
    case 'key-round':
      return LucideIcons.keyRound;
    case 'rocket':
      return LucideIcons.rocket;
    case 'flame':
      return LucideIcons.flame;
    case 'graduation-cap':
      return LucideIcons.graduationCap;
    case 'git-branch':
      return LucideIcons.gitBranch;
    case 'sparkles':
      return LucideIcons.sparkles;
    case 'code-xml':
      return LucideIcons.codeXml;
    case 'compass':
      return LucideIcons.compass;
    case 'palette':
      return LucideIcons.palette;
    case 'server-cog':
      return LucideIcons.serverCog;
    case 'file-question':
      return LucideIcons.fileQuestion;
    // type glyphs
    case 'bookmark':
      return LucideIcons.bookmark;
    case 'circle-check':
      return LucideIcons.circleCheck;
    case 'bug':
      return LucideIcons.bug;
    case 'zap':
      return LucideIcons.zap;
    // priority
    case 'chevrons-up':
      return LucideIcons.chevronsUp;
    case 'chevron-up':
      return LucideIcons.chevronUp;
    case 'equal':
      return LucideIcons.equal;
    case 'chevron-down':
      return LucideIcons.chevronDown;
    // callouts
    case 'info':
      return LucideIcons.info;
    case 'triangle-alert':
      return LucideIcons.triangleAlert;
    case 'pencil':
      return LucideIcons.pencil;
    case 'lightbulb':
      return LucideIcons.lightbulb;
    // ui / toolbar
    case 'search':
      return LucideIcons.search;
    case 'x':
      return LucideIcons.x;
    case 'eye':
      return LucideIcons.eye;
    case 'clock':
      return LucideIcons.clock;
    case 'corner-down-left':
      return LucideIcons.cornerDownLeft;
    case 'link-2':
      return LucideIcons.link2;
    case 'unlink':
      return LucideIcons.unlink;
    case 'hash':
      return LucideIcons.hash;
    case 'at-sign':
      return LucideIcons.atSign;
    case 'heading-1':
      return LucideIcons.heading1;
    case 'heading-2':
      return LucideIcons.heading2;
    case 'heading-3':
      return LucideIcons.heading3;
    case 'bold':
      return LucideIcons.bold;
    case 'italic':
      return LucideIcons.italic;
    case 'strikethrough':
      return LucideIcons.strikethrough;
    case 'code':
      return LucideIcons.code;
    case 'list':
      return LucideIcons.list;
    case 'list-ordered':
      return LucideIcons.listOrdered;
    case 'list-checks':
      return LucideIcons.listChecks;
    case 'quote':
      return LucideIcons.quote;
    case 'link':
      return LucideIcons.link;
    case 'square-code':
      return LucideIcons.squareCode;
    case 'table':
      return LucideIcons.table;
    case 'check':
      return LucideIcons.check;
    case 'chevron-right':
      return LucideIcons.chevronRight;
    case 'panel-left':
      return LucideIcons.panelLeft;
    case 'arrow-left':
      return LucideIcons.arrowLeft;
    case 'layout-grid':
      return LucideIcons.layoutGrid;
    case 'plus':
      return LucideIcons.plus;
    case 'ellipsis':
      return LucideIcons.ellipsis;
    case 'trash-2':
      return LucideIcons.trash2;
    case 'folder-plus':
      return LucideIcons.folderPlus;
    case 'file-text':
    default:
      return LucideIcons.fileText;
  }
}
