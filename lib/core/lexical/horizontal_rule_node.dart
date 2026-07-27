/// The `---` divider, as a node.
library;

import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// A horizontal rule.
///
/// Upstream Lexical has this node; the Dart port does not implement it yet, and
/// hinata's markdown has always supported `---`. Registering it here is what
/// keeps a stored document containing a divider openable at all — an
/// unregistered type is refused loudly rather than dropped, which is the right
/// default and the wrong outcome for a construct users actually write.
///
/// It carries no fields, so the whole implementation is its type string. The
/// wire shape matches upstream's: `{"type": "horizontalrule", "version": 1}`.
///
/// TODO(lexical): move this into `lexical_rich_text` upstream — it is a
/// standard Lexical node, not something specific to this application.
class HorizontalRuleNode extends DecoratorNode {
  /// Creates a rule.
  HorizontalRuleNode();

  @override
  String get type => 'horizontalrule';

  @override
  HorizontalRuleNode clone() => HorizontalRuleNode();

  // A block: it sits between paragraphs, never inside a line.
  @override
  bool get isInline => false;
}

/// Creates a horizontal rule, applying any registered node replacement.
HorizontalRuleNode $createHorizontalRuleNode() =>
    $applyNodeReplacement(HorizontalRuleNode());

/// Whether [node] is a horizontal rule.
bool $isHorizontalRuleNode(LexicalNode? node) => node is HorizontalRuleNode;
