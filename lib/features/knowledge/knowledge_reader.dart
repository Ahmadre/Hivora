import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/lexical/hinata_document.dart';
import '../../core/lexical/hinata_lexical.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/lexical/hinata_outline.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_scope.dart';
import 'knowledge_tokens.dart';
import 'markdown/smart_link_resolver.dart';

enum AsideMode { side, below, none }

/// Article reader: breadcrumb · title · byline (contributor stack · updated ·
/// reads) · labels · rendered body · *Linked issues* grid, plus an aside with
/// Table-of-contents, Contributors, Related articles and Details.
class KnowledgeReader extends StatefulWidget {
  const KnowledgeReader({
    super.key,
    required this.article,
    required this.asideMode,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final KbArticle article;
  final AsideMode asideMode;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Opens the "Report" flow for this article. Sits beside edit/delete rather
  /// than behind a menu, because a knowledge-base page is visible org-wide and
  /// this is the only handle a reader who cannot edit it has on its content.
  final VoidCallback onReport;

  @override
  State<KnowledgeReader> createState() => _KnowledgeReaderState();
}

class _KnowledgeReaderState extends State<KnowledgeReader> {
  /// Publishes the mounted blocks so the outline can scroll to one.
  final BlockRegistry _blocks = BlockRegistry();

  /// The document's headings. Empty until the document has been opened, which
  /// is a frame later — node keys are assigned at parse time, not stored.
  List<OutlineEntry> _outline = const [];

  /// Issues the article links to — read from the document's smart links, which
  /// is where a reference lives now that it is a node.
  List<String> _linkedIssueIds = const [];
  NodeKey? _activeToc;

  @override
  void dispose() {
    _blocks.dispose();
    super.dispose();
  }

  /// Takes the outline and the linked issues from the document that is on
  /// screen — including when there is none.
  ///
  /// The reader has no key, so its State is reused when a different article is
  /// opened. Leaving the previous article's headings up because the new one
  /// could not be read is not a smaller failure than showing nothing: the
  /// entries point at node keys from a document that is gone, so every one of
  /// them is a button that does nothing.
  void _onDocument(LexicalEditor? editor) {
    final outline = editor == null
        ? const <OutlineEntry>[]
        : documentOutline(editor);
    final linked = editor == null
        ? const <String>[]
        : documentSmartLinks(editor, SmartLinkKind.issue);
    if (!mounted) return;
    setState(() {
      _outline = outline;
      _linkedIssueIds = linked;
      _activeToc = null;
    });
  }

  void _jump(OutlineEntry entry) {
    final position = Scrollable.maybeOf(context)?.position;
    // A heading the renderer has culled has no render object yet; marking it
    // active without moving would be a button that lies.
    if (position != null &&
        revealBlock(_blocks, position, entry.nodeKey, alignment: 0.02)) {
      setState(() => _activeToc = entry.nodeKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = KnowledgeScope.of(context).repo;
    final article = _article(repo);
    final aside = _aside(repo, _outline);

    switch (widget.asideMode) {
      case AsideMode.side:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: KbTokens.readerMaxWidth,
                  ),
                  child: article,
                ),
              ),
            ),
            const SizedBox(width: KbTokens.asideGap),
            SizedBox(width: KbTokens.asideWidth, child: aside),
          ],
        );
      case AsideMode.below:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KbTokens.readerMaxWidth,
              ),
              child: article,
            ),
            const SizedBox(height: 30),
            aside,
          ],
        );
      case AsideMode.none:
        return article;
    }
  }

  // ── article column ──
  Widget _article(KnowledgeRepository repo) {
    final a = widget.article;
    final sp = repo.spaceById(a.spaceId);
    final author = repo.userById(a.authorId);
    final parent = a.parentId == null ? null : repo.articleById(a.parentId!);
    final linkedIds = _linkedIssueIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // breadcrumb
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (sp != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: KbTokens.spaceChipBg(sp.hue),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      lucideIcon(sp.icon),
                      size: 13,
                      color: KbTokens.spaceChipText(sp.hue),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sp.name,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: KbTokens.spaceChipText(sp.hue),
                      ),
                    ),
                  ],
                ),
              ),
            if (parent != null) ...[
              Icon(
                lucideIcon('chevron-right'),
                size: 14,
                color: AppColors.inkFaint,
              ),
              GestureDetector(
                onTap: () => KnowledgeScope.of(context).openArticle(parent.id),
                child: Text(
                  parent.title,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // title
        Text(
          a.title,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 31,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 16),
        // byline — on a phone the read-count is dropped and the edit button
        // collapses to an icon so the author line keeps room and doesn't crowd.
        Builder(
          builder: (context) {
            final compact = context.isCompact;
            return Row(
              children: [
                AvatarStack(
                  names: a.contributorIds
                      .map((id) => repo.userById(id)?.name ?? '?')
                      .toList(),
                  radius: 12,
                  max: 4,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                      children: [
                        TextSpan(
                          text: author?.name ?? '',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${context.t('knowledge.updatedAgo', variables: {'when': a.updated})}',
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Icon(lucideIcon('eye'), size: 14, color: AppColors.inkFaint),
                  const SizedBox(width: 5),
                  Text(
                    '${a.reads}',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (compact)
                  Tooltip(
                    message: context.t('knowledge.editShort'),
                    child: OutlinedButton(
                      onPressed: widget.onEdit,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(38, 38),
                      ),
                      child: Icon(lucideIcon('pencil'), size: 16),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: widget.onEdit,
                    icon: Icon(lucideIcon('pencil'), size: 15),
                    label: Text(context.t('knowledge.editShort')),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Tooltip(
                  message: context.t('moderation.report.action'),
                  child: OutlinedButton(
                    onPressed: widget.onReport,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(38, 38),
                      foregroundColor: AppColors.inkSoft,
                      side: BorderSide(color: AppColors.hairline),
                    ),
                    child: Icon(lucideIcon('flag'), size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: context.t('knowledge.delete'),
                  child: OutlinedButton(
                    onPressed: widget.onDelete,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(38, 38),
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.hairline),
                    ),
                    child: Icon(lucideIcon('trash-2'), size: 16),
                  ),
                ),
              ],
            );
          },
        ),
        if (a.labels.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final l in a.labels) _tag(l)],
          ),
        ],
        const SizedBox(height: 22),
        Divider(height: 1, color: AppColors.hairline),
        const SizedBox(height: 8),
        // body
        // The stored document, rendered. Not scrollable: the page around it
        // already scrolls, and the outline reveals blocks through that same
        // position.
        HinataDocument(
          // An article the backfill could not convert still has its markdown;
          // rendering that beats rendering an empty page.
          doc: documentOrLegacy(widget.article.doc, widget.article.body),
          registry: _blocks,
          onDocument: _onDocument,
        ),
        // linked issues
        if (linkedIds.isNotEmpty) _linkedIssues(linkedIds),
      ],
    );
  }

  Widget _linkedIssues(List<String> linkedIds) {
    return Container(
      margin: const EdgeInsets.only(top: 38),
      padding: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(lucideIcon('link-2'), size: 16, color: KbTokens.accent),
              const SizedBox(width: 8),
              Text(
                context.t('knowledge.linkedIssues'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(
                  '${linkedIds.length}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth < KbTokens.bpPhone
                  ? 1
                  : (c.maxWidth / 290).floor().clamp(1, 3);
              const gap = 10.0;
              final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final id in linkedIds)
                    SizedBox(
                      width: tileW,
                      child: _IssueCard(id: id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(KbTokens.radiusChip),
      border: Border.all(color: AppColors.hairline2),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.inkSoft,
      ),
    ),
  );

  // ── aside ──
  Widget _aside(KnowledgeRepository repo, List<OutlineEntry> toc) {
    final a = widget.article;
    final sp = repo.spaceById(a.spaceId);
    final related = repo.relatedArticles(a.body);
    final contributors = a.contributorIds.isEmpty
        ? [a.authorId]
        : a.contributorIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (toc.length > 1) ...[
          _asideHeader(context.t('knowledge.onThisPage')),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.hairline, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final t in toc) _tocRow(t)],
            ),
          ),
          const SizedBox(height: 22),
        ],
        _asideHeader(context.t('knowledge.contributors')),
        const SizedBox(height: 8),
        for (final id in contributors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                AppAvatar(name: repo.userById(id)?.name ?? '?', radius: 13),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    repo.userById(id)?.name ?? '?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        if (related.isNotEmpty) ...[
          const SizedBox(height: 22),
          _asideHeader(context.t('knowledge.relatedArticles')),
          const SizedBox(height: 6),
          for (final d in related)
            InkWell(
              onTap: () => KnowledgeScope.of(context).openArticle(d.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(lucideIcon(d.icon), size: 15, color: KbTokens.accent),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 22),
        _asideHeader(context.t('knowledge.details')),
        const SizedBox(height: 6),
        _detail(context.t('knowledge.created'), a.created),
        _detail(context.t('knowledge.space'), sp?.name ?? '—'),
        _detail(
          context.t('knowledge.status'),
          a.status[0].toUpperCase() + a.status.substring(1),
        ),
      ],
    );
  }

  Widget _asideHeader(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w700,
      color: AppColors.inkFaint,
    ),
  );

  Widget _tocRow(OutlineEntry t) {
    final on = _activeToc == t.nodeKey;
    return InkWell(
      onTap: () => _jump(t),
      child: Transform.translate(
        offset: const Offset(-2, 0),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            t.level == 1 ? 12.0 : (t.level == 2 ? 22.0 : 32.0),
            5,
            8,
            5,
          ),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: on ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            t.text,
            style: TextStyle(
              fontSize: t.level == 3 ? 12 : 12.5,
              height: 1.35,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              color: on ? KbTokens.accent : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// One "Linked issues" card: type glyph · id · state · title · assignee.
/// Resolves [id] (a readable id) against the real backend via [SmartLinkScope];
/// falls back to an id-only card while issues are still loading / not found.
class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final resolver = SmartLinkScope.of(context);
    final it = resolver.issue(id);
    final color = it?.typeColor ?? KbTokens.accent;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(KbTokens.radiusCard),
      child: InkWell(
        onTap: () => resolver.openIssue(id),
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  lucideIcon(it?.typeIcon ?? 'circle-check'),
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          id,
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        if (it != null) ...[
                          const SizedBox(width: 9),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: it.stateColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              it.stateName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: it.stateColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      it?.title ?? 'Open issue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (it?.assigneeName != null)
                AppAvatar(name: it!.assigneeName!, radius: 11),
            ],
          ),
        ),
      ),
    );
  }
}
