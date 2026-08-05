import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        GlassContainer,
        GlassMenuAlignment,
        GlassPopover,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/lexical/hinata_document.dart';
import 'voice/voice_player.dart';

part 'comment_thread.bubbles.dart';
part 'comment_thread.menus.dart';
part 'comment_thread.voice.dart';

/// The quick-reaction emojis offered by the reaction popover (before the "…"
/// opens the full device picker). Mirrors WhatsApp/iMessage.
const List<String> kQuickReactions = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

/// Opaque glass for the reaction/menu popovers: they float over the feed, so —
/// like the composer — they need a strong tint (transparent nav glass would be
/// unreadable) and, on native, the standard lightweight shader (the default
/// premium pipeline corrupts on rotation). Same lighting as [kNavGlassDark].
const _menuGlassDark = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345,
  glassColor: Color(0xD91A1A22), // ~0.85 opaque dark slate
);
const _menuGlassLight = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345,
  glassColor: Color(0xF2FFFFFF), // ~0.95 near-solid frost
);

LiquidGlassSettings _navGlass(bool dark) =>
    dark ? _menuGlassDark : _menuGlassLight;

/// How top-level comments are ordered. Reply threads are *always* oldest-first,
/// independent of this.
enum CommentSort {
  newest,
  oldest;

  /// The `sort` query value the backend expects.
  String get api => this == CommentSort.oldest ? 'oldest' : 'newest';
}

/// Compact "Newest first ▾" selector that opens a two-option glass popover.
class CommentSortButton extends StatelessWidget {
  const CommentSortButton({
    super.key,
    required this.sort,
    required this.onChanged,
    this.compact = false,
  });

  final CommentSort sort;
  final ValueChanged<CommentSort> onChanged;

  /// Icon-only trigger for narrow layouts where the text label wouldn't fit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final label = sort == CommentSort.newest
        ? context.t('comments.sortNewest')
        : context.t('comments.sortOldest');
    return GlassPopover(
      alignment: GlassMenuAlignment.bottomRight,
      popoverWidth: 200,
      popoverBorderRadius: 18,
      settings: _navGlass(dark),
      quality: GlassQuality.standard,
      triggerBuilder: (context, toggle) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: toggle,
          borderRadius: BorderRadius.circular(9),
          // Only attach a tooltip in the icon-only (compact) layout — the wide
          // layout shows the label inline, so an empty-message tooltip there
          // would pop a blank grey bubble on hover.
          child: _CompactTooltip(
            enabled: compact,
            message: label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.arrowUpDown,
                    size: compact ? 16 : 14,
                    color: AppColors.inkSoft,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 14,
                      color: AppColors.inkSoft,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      contentBuilder: (context, close) => _ContextMenuCard(
        rows: [
          _MenuRowData(
            sort == CommentSort.newest
                ? LucideIcons.check
                : LucideIcons.arrowDown,
            context.t('comments.sortNewest'),
            () {
              close();
              onChanged(CommentSort.newest);
            },
          ),
          _MenuRowData(
            sort == CommentSort.oldest
                ? LucideIcons.check
                : LucideIcons.arrowUp,
            context.t('comments.sortOldest'),
            () {
              close();
              onChanged(CommentSort.oldest);
            },
          ),
        ],
      ),
    );
  }
}

/// Wraps [child] in a [Tooltip] only when [enabled]; otherwise returns it
/// untouched, so a control that shows its label inline doesn't also pop an
/// empty tooltip bubble.
class _CompactTooltip extends StatelessWidget {
  const _CompactTooltip({
    required this.enabled,
    required this.message,
    required this.child,
  });

  final bool enabled;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Tooltip(message: message, child: child);
  }
}

/// View-state of one root comment's (lazily loaded) reply thread. Owned by the
/// issue sheet and handed to the thread via [CommentInteractions.threadOf].
class ReplyThread {
  const ReplyThread({
    this.expanded = false,
    this.loading = false,
    this.replies = const [],
    this.total = 0,
  });

  /// Whether the thread is currently unfolded.
  final bool expanded;

  /// Whether a page of replies is in flight.
  final bool loading;

  /// Loaded replies, oldest-first (newest at the bottom).
  final List<IssueComment> replies;

  /// Total replies on the backend (known once a page has loaded).
  final int total;

  /// More older-than-loaded… no — more *newer* replies remain to page in.
  bool get hasMore => replies.length < total;

  ReplyThread copyWith({
    bool? expanded,
    bool? loading,
    List<IssueComment>? replies,
    int? total,
  }) => ReplyThread(
    expanded: expanded ?? this.expanded,
    loading: loading ?? this.loading,
    replies: replies ?? this.replies,
    total: total ?? this.total,
  );
}

/// The per-comment actions + directory lookups the thread needs, bundled so both
/// [CommentThread] and a single [CommentBubbleRow] (the "All" tab) share one
/// wiring. Callbacks are dispatched by the persistent action row + popovers.
class CommentInteractions {
  const CommentInteractions({
    required this.meId,
    required this.nameFor,
    required this.avatarFor,
    required this.loadVoice,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onReply,
    required this.onReact,
    required this.onCopy,
    required this.onCopyLink,
    required this.onTogglePin,
    required this.onEnterSelection,
    required this.onJumpToComment,
    required this.onReport,
    required this.onOpenAuthor,
    required this.threadOf,
    required this.onToggleReplies,
    required this.onLoadMoreReplies,
  });

  final String? meId;
  final String Function(String authorId) nameFor;
  final String? Function(String authorId) avatarFor;
  final VoiceAudioLoader Function(IssueComment comment) loadVoice;

  /// Whether the signed-in user owns [comment] (edit/delete/select gate).
  final bool Function(IssueComment comment) canManage;

  final void Function(IssueComment comment) onEdit;
  final void Function(IssueComment comment) onDelete;
  final void Function(IssueComment comment) onReply;
  final void Function(IssueComment comment, String emoji) onReact;
  final void Function(IssueComment comment) onCopy;
  final void Function(IssueComment comment) onCopyLink;
  final void Function(IssueComment comment) onTogglePin;
  final void Function(IssueComment comment) onEnterSelection;
  final void Function(String commentId) onJumpToComment;

  /// Opens the "Report" flow for [comment]. Offered on every comment, including
  /// the reader's own: a report is about content, and letting someone flag their
  /// own post is harmless next to a menu whose rows appear and disappear
  /// depending on who wrote what.
  final void Function(IssueComment comment) onReport;

  /// Opens the author's actions popover (report / block the person), anchored to
  /// [anchor] — the avatar's global rect, captured before the tap's async gap so
  /// the popover has somewhere to point on wide layouts.
  final void Function(IssueComment comment, Rect anchor) onOpenAuthor;

  /// The reply-thread view-state for a root comment (empty if never expanded).
  final ReplyThread Function(String rootId) threadOf;

  /// Expand (loading the first page) / collapse a root's reply thread.
  final void Function(IssueComment root) onToggleReplies;

  /// Load the next page of a root's replies.
  final void Function(IssueComment root) onLoadMoreReplies;
}

/// Jira-style comment feed (flat text, always left-aligned). Each top-level
/// comment renders a header (author · date), its body, reactions and a
/// persistent action row, followed by its own collapsible reply thread.
class CommentThread extends StatelessWidget {
  const CommentThread({
    super.key,
    required this.comments,
    required this.interactions,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelected,
    this.highlightedId,
    this.commentKeys,
    this.pinnedSection = false,
  });

  final List<IssueComment> comments;
  final CommentInteractions interactions;

  /// Multi-select (batch delete of own comments) state.
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(IssueComment comment)? onToggleSelected;

  /// Comment to flash (deep-link / reply-jump highlight).
  final String? highlightedId;

  /// Stable keys per comment id so a jump can scroll to a specific row.
  final Map<String, GlobalKey>? commentKeys;

  /// The pinned section renders each comment standalone (no reply threads).
  final bool pinnedSection;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var idx = 0; idx < comments.length; idx++) {
      final c = comments[idx];
      final hasThread = !pinnedSection && c.isRoot;
      final thread = hasThread
          ? interactions.threadOf(c.id)
          : const ReplyThread();
      final row = CommentBubbleRow(
        comment: c,
        interactions: interactions,
        pinned: pinnedSection,
        selectionMode: selectionMode,
        selected: selectedIds.contains(c.id),
        onToggleSelected: onToggleSelected,
        highlight: highlightedId == c.id,
        trunkBelow: thread.expanded && thread.replies.isNotEmpty,
      );
      final key = commentKeys?[c.id];
      // Isolate each bubble's glass/blur repaint so one comment's state change
      // (reaction, pin, voice tick) doesn't repaint the whole eager thread.
      final boundaried = RepaintBoundary(child: row);
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: idx == 0 ? 0 : 18),
          child: key == null
              ? boundaried
              : KeyedSubtree(key: key, child: boundaried),
        ),
      );
      // A root comment carries its own flat reply thread (never in the pinned
      // section, and never for a reply row).
      if (hasThread) {
        rows.add(
          _ReplyThreadView(
            root: c,
            interactions: interactions,
            selectionMode: selectionMode,
            selectedIds: selectedIds,
            onToggleSelected: onToggleSelected,
            highlightedId: highlightedId,
            commentKeys: commentKeys,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
