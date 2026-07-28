/// The `{{issue:…}}` / `{{doc:…}}` / `{{user:…}}` chip, as a node.
library;

import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// What a smart link points at.
enum SmartLinkKind {
  /// An issue, addressed by its readable id (`HIN-42`).
  issue,

  /// A knowledge-base article, addressed by its id.
  doc,

  /// A person, addressed by their user id — an `@`-mention.
  user;

  /// The wire-format name, which is the enum name.
  String get wire => name;

  /// Parses a wire-format kind, defaulting to [issue] for anything unknown so
  /// a document written by a newer client still renders something.
  static SmartLinkKind parse(Object? value) => SmartLinkKind.values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => SmartLinkKind.issue,
  );
}

/// A link to something inside hinata, rendered as a chip.
///
/// This used to be a `{{kind:id}}` token inside a markdown string, found by a
/// regex at render time. As a node it is data: the document says what it points
/// at, the search index gets the label instead of an ObjectId, and the server
/// answers "which articles reference this issue" from an index rather than by
/// scanning every body.
///
/// It is an **inline decorator** — a widget in the text flow, atomic to the
/// caret. The label is a denormalised copy of the target's title, kept so the
/// chip and the plain-text projection have something readable before the target
/// is resolved; the live title is looked up when the chip is built, so a stale
/// label is never what the reader sees.
class SmartLinkNode extends DecoratorNode {
  /// Creates a smart link. The no-argument form is what the registry calls
  /// before applying JSON.
  SmartLinkNode({
    SmartLinkKind kind = SmartLinkKind.issue,
    String targetId = '',
    String? label,
  }) : _kind = kind,
       _targetId = targetId,
       _label = label;

  SmartLinkKind _kind;
  String _targetId;
  String? _label;

  @override
  String get type => 'smartlink';

  // Inline: a chip sits in a line of prose, not between paragraphs.
  @override
  bool get isInline => true;

  @override
  SmartLinkNode clone() =>
      SmartLinkNode(kind: _kind, targetId: _targetId, label: _label);

  @override
  void afterCloneFrom(covariant SmartLinkNode prev) {
    super.afterCloneFrom(prev);
    _kind = prev._kind;
    _targetId = prev._targetId;
    _label = prev._label;
  }

  /// What this points at.
  SmartLinkKind get kind => getLatest<SmartLinkNode>()._kind;

  /// The target's id — a readable issue id, or an object id.
  String get targetId => getLatest<SmartLinkNode>()._targetId;

  /// A readable stand-in for the target, or null when there is none.
  String? get label => getLatest<SmartLinkNode>()._label;

  /// Replaces the denormalised label.
  SmartLinkNode setLabel(String? value) =>
      getWritable<SmartLinkNode>().._label = value;

  /// The chip's plain-text stand-in: the label when there is one.
  ///
  /// Deliberately not the id. This is what copy-paste produces and what the
  /// server indexes, and an ObjectId is noise in both.
  @override
  String getTextContent() => _label ?? '';

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'kind': _kind.wire,
    'label': _label,
    'targetId': _targetId,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _kind = SmartLinkKind.parse(json['kind']);
    final targetId = json['targetId'];
    _targetId = targetId is String ? targetId : '';
    final label = json['label'];
    _label = label is String && label.isNotEmpty ? label : null;
  }
}

/// Creates a smart link, applying any registered node replacement.
SmartLinkNode $createSmartLinkNode({
  required SmartLinkKind kind,
  required String targetId,
  String? label,
}) => $applyNodeReplacement(
  SmartLinkNode(kind: kind, targetId: targetId, label: label),
);

/// Whether [node] is a smart link.
bool $isSmartLinkNode(LexicalNode? node) => node is SmartLinkNode;
