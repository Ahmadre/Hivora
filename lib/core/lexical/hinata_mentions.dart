/// Typing `@` to link an issue, an article or a person.
///
/// hinata's chips are [SmartLinkNode]s, not the bundle's `mention` — the app
/// resolves them against live data, navigates on tap and indexes them on the
/// server. The bundle's typeahead is still what runs the interaction (bounded
/// matching, debounce, stale-response rejection, keyboard navigation), and the
/// node it inserts is swapped for hinata's before the writer sees it.
library;

import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../widgets/app_avatar.dart';
import '../widgets/glass_panel.dart';
import '../../features/knowledge/data/knowledge_models.dart' show lucideIcon;
import '../../features/knowledge/markdown/smart_link_resolver.dart';
import '../../features/search/search_tokens.dart';
import 'smart_link_node.dart';

/// The `@` typeahead over [resolver], or null when there is nothing to pick.
///
/// Returns null rather than an empty picker when no [SmartLinkScope] is in
/// scope: a menu that can never have a row is worse than no menu, and the two
/// surfaces without a resolver — a test, a preview — should keep `@` as the
/// plain character it is.
LexicalMentions? hinataMentions({
  required LexicalEditor editor,
  required SmartLinkResolver? resolver,
}) {
  if (resolver == null) return null;
  return LexicalMentions(
    source: _SmartLinkMentionSource(resolver),
    triggers: const [
      // One trigger for all three kinds. The kind rides on each suggestion, so
      // `@` finds an issue, an article and a person in the same list — which is
      // what the markdown mention field did, and what people learned.
      MentionTrigger(character: '@', mentionType: 'user'),
    ],
    limit: 12,
    width: 320,
    maxHeight: 280,
    debounce: const Duration(milliseconds: 120),
    itemBuilder: _row,
    // The app's own material, not a box: the picker is a floating overlay and
    // every other one in hinata is a glass lens. A `Decoration` can draw a
    // fill, a border and a shadow, which is why this popover was the one
    // surface in the product that looked like it came from somewhere else.
    surfaceBuilder: (context, list) => _GlassPopover(child: list),
    // The bundle's node is a stand-in: it exists for the length of one commit
    // so the insertion keeps the package's offset arithmetic, and is replaced
    // by hinata's chip in the same tick.
    onInserted: (suggestion) => _swap(editor, suggestion),
  );
}

/// The picker's surface: the same liquid-glass lens as the search palette and
/// every other floating overlay in the app.
class _GlassPopover extends StatelessWidget {
  const _GlassPopover({required this.child});

  final Widget child;

  static const double _radius = 16;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    return GlassPanelShadow(
      radius: BorderRadius.circular(_radius),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The list is a list of *targets*, and without a word for what
                // the rows are the popover reads as an autocomplete of the text
                // being typed rather than as a picker of things to link to.
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
                  child: Text(
                    context.t('md.linkTo').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the just-inserted `mention` with hinata's `smartlink`.
void _swap(LexicalEditor editor, MentionSuggestion suggestion) {
  final kind = SmartLinkKind.parse(suggestion.mentionType);
  // runUpdate, not update: accepting with Enter arrives through a command
  // handler, so an update is already open — and `update` throws on a nested
  // call. Joining it also makes the insertion and the swap one undo step,
  // which is what a writer means by "undo the mention".
  editor.runUpdate(() {
    final node = _findMention(
      $getRoot(),
      id: suggestion.id,
      type: suggestion.mentionType,
    );
    if (node == null) return;
    node.replace(
      $createSmartLinkNode(
        kind: kind,
        targetId: suggestion.id,
        // Only a readable key reads as itself. An ObjectId does not, and
        // putting one in front of the reader is what the label exists to
        // avoid — so a doc or a person carries no denormalised label and is
        // resolved live instead.
        label: kind == SmartLinkKind.issue ? suggestion.label : null,
      ),
    );
  });
}

/// The last mention in [element] carrying [id] and [type].
///
/// The last, not the first: the same person mentioned twice is ordinary, and
/// the one just inserted is the later of the two.
MentionNode? _findMention(
  ElementNode element, {
  required String id,
  required String type,
}) {
  MentionNode? found;
  for (final child in element.children) {
    if (child is MentionNode &&
        child.mentionId == id &&
        child.mentionType == type) {
      found = child;
    } else if (child is ElementNode) {
      found = _findMention(child, id: id, type: type) ?? found;
    }
  }
  return found;
}

/// Feeds the picker from the ambient resolver.
///
/// Issues may come from the backend (the issue detail refuses to hold a whole
/// project's issue set in memory) while articles and people are already there,
/// so the two are asked for in parallel and shown as one list.
class _SmartLinkMentionSource implements MentionSource {
  const _SmartLinkMentionSource(this.resolver);

  final SmartLinkResolver resolver;

  // Equal for the same resolver. `MentionScope` throws its search controller
  // away whenever the source is not `==` to the previous one, and the editor
  // rebuilds on every keystroke — so a source without this closes the picker
  // on the first character typed after `@`.
  @override
  bool operator ==(Object other) =>
      other is _SmartLinkMentionSource && other.resolver == resolver;

  @override
  int get hashCode => resolver.hashCode;

  @override
  Future<List<MentionSuggestion>> search(MentionQuery query) async {
    final text = query.text.trim();
    final local = resolver.mentions(text, commentMode: false);
    final issues = resolver.asyncIssueMentions
        ? await resolver.searchIssueMentions(text)
        : const <MentionCandidate>[];
    return [
      for (final candidate in [...issues, ...local].take(query.limit))
        MentionSuggestion(
          id: candidate.id,
          // Without the trigger character: the label builder prepends it, and
          // a label of `@Jonas` behind an `@` inserts `@@Jonas`.
          label: candidate.title,
          mentionType: candidate.kind,
          subtitle: candidate.sub,
          data: {
            if (candidate.issueType != null) 'icon': candidate.issueType,
            if (candidate.icon != null) 'docIcon': candidate.icon,
            // The type glyph's hue. Held as an int rather than a `Color`: the
            // bundle copies this map onto the node it inserts, and although
            // that node is replaced before the commit lands, a value that
            // cannot be serialised has no business being on a document.
            if (candidate.issueColor != null)
              'color': candidate.issueColor!.toARGB32(),
          },
        ),
    ];
  }
}

/// One suggestion row, on the glass.
///
/// The selected row is a rounded amber lozenge rather than a full-bleed band:
/// the surface is a lens with rounded corners, and a band painted to its edges
/// fights the shape it sits in.
Widget _row(
  BuildContext context,
  MentionSuggestion suggestion,
  bool highlighted,
) => Container(
  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  decoration: BoxDecoration(
    color: highlighted ? AppColors.accentSoft : null,
    borderRadius: BorderRadius.circular(9),
  ),
  child: Row(
    children: [
      _leading(suggestion),
      const SizedBox(width: 10),
      // Titles are user data of any length and this has to survive a 320 px
      // phone.
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              suggestion.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            if ((suggestion.subtitle ?? '').isNotEmpty)
              Text(
                suggestion.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      _KindBadge(kind: suggestion.mentionType),
    ],
  ),
);

/// The glyph tile at the head of a row.
///
/// A person is their avatar; everything else is its type glyph on a tile tinted
/// with that type's own hue, which is what tells three issues of different
/// kinds apart at a glance.
Widget _leading(MentionSuggestion suggestion) {
  if (suggestion.mentionType == 'user') {
    return AppAvatar(name: suggestion.label, radius: 11);
  }
  final isDoc = suggestion.mentionType == 'doc';
  final raw = suggestion.data['color'];
  final color = isDoc
      ? AppColors.accentStrong
      : (raw is int ? Color(raw) : AppColors.accentStrong);
  final icon = lucideIcon(
    (isDoc ? suggestion.data['docIcon'] : suggestion.data['icon']) as String? ??
        (isDoc ? 'file-text' : 'circle-dot'),
  );
  return Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, size: 14, color: color),
  );
}

/// What kind of thing a row points at, in a word.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      'issue' => context.t('md.kindIssue'),
      'doc' => context.t('md.kindDoc'),
      _ => context.t('md.kindUser'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          color: AppColors.inkFaint,
        ),
      ),
    );
  }
}
