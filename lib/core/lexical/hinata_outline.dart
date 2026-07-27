/// The headings of a document, for a table of contents.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'hinata_lexical.dart';

/// One heading in a document's outline.
///
/// Carries the node's key rather than a `GlobalKey`: the renderer culls blocks
/// that are off screen, so there is no widget to hold a key on until the reader
/// scrolls near it. The key survives that, and the block registry turns it back
/// into something scrollable when it is mounted.
class OutlineEntry {
  const OutlineEntry({
    required this.nodeKey,
    required this.level,
    required this.text,
  });

  /// The heading node's key in the open document.
  final NodeKey nodeKey;

  /// 1–6, as in `h1`–`h6`.
  final int level;

  /// The heading's plain text.
  final String text;
}

/// The h1–h3 headings of an open document, in order.
///
/// Stops at h3 because deeper levels make an aside longer than the article it
/// summarizes — which is what the knowledge base did before this and is why the
/// depth is fixed here rather than left to each caller.
List<OutlineEntry> documentOutline(LexicalEditor editor) =>
    editor.editorState.read(() {
      final entries = <OutlineEntry>[];
      for (final child in $getRoot().children) {
        if (child is! HeadingNode) continue;
        final level = switch (child.tag) {
          HeadingTag.h1 => 1,
          HeadingTag.h2 => 2,
          HeadingTag.h3 => 3,
          _ => 0,
        };
        if (level == 0) continue;
        final text = child.getTextContent().trim();
        if (text.isEmpty) continue;
        entries.add(OutlineEntry(nodeKey: child.key, level: level, text: text));
      }
      return entries;
    });

/// The targets a document's smart links point at, of the given kind, in order.
///
/// Replaces scanning the body for `{{issue:KEY}}` tokens: a link is a node now,
/// so the references are read from the document rather than pattern-matched out
/// of text that no longer contains them.
List<String> documentSmartLinks(LexicalEditor editor, SmartLinkKind kind) =>
    editor.editorState.read(() {
      final seen = <String>{};
      final out = <String>[];
      void walk(ElementNode element) {
        for (final child in element.children) {
          if (child is SmartLinkNode) {
            if (child.kind == kind && seen.add(child.targetId)) {
              out.add(child.targetId);
            }
          } else if (child is ElementNode) {
            walk(child);
          }
        }
      }

      walk($getRoot());
      return out;
    });

/// As [documentSmartLinks], but for a document that is not open in an editor.
///
/// Opens it in a throwaway one. Callers that already have an editor should use
/// [documentSmartLinks]; this is for the common case of holding only the stored
/// string, and it returns nothing rather than throwing on an unreadable one.
List<String> smartLinksIn(String? doc, SmartLinkKind kind) {
  if (doc == null || doc.trim().isEmpty) return const [];
  try {
    final editor = createHinataEditor()
      ..setEditorState(createHinataEditor().parseEditorStateFromString(doc));
    return documentSmartLinks(editor, kind);
  } on Object {
    return const [];
  }
}

/// Scrolls [position] so the block for [nodeKey] is visible.
///
/// Returns false when the block is not mounted — the renderer culls what is off
/// screen, so a far-away heading has no render object to reveal yet. Saying so
/// lets the caller fall back rather than silently doing nothing.
bool revealBlock(
  BlockRegistry registry,
  ScrollPosition position,
  NodeKey nodeKey, {
  Duration duration = const Duration(milliseconds: 260),
  Curve curve = Curves.easeOutCubic,
  double alignment = 0,
}) {
  final block = registry[nodeKey];
  if (block == null || !block.render.attached) return false;
  position.ensureVisible(
    block.render,
    alignment: alignment,
    duration: duration,
    curve: curve,
  );
  return true;
}
