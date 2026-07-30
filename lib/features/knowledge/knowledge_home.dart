import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_tokens.dart';

/// KB home: search + a card grid of spaces + a "recently updated" list.
class KnowledgeHome extends StatefulWidget {
  const KnowledgeHome({
    super.key,
    required this.repo,
    required this.onOpenArticle,
    required this.onOpenSpace,
    required this.onNewSpace,
    required this.onDeleteSpace,
  });

  final KnowledgeRepository repo;
  final ValueChanged<String> onOpenArticle;
  final ValueChanged<String> onOpenSpace;
  final VoidCallback onNewSpace;

  /// Delete an empty, persisted space (by name/id).
  final ValueChanged<String> onDeleteSpace;

  @override
  State<KnowledgeHome> createState() => _KnowledgeHomeState();
}

class _KnowledgeHomeState extends State<KnowledgeHome> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final matches = _query.trim().isEmpty
        ? null
        : repo.articles.where((a) {
            final sp = repo.spaceById(a.spaceId);
            final hay = '${a.title} ${sp?.name ?? ''} ${a.labels.join(' ')}'
                .toLowerCase();
            return hay.contains(_query.toLowerCase());
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchBar(),
        const SizedBox(height: 22),
        if (matches != null)
          _results(matches)
        else ...[
          _spacesGrid(repo),
          const SizedBox(height: 26),
          _sectionHeader(context.t('knowledge.recentlyUpdated')),
          const SizedBox(height: 12),
          ..._recent(repo).map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _KbHit(
                repo: repo,
                article: a,
                onTap: widget.onOpenArticle,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<KbArticle> _recent(KnowledgeRepository repo) {
    final list = [...repo.articles];
    list.sort((a, b) {
      int rank(KbArticle x) =>
          x.updated.contains('h') || x.updated.contains('now') ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    return list.take(5).toList();
  }

  Widget _searchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(lucideIcon('search'), size: 19, color: AppColors.inkFaint),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: context.t('knowledge.searchHint'),
                hintStyle: TextStyle(color: AppColors.inkFaint),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _search.clear();
              }),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  lucideIcon('x'),
                  size: 14,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _results(List<KbArticle> matches) {
    if (matches.isEmpty) {
      return HiveEmptyState(
        title: context.t('knowledge.noResultsTitle'),
        message: context.t('knowledge.noResultsMessage'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          '${matches.length} result${matches.length != 1 ? 's' : ''}',
        ),
        const SizedBox(height: 12),
        for (final a in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _KbHit(
              repo: widget.repo,
              article: a,
              onTap: widget.onOpenArticle,
            ),
          ),
      ],
    );
  }

  Widget _spacesGrid(KnowledgeRepository repo) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < KbTokens.bpPhone
            ? 1
            : (c.maxWidth / 260).floor().clamp(1, 4);
        const gap = 14.0;
        final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in repo.spaces)
              SizedBox(
                width: tileW,
                child: _SpaceCard(
                  space: s,
                  count: repo.articleCountInSpace(s.id),
                  onTap: () => widget.onOpenSpace(s.id),
                  onDelete:
                      repo.isPersistedSpace(s.id) &&
                          repo.articleCountInSpace(s.id) == 0
                      ? () => widget.onDeleteSpace(s.id)
                      : null,
                ),
              ),
            SizedBox(
              width: tileW,
              child: _NewSpaceCard(onTap: widget.onNewSpace),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 12,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
      color: AppColors.inkFaint,
    ),
  );
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.space,
    required this.count,
    required this.onTap,
    this.onDelete,
  });
  final KbSpace space;
  final int count;
  final VoidCallback onTap;

  /// When non-null, an empty persisted space — show a delete affordance.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(KbTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: hueSwatch(space.hue)),
              ),
              if (onDelete != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message: context.t('knowledge.deleteSpace'),
                    child: InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(
                        KbTokens.radiusControl,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          lucideIcon('trash-2'),
                          size: 15,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: KbTokens.spaceChipBg(space.hue),
                        borderRadius: BorderRadius.circular(
                          KbTokens.radiusControl,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        lucideIcon(space.icon),
                        size: 22,
                        color: KbTokens.spaceChipText(space.hue),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      space.name,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      space.desc,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t(
                        'knowledge.articleCount',
                        variables: {'count': '$count'},
                      ),
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed "+ New space" tile that closes the spaces grid; opens the create-space
/// dialog.
class _NewSpaceCard extends StatelessWidget {
  const _NewSpaceCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(KbTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            border: Border.all(color: AppColors.hairline2),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                ),
                alignment: Alignment.center,
                child: Icon(
                  lucideIcon('folder-plus'),
                  size: 22,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.t('knowledge.newSpace'),
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KbHit extends StatelessWidget {
  const _KbHit({
    required this.repo,
    required this.article,
    required this.onTap,
  });
  final KnowledgeRepository repo;
  final KbArticle article;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final sp = repo.spaceById(article.spaceId);
    final author = repo.userById(article.authorId);
    final hue = sp?.hue ?? 250;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(KbTokens.radiusCard),
      child: InkWell(
        onTap: () => onTap(article.id),
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: KbTokens.spaceChipBg(hue),
                  borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                ),
                alignment: Alignment.center,
                child: Icon(
                  lucideIcon(article.icon),
                  size: 19,
                  color: KbTokens.spaceChipText(hue),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${sp?.name ?? ''} · ${context.t('knowledge.updatedAgo', variables: {'when': article.updated})} · ${author?.name ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(lucideIcon('eye'), size: 13, color: AppColors.inkFaint),
                  const SizedBox(width: 5),
                  Text(
                    '${article.reads}',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
