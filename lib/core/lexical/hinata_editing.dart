/// The editing operations the toolbar performs.
///
/// Turning a paragraph into a heading, a quote or a code block is the package's
/// `$setBlocksType`, and it is used for exactly that. What stays here is the
/// part that is hinata's: the toggle a pressed-looking button implies, and the
/// two shapes that are containers rather than lines — a list, and hinata's own
/// callout. Converting one of those means unwrapping it, which is a decision
/// about hinata's document, not an operation Lexical can make on its own.
library;

import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'callout_node.dart';
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

  final subjects = _selectedSubjects(selection);
  if (subjects.isEmpty) return;

  final target = $selectedBlockKind() == kind ? BlockKind.paragraph : kind;
  final containers = subjects.any(_isContainer);

  // No container on either side: this is the package's operation exactly — one
  // new element per block, children carried across, and anything that holds
  // blocks rather than a line left alone. A caret in a table cell converts the
  // paragraph in that cell, which is what the writer pointed at.
  if (!containers && !target.isList && target != BlockKind.callout) {
    $setBlocksType(selection, () => _createBlock(target));
    return;
  }

  for (final subject in subjects) {
    _replace(subject, target, callout);
  }
}

/// Whether hinata treats [node] as a container it unwraps rather than replaces.
bool _isContainer(ElementNode node) => node is ListNode || node is CalloutNode;

/// The element a block button acts on, for one selected node.
///
/// The outermost list or callout on the path when there is one — pressing the
/// list button with the caret in a nested item is about the list, not the item.
/// Otherwise the nearest block that holds a line, which is what [$isBlock]
/// means: a table, a row and a cell are containers, so a caret inside one
/// resolves to the paragraph in the cell and the table is never a subject.
ElementNode? _subjectOf(LexicalNode node) {
  ElementNode? leaf;
  ElementNode? container;
  for (LexicalNode? current = node; current != null; ) {
    if (current is ElementNode) {
      if (leaf == null && $isBlock(current)) leaf = current;
      if (_isContainer(current)) container = current;
    }
    current = current.getParent();
  }
  return container ?? leaf;
}

/// The distinct elements the selection's blocks resolve to, in document order.
List<ElementNode> _selectedSubjects(BaseSelection selection) {
  final seen = <NodeKey>{};
  final subjects = <ElementNode>[];
  for (final node in selection.getNodes()) {
    final subject = _subjectOf(node);
    if (subject != null && seen.add(subject.key)) subjects.add(subject);
  }
  return subjects;
}

/// A fresh element of [kind], for the kinds that are a line rather than a
/// container.
ElementNode _createBlock(BlockKind kind) => switch (kind) {
  BlockKind.heading1 => $createHeadingNode(HeadingTag.h1),
  BlockKind.heading2 => $createHeadingNode(HeadingTag.h2),
  BlockKind.heading3 => $createHeadingNode(HeadingTag.h3),
  BlockKind.quote => $createQuoteNode(),
  BlockKind.code => $createCodeNode(),
  _ => $createParagraphNode(),
};

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
  final subjects = _selectedSubjects(selection);
  if (subjects.isEmpty) return null;
  final first = _kindOf(subjects.first);
  if (first == null) return null;
  return subjects.every((subject) => _kindOf(subject) == first) ? first : null;
}

/// The flavour every selected block is a callout of, or null.
///
/// The four flavours are one block kind, so the pressed state of the warn
/// button cannot be answered by [$selectedBlockKind] alone.
CalloutKind? $selectedCalloutKind() {
  final selection = $getSelection();
  if (selection == null) return null;
  final subjects = _selectedSubjects(selection);
  if (subjects.isEmpty) return null;
  CalloutKind? kind;
  for (final subject in subjects) {
    // `_selectedSubjects` resolves to the enclosing callout, so a caret inside
    // a callout's paragraph arrives here as the callout.
    if (subject is! CalloutNode) return null;
    kind ??= subject.kind;
    if (subject.kind != kind) return null;
  }
  return kind;
}

/// The kind a subject currently is, or null for a shape the toolbar does not
/// model — a table, an image.
BlockKind? _kindOf(ElementNode subject) {
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

/// Converts one subject, for the cases the package's operation cannot cover:
/// a container on either side of the conversion.
void _replace(ElementNode subject, BlockKind kind, CalloutKind callout) {
  if (kind.isList) {
    _toList(subject, kind);
    return;
  }

  if (kind == BlockKind.callout) {
    _toCallout(subject, callout);
    return;
  }

  // Unwrapping a container: one replacement per block it holds, the same rule
  // `$setBlocksType` follows. Merging a three-item list into a single heading
  // keeps every character and loses every boundary between them —
  // "EinsZweiDrei" — and no undo-less writer gets that back.
  final replacements = [
    for (final run in _inlineRunsOf(subject))
      _createBlock(kind)..appendAll(run),
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
  final subjects = _selectedSubjects(selection);
  if (subjects.isEmpty) return;
  // The top-level element, not the subject: a rule belongs after the table,
  // not inside the cell the caret happens to be in.
  final anchor = subjects.last.getTopLevelElement() ?? subjects.last;
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
