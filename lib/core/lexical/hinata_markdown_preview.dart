/// What a markdown draft will look like once it is stored.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lexical_markdown/lexical_markdown.dart';

import 'hinata_document.dart';
import 'hinata_lexical.dart';

/// Matches the smart-link tokens the composer's mention field writes.
final RegExp _smartLinkToken = RegExp(r'\{\{(issue|doc|user):([^}]+)}}');

/// Opens a callout block. Mirrors the server's pre-pass exactly.
final RegExp _calloutOpen = RegExp(r'^:::(info|warn|note|tip)\s*$');

/// Closes a callout block.
final RegExp _calloutClose = RegExp(r'^:::\s*$');

/// Renders a markdown draft as the document it will become.
///
/// The comment composer stays a plain text field on purpose — most comments are
/// a sentence, and a document editor makes the common case heavier for nothing.
/// It therefore sends markdown, and the server converts it exactly as it
/// converts markdown from an AI agent or an inbound e-mail.
///
/// This preview runs the same conversion on the client, so what the writer sees
/// is what will be stored rather than a second renderer's opinion of it.
class HinataMarkdownPreview extends StatelessWidget {
  const HinataMarkdownPreview({
    required this.markdown,
    super.key,
    this.fontSize = 14,
    this.blockSpacing,
  });

  /// The draft, as typed.
  final String markdown;

  final double fontSize;
  final double? blockSpacing;

  @override
  Widget build(BuildContext context) => HinataDocument(
    doc: markdownToDocument(markdown),
    fontSize: fontSize,
    blockSpacing: blockSpacing,
  );
}

/// Converts markdown to a stored document, or null when there is nothing in it.
///
/// The `{{kind:id}}` tokens are hinata's own and markdown knows nothing about
/// them, so they are turned into smart-link nodes in a second pass over the
/// text the markdown importer produced — the same two-step the server performs.
String? markdownToDocument(String markdown) {
  if (markdown.trim().isEmpty) return null;
  final editor = createHinataEditor();
  try {
    editor.update(() {
      $convertFromMarkdown(markdown, transformers: defaultMarkdownTransformers);
      final root = $getRoot();
      _foldCallouts(root);
      _replaceSmartLinkTokens(root);
      if (root.childrenSize == 0) root.append($createParagraphNode());
    }, discrete: true);
    return editor.toJsonString();
  } on Object {
    // A draft that cannot be converted is still a draft; the composer shows
    // nothing rather than an exception where the preview should be.
    return null;
  }
}

/// Folds `:::kind` … `:::` runs into callout blocks.
///
/// Markdown knows nothing about the fences, so the importer leaves them as
/// paragraphs holding the literal marker. Converting the whole draft once and
/// folding afterwards keeps this to a single pass over one editor — splitting
/// the source first would mean converting each run in its own editor, and the
/// importer clears the root it writes into.
///
/// An unterminated opener is left alone, so a typo shows as the text it is
/// rather than swallowing the rest of the draft.
void _foldCallouts(ElementNode root) {
  for (final child in root.children.toList()) {
    final opener = _markerOf(child);
    if (opener == null) continue;

    // Collect until the closing fence; give up if there is none.
    final body = <LexicalNode>[];
    var closer = child.getNextSibling();
    while (closer != null && !_isCloseMarker(closer)) {
      body.add(closer);
      closer = closer.getNextSibling();
    }
    if (closer == null) continue;

    final callout = $createCalloutNode(opener);
    for (final block in body) {
      callout.append(block);
    }
    if (callout.childrenSize == 0) callout.append($createParagraphNode());
    child.replace(callout);
    closer.remove();
  }
}

/// The callout kind a node opens, or null when it is not an opening fence.
CalloutKind? _markerOf(LexicalNode node) {
  if (node is! ElementNode) return null;
  final match = _calloutOpen.firstMatch(node.getTextContent().trim());
  return match == null ? null : CalloutKind.parse(match.group(1));
}

bool _isCloseMarker(LexicalNode node) =>
    node is ElementNode && _calloutClose.hasMatch(node.getTextContent().trim());

/// Rewrites `{{kind:id}}` inside text nodes as smart-link nodes.
void _replaceSmartLinkTokens(ElementNode element) {
  for (final child in element.children.toList()) {
    if (child is ElementNode) {
      _replaceSmartLinkTokens(child);
      continue;
    }
    if (child is! TextNode) continue;

    final text = child.getTextContent();
    final matches = _smartLinkToken.allMatches(text).toList();
    if (matches.isEmpty) continue;

    // Build the replacement run, then swap it in — mutating while walking the
    // original would invalidate the sibling pointers mid-iteration.
    final replacements = <LexicalNode>[];
    var last = 0;
    for (final match in matches) {
      if (match.start > last) {
        replacements.add($createTextNode(text.substring(last, match.start)));
      }
      final kind = SmartLinkKind.parse(match.group(1));
      final targetId = match.group(2)!.trim();
      replacements.add(
        $createSmartLinkNode(
          kind: kind,
          targetId: targetId,
          // Only an issue key is readable on its own; an ObjectId is not, and
          // inventing a label from it would put the id in front of the reader.
          label: kind == SmartLinkKind.issue ? targetId : null,
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      replacements.add($createTextNode(text.substring(last)));
    }

    LexicalNode anchor = child;
    for (final replacement in replacements) {
      anchor.insertAfter(replacement);
      anchor = replacement;
    }
    child.remove();
  }
}
