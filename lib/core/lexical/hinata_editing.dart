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
    // The root is not a block and cannot be replaced — `root.replace` throws,
    // uncaught, inside the update. Unreachable from the toolbar, cheap to rule
    // out here rather than relying on that staying true.
    if (block is RootNode) continue;
    final current = _kindOf(block);
    // A shape the toolbar does not model — a table, an image. Rewriting it
    // would flatten it into the pressed kind and lose its structure, so a
    // block button does nothing to it rather than destroying it.
    if (current == null) continue;
    final target = current == kind ? BlockKind.paragraph : kind;
    _replace(block, target, callout);
  }
}

/// Whether every selected block already has [kind] — drives the pressed state.
bool $blockKindIs(BlockKind kind) => $selectedBlockKind() == kind;

/// The kind every selected block has, or null when they differ, the selection
/// is empty, or the shape is one the toolbar does not model.
///
/// One read answers the whole toolbar. Asking per button — thirteen of them,
/// each opening its own `editorState.read()`, on every keystroke — is the same
/// answer paid for thirteen times a frame.
BlockKind? $selectedBlockKind() {
  final selection = $getSelection();
  if (selection == null) return null;
  final blocks = _selectedBlocks(selection).whereType<ElementNode>().toList();
  if (blocks.isEmpty) return null;
  final first = _kindOf(blocks.first);
  if (first == null) return null;
  return blocks.every((block) => _kindOf(block) == first) ? first : null;
}

/// The flavour every selected block is a callout of, or null.
///
/// The four flavours are one block kind, so the pressed state of the warn
/// button cannot be answered by [$selectedBlockKind] alone.
CalloutKind? $selectedCalloutKind() {
  final selection = $getSelection();
  if (selection == null) return null;
  final blocks = _selectedBlocks(selection);
  if (blocks.isEmpty) return null;
  CalloutKind? kind;
  for (final block in blocks) {
    // `_selectedBlocks` already resolves to the top-level block, so a caret
    // inside a callout's paragraph arrives here as the callout.
    if (block is! CalloutNode) return null;
    kind ??= block.kind;
    if (block.kind != kind) return null;
  }
  return kind;
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

  if (kind == BlockKind.callout) {
    _toCallout(subject, callout);
    return;
  }

  ElementNode make() => switch (kind) {
    BlockKind.heading1 => $createHeadingNode(HeadingTag.h1),
    BlockKind.heading2 => $createHeadingNode(HeadingTag.h2),
    BlockKind.heading3 => $createHeadingNode(HeadingTag.h3),
    BlockKind.quote => $createQuoteNode(),
    BlockKind.code => $createCodeNode(),
    _ => $createParagraphNode(),
  };

  // One replacement per source block, which is what Lexical's own
  // `$setBlocksType` does. Merging a three-item list into a single heading
  // keeps every character and loses every boundary between them — "EinsZwei
  // Drei" — and no undo-less writer gets that back.
  final replacements = [
    for (final run in _inlineRunsOf(subject)) make()..appendAll(run),
  ];
  subject.replace(replacements.first);
  LexicalNode anchor = replacements.first;
  for (final replacement in replacements.skip(1)) {
    anchor.insertAfter(replacement);
    anchor = replacement;
  }
}

/// Wraps [subject] in a callout.
///
/// A callout holds *blocks*. Its children therefore have to be blocks too:
/// appending a list's items straight into a paragraph produces
/// `callout > paragraph > [listitem, listitem]`, which round-trips, stores and
/// renders — and is a tree no other Lexical client can read.
void _toCallout(ElementNode subject, CalloutKind kind) {
  final replacement = $createCalloutNode(kind);

  // A list is a block in its own right and moves in whole: a `listitem`
  // outside a `list` is not a legal tree.
  if (subject is ListNode) {
    subject.insertBefore(replacement);
    replacement.append(subject);
    return;
  }

  final loose = <LexicalNode>[];
  void flushLoose() {
    if (loose.isEmpty) return;
    replacement.append($createParagraphNode()..appendAll(loose.toList()));
    loose.clear();
  }

  for (final child in subject.children.toList()) {
    if (child is ElementNode && !child.isInline) {
      // Already a block: it keeps its own shape inside the callout.
      flushLoose();
      replacement.append(child);
    } else {
      loose.add(child);
    }
  }
  flushLoose();
  if (replacement.childrenSize == 0) replacement.append($createParagraphNode());
  subject.replace(replacement);
}

/// The inline content of a block, grouped one entry per *source* block.
///
/// A paragraph is one run. A container — a list, a callout, a list item holding
/// a nested list — yields one run per block it holds, reaching through the
/// nesting. Runs are never merged across a block boundary, because that is
/// exactly where the words of two paragraphs would be glued together.
///
/// Always returns at least one run, so an empty block still converts to an
/// empty block of the new kind rather than disappearing.
List<List<LexicalNode>> _inlineRunsOf(ElementNode block) {
  final runs = <List<LexicalNode>>[];
  final loose = <LexicalNode>[];
  void flushLoose() {
    if (loose.isEmpty) return;
    runs.add(loose.toList());
    loose.clear();
  }

  for (final child in block.children.toList()) {
    if (child is ElementNode && !child.isInline) {
      flushLoose();
      runs.addAll(_inlineRunsOf(child));
    } else {
      loose.add(child);
    }
  }
  flushLoose();
  return runs.isEmpty ? [<LexicalNode>[]] : runs;
}

void _toList(ElementNode subject, BlockKind kind) {
  final type = switch (kind) {
    BlockKind.numberList => ListType.number,
    BlockKind.checkList => ListType.check,
    _ => ListType.bullet,
  };

  // Already this kind of list: unwrap it back to paragraphs, one per item —
  // including the items of a nested list, which are blocks of their own.
  if (subject is ListNode && subject.listType == type) {
    LexicalNode anchor = subject;
    for (final run in _inlineRunsOf(subject)) {
      final paragraph = $createParagraphNode()..appendAll(run);
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

  // Anything else: one item per block it holds, so a callout with two
  // paragraphs becomes two bullets rather than one run-on bullet.
  final list = $createListNode(type);
  for (final run in _inlineRunsOf(subject)) {
    list.append(
      $createListItemNode(type == ListType.check ? false : null)
        ..appendAll(run),
    );
  }
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
