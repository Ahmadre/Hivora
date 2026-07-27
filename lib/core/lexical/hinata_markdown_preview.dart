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

/// A thematic break on a line of its own: `---`, `***` or `___`.
final RegExp _thematicBreak = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');

/// Opens or closes a fenced code block.
final RegExp _codeFence = RegExp(r'^\s*(```|~~~)');

/// `![alt](src)`, written the way the server writes it.
///
/// The package ships an `imageTransformer` and it is *almost* this one: it
/// stamps the playground's `maxWidth` of 800, while the server writes 500. A
/// preview that differs from the stored document by a field is precisely what
/// this module exists to prevent, so the rule is spelled out here rather than
/// borrowed.
final TextMatchTransformer _imageTransformer = TextMatchTransformer(
  // The `!` is part of the match: without it the link rule claims the
  // `[alt](src)` and the image arrives as a link behind a stray `!`.
  regExp: RegExp(r'!\[([^\[\]]*)\]\(([^)\s]+)\)'),
  replace: (match, format) =>
      $createImageNode(src: match.group(2)!, altText: match.group(1)!),
  export: (node, exportChildren) =>
      node is! ImageNode ? null : '![${node.altText}](${node.src})',
);

/// The rules hinata converts markdown with.
///
/// Ordinary markdown plus the two constructs the server converts and the
/// default set leaves out — images and tables — because neither is part of
/// upstream's `TRANSFORMERS` either. Without them `![x](url)` previews as a
/// literal `!` in front of a link and a pipe table as paragraphs of pipes,
/// while the server stores an image and a table.
final MarkdownTransformers hinataMarkdownTransformers =
    defaultMarkdownTransformers.extend(
      elements: [tableTransformer],
      textMatches: [_imageTransformer],
    );

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

/// The document to show for a row that may predate the format change.
///
/// The server backfills markdown into Lexical, but that migration has an
/// explicit per-row failure branch that logs and leaves the document null — and
/// those rows still hold their markdown. Reading [doc] alone turns exactly
/// those rows into a blank article, a "no description", an empty comment. This
/// converts the legacy text instead, which is the same conversion the backfill
/// would have done.
///
/// Returns null only when there genuinely is nothing to show.
String? documentOrLegacy(String? doc, String? legacyMarkdown) {
  if (doc != null && doc.trim().isNotEmpty) return doc;
  final legacy = legacyMarkdown?.trim();
  if (legacy == null || legacy.isEmpty) return null;
  return _cachedConversion(legacy);
}

/// Conversions of legacy content, kept across rebuilds.
///
/// [documentOrLegacy] is called from `build`, and a surface rebuilds on every
/// keystroke in the composer above it. Re-parsing markdown each time would make
/// the rare broken row the expensive one. Bounded, because the cache exists to
/// survive rebuilds of the same few documents, not to grow with the session.
final Map<String, String?> _legacyConversions = <String, String?>{};
const int _legacyConversionsMax = 8;

String? _cachedConversion(String markdown) {
  final hit = _legacyConversions[markdown];
  if (hit != null || _legacyConversions.containsKey(markdown)) return hit;
  final converted = markdownToDocument(markdown);
  if (_legacyConversions.length >= _legacyConversionsMax) {
    _legacyConversions.remove(_legacyConversions.keys.first);
  }
  _legacyConversions[markdown] = converted;
  return converted;
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
      $convertFromMarkdown(
        _spellBreaksWithDashes(markdown),
        transformers: hinataMarkdownTransformers,
      );
      final root = $getRoot();
      _foldThematicBreaks(root);
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

/// Rewrites `***` and `___` break lines as `---`.
///
/// A thematic break has three spellings and the emphasis rules eat two of them:
/// by the time there is a node to fold, `***` has already become a stray `*`.
/// So the spelling is settled on the source line, where the construct actually
/// lives, and [_foldThematicBreaks] only ever has to recognise dashes.
///
/// Fenced code is skipped: inside a fence those characters are content, and
/// rewriting them would change what the writer typed.
String _spellBreaksWithDashes(String markdown) {
  final lines = markdown.split('\n');
  var fenced = false;
  for (var i = 0; i < lines.length; i++) {
    if (_codeFence.hasMatch(lines[i])) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    if (_thematicBreak.hasMatch(lines[i].trim())) lines[i] = '---';
  }
  return lines.join('\n');
}

/// Turns a paragraph that is nothing but `---` into a divider.
///
/// The importer is line-based and has no rule for a thematic break, so it
/// leaves the marker as a paragraph holding the literal characters. The server
/// writes a `horizontalrule`, and a preview showing `---` as text where the
/// stored document has a rule is the same broken promise as the image case.
///
/// Only paragraphs, and only at the top level: `---` inside a code block is
/// content, and inside a table cell it is a column separator.
void _foldThematicBreaks(ElementNode root) {
  for (final child in root.children.toList()) {
    if (child is! ParagraphNode) continue;
    if (!_thematicBreak.hasMatch(child.getTextContent().trim())) continue;
    child.replace($createHorizontalRuleNode());
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
///
/// Fences nest: a `:::` closes the innermost opener, not the outermost, and the
/// body of a folded callout is folded in turn. Counting depth is what keeps the
/// first `:::` of `:::info … :::info … ::: …:::` from ending the outer block
/// and leaving the inner marker on screen as literal text.
void _foldCallouts(ElementNode container) {
  for (final child in container.children.toList()) {
    // A node an earlier fold already consumed is no longer here.
    if (child.getParent()?.key != container.key) continue;
    final opener = _markerOf(child);
    if (opener == null) continue;

    // Collect until the fence that closes *this* opener; give up if there is
    // none, which is what leaves a typo showing as the text it is.
    final body = <LexicalNode>[];
    var depth = 1;
    LexicalNode? closer;
    var scan = child.getNextSibling();
    while (scan != null) {
      if (_markerOf(scan) != null) {
        depth++;
      } else if (_isCloseMarker(scan)) {
        depth--;
        if (depth == 0) {
          closer = scan;
          break;
        }
      }
      body.add(scan);
      scan = scan.getNextSibling();
    }
    if (closer == null) continue;

    final callout = $createCalloutNode(opener);
    for (final block in body) {
      callout.append(block);
    }
    if (callout.childrenSize == 0) callout.append($createParagraphNode());
    child.replace(callout);
    closer.remove();
    _foldCallouts(callout);
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
