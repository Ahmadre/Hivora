/// The `:::info` admonition block, as a node.
library;

import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// The four callout flavours hinata has always written.
enum CalloutKind {
  /// Neutral context.
  info,

  /// Something that can go wrong.
  warn,

  /// An aside.
  note,

  /// A suggestion.
  tip;

  /// The wire-format name, which is the enum name.
  String get wire => name;

  /// Parses a wire-format kind, defaulting to [info] so a document written by a
  /// newer client still renders as a callout rather than failing to open.
  static CalloutKind parse(Object? value) => CalloutKind.values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => CalloutKind.info,
  );
}

/// A callout: a block of content set apart from the prose around it.
///
/// An element rather than a decorator, because its content is a document —
/// paragraphs, lists, links — that stays editable in place. Its only field is
/// which flavour it is.
class CalloutNode extends ElementNode {
  /// Creates a callout. The no-argument form is what the registry calls before
  /// applying JSON.
  CalloutNode([this._kind = CalloutKind.info]);

  CalloutKind _kind;

  @override
  String get type => 'callout';

  @override
  CalloutNode clone() => CalloutNode(_kind);

  @override
  void afterCloneFrom(covariant CalloutNode prev) {
    super.afterCloneFrom(prev);
    _kind = prev._kind;
  }

  /// Which flavour this is.
  CalloutKind get kind => getLatest<CalloutNode>()._kind;

  /// Changes the flavour.
  CalloutNode setKind(CalloutKind value) =>
      getWritable<CalloutNode>().._kind = value;

  @override
  ElementNode insertNewAfter({required bool isAtEnd}) {
    // Enter at the end leaves the callout; anywhere else splits it, which is
    // what a block that holds several paragraphs should do. Pressing Enter on
    // the last empty line is how a writer gets out, and it is the behaviour a
    // quote has in Lexical for the same reason.
    if (isAtEnd) {
      final paragraph = $createParagraphNode();
      paragraph.setDirection(getDirection());
      insertAfter(paragraph);
      return paragraph;
    }
    final paragraph = $createParagraphNode();
    paragraph.setDirection(getDirection());
    append(paragraph);
    return paragraph;
  }

  @override
  Map<String, Object?> exportJson() => {
    ...super.exportJson(),
    'kind': _kind.wire,
  };

  @override
  void updateFromJson(Map<String, Object?> json) {
    super.updateFromJson(json);
    _kind = CalloutKind.parse(json['kind']);
  }
}

/// Creates a callout, applying any registered node replacement.
CalloutNode $createCalloutNode(CalloutKind kind) =>
    $applyNodeReplacement(CalloutNode(kind));

/// Whether [node] is a callout.
bool $isCalloutNode(LexicalNode? node) => node is CalloutNode;
