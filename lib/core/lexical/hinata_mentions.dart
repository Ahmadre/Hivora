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
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../../features/knowledge/data/knowledge_models.dart' show lucideIcon;
import '../../features/knowledge/markdown/smart_link_resolver.dart';
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
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hairline),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F231F3F),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    // The bundle's node is a stand-in: it exists for the length of one commit
    // so the insertion keeps the package's offset arithmetic, and is replaced
    // by hinata's chip in the same tick.
    onInserted: (suggestion) => _swap(editor, suggestion),
  );
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
          },
        ),
    ];
  }
}

/// One suggestion row, in the app's list idiom.
Widget _row(
  BuildContext context,
  MentionSuggestion suggestion,
  bool highlighted,
) {
  final icon = switch (suggestion.mentionType) {
    'issue' => lucideIcon(suggestion.data['icon'] as String? ?? 'circle-dot'),
    'doc' => lucideIcon(suggestion.data['docIcon'] as String? ?? 'file-text'),
    _ => LucideIcons.atSign,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    color: highlighted ? AppColors.accent.withValues(alpha: 0.14) : null,
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.inkSoft),
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              if ((suggestion.subtitle ?? '').isNotEmpty)
                Text(
                  suggestion.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
