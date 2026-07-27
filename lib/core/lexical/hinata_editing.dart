/// The editing operations the toolbar performs.
///
/// Inline formatting and links are commands the packages already ship. Turning
/// a paragraph into a heading, a quote, a list or a callout is not: Lexical web
/// does it with `$setBlocksType`, which the Dart port has not exposed, so the
/// same operation lives here — replace each selected top-level block with a new
/// element and move its children across.
library;

import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'callout_node.dart';
import 'horizontal_rule_node.dart';
import 'smart_link_node.dart';

/// The block shapes the toolbar can produce.
enum BlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  quote,
  code,
  bulletList,
  numberList,
  checkList,
  callout;

  /// Whether this kind is one of the three list shapes.
  bool get isList =>
      this == bulletList || this == numberList || this == checkList;
}

/// Replaces every selected top-level block with [kind].
///
/// A second application of the same kind returns the block to a paragraph, so
/// the toolbar buttons toggle rather than only ever converting one way — which
/// is what a writer expects from a pressed-looking button.
void $setBlockKind(BlockKind kind, {CalloutKind callout = CalloutKind.info}) {
  final selection = $getSelection();
  if (selection == null) return;

  for (final block in _selectedBlocks(selection)) {
    if (block is! ElementNode) continue;
    final already = _kindOf(block) == kind;
    final target = already ? BlockKind.paragraph : kind;
    _replace(block, target, callout);
  }
}

/// Whether every selected block already has [kind] — drives the pressed state.
bool $blockKindIs(BlockKind kind) {
  final selection = $getSelection();
  if (selection == null) return false;
  final blocks = _selectedBlocks(selection).whereType<ElementNode>().toList();
  if (blocks.isEmpty) return false;
  return blocks.every((block) => _kindOf(block) == kind);
}

/// The distinct top-level blocks the selection touches, in document order.
List<LexicalNode> _selectedBlocks(BaseSelection selection) {
  final seen = <NodeKey>{};
  final blocks = <LexicalNode>[];
  for (final node in selection.getNodes()) {
    final block = node.getTopLevelElement() ?? node;
    if (seen.add(block.key)) blocks.add(block);
  }
  return blocks;
}

/// The kind a block currently is, or null for something the toolbar does not
/// model (a table, an image).
BlockKind? _kindOf(ElementNode block) {
  // A list item's shape is its parent list's, which is what the caret is
  // "inside" from the writer's point of view.
  final subject = block is ListItemNode ? block.getParent() : block;
  return switch (subject) {
    ParagraphNode() => BlockKind.paragraph,
    QuoteNode() => BlockKind.quote,
    CodeNode() => BlockKind.code,
    CalloutNode() => BlockKind.callout,
    HeadingNode(:final tag) => switch (tag) {
      HeadingTag.h1 => BlockKind.heading1,
      HeadingTag.h2 => BlockKind.heading2,
      HeadingTag.h3 => BlockKind.heading3,
      _ => BlockKind.paragraph,
    },
    ListNode(:final listType) => switch (listType) {
      ListType.bullet => BlockKind.bulletList,
      ListType.number => BlockKind.numberList,
      ListType.check => BlockKind.checkList,
    },
    _ => null,
  };
}

void _replace(ElementNode block, BlockKind kind, CalloutKind callout) {
  // Inside a list, the block to convert is the list itself, not the item.
  final subject = block is ListItemNode ? (block.getParent() ?? block) : block;

  if (kind.isList) {
    _toList(subject, kind);
    return;
  }

  final replacement = switch (kind) {
    BlockKind.heading1 => $createHeadingNode(HeadingTag.h1),
    BlockKind.heading2 => $createHeadingNode(HeadingTag.h2),
    BlockKind.heading3 => $createHeadingNode(HeadingTag.h3),
    BlockKind.quote => $createQuoteNode(),
    BlockKind.code => $createCodeNode(),
    BlockKind.callout => $createCalloutNode(callout),
    _ => $createParagraphNode(),
  };

  // A callout holds blocks; everything else here holds inline content. Moving
  // a list's items into a paragraph would produce an illegal tree, so the
  // content is flattened to its inline children first.
  if (kind == BlockKind.callout) {
    final paragraph = $createParagraphNode();
    for (final child in subject.children.toList()) {
      paragraph.append(child);
    }
    replacement.append(paragraph);
  } else {
    for (final child in _inlineContentOf(subject)) {
      replacement.append(child);
    }
  }
  subject.replace(replacement);
}

/// The inline children of a block, reaching through list items and callouts so
/// converting out of them keeps the words.
List<LexicalNode> _inlineContentOf(ElementNode block) {
  final out = <LexicalNode>[];
  for (final child in block.children.toList()) {
    if (child is ElementNode && !child.isInline) {
      out.addAll(_inlineContentOf(child));
    } else {
      out.add(child);
    }
  }
  return out;
}

void _toList(ElementNode subject, BlockKind kind) {
  final type = switch (kind) {
    BlockKind.numberList => ListType.number,
    BlockKind.checkList => ListType.check,
    _ => ListType.bullet,
  };

  // Already this kind of list: unwrap it back to paragraphs.
  if (subject is ListNode && subject.listType == type) {
    LexicalNode anchor = subject;
    for (final item in subject.children.toList()) {
      final paragraph = $createParagraphNode();
      if (item is ElementNode) {
        for (final child in _inlineContentOf(item)) {
          paragraph.append(child);
        }
      }
      anchor.insertAfter(paragraph);
      anchor = paragraph;
    }
    subject.remove();
    return;
  }

  // A different list type: retype in place, keeping the items.
  if (subject is ListNode) {
    final list = $createListNode(type);
    for (final item in subject.children.toList()) {
      list.append(item);
    }
    subject.replace(list);
    return;
  }

  final list = $createListNode(type);
  final item = $createListItemNode(type == ListType.check ? false : null);
  for (final child in _inlineContentOf(subject)) {
    item.append(child);
  }
  list.append(item);
  subject.replace(list);
}

/// Inserts a divider after the selected block.
void $insertDivider() {
  final selection = $getSelection();
  if (selection == null) return;
  final blocks = _selectedBlocks(selection);
  if (blocks.isEmpty) return;
  final anchor = blocks.last.getTopLevelElement() ?? blocks.last;
  final rule = $createHorizontalRuleNode();
  anchor.insertAfter(rule);
  // A divider is atomic, so leave a paragraph behind it — otherwise a rule at
  // the end of a document leaves nowhere to type.
  if (rule.getNextSibling() == null) rule.insertAfter($createParagraphNode());
}

/// Inserts a smart-link chip at the caret.
void $insertSmartLink({
  required SmartLinkKind kind,
  required String targetId,
  String? label,
}) {
  final selection = $getSelection();
  if (selection is! RangeSelection) return;
  selection.insertNodes([
    $createSmartLinkNode(kind: kind, targetId: targetId, label: label),
    $createTextNode(' '),
  ]);
}
