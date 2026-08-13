import 'package:flutter/widgets.dart';

import '../../core/models/work_models.dart';
import '../../core/widgets/hive_widgets.dart' show stateLabel;
import 'data/knowledge_models.dart' show KbArticle, typeMeta;
import 'data/knowledge_repository.dart';
import 'knowledge_tokens.dart';
import 'markdown/smart_link_resolver.dart';

/// [SmartLinkResolver] for the KB reader and editor. Articles and people come
/// from the seed [KnowledgeRepository]; **issues resolve against the real
/// backend** (a pre-loaded `readableId → Issue` map), so an article links and
/// opens genuine issues — not generated demo data.
///
/// Keeps issues in the synchronous [mentions] list (it already holds the map),
/// so it inherits [asyncIssueMentions] = false from the base.
class KnowledgeLinkResolver extends SmartLinkResolver {
  KnowledgeLinkResolver({
    required this.repo,
    required this.issuesByReadable,
    required this.stateColorFor,
    required this.nameFor,
    required this.onOpenArticle,
    required this.onOpenIssue,
    this.onOpenUser,
  });

  final KnowledgeRepository repo;

  /// Real backend issues keyed by readable id (e.g. `HIV-208`).
  final Map<String, Issue> issuesByReadable;
  final Color Function(String state) stateColorFor;
  final String? Function(String? userId) nameFor;
  final void Function(String articleId) onOpenArticle;
  final void Function(String readableId) onOpenIssue;
  final void Function(String userId)? onOpenUser;

  @override
  SmartIssue? issue(String id) {
    final it = issuesByReadable[id];
    if (it == null) return null;
    return smartIssueFromReal(it, stateColorFor, nameFor);
  }

  @override
  SmartDoc? doc(String id) {
    final a = repo.articleById(id);
    if (a == null) return null;
    return smartDocFromArticle(repo, a);
  }

  @override
  SmartPerson? person(String id) {
    final u = repo.userById(id);
    if (u == null) return null;
    return SmartPerson(id: u.id, name: u.name, subtitle: u.title);
  }

  @override
  void openIssue(String id) => onOpenIssue(id);

  @override
  void openDoc(String id) => onOpenArticle(id);

  @override
  void openPerson(String id) => onOpenUser?.call(id);

  @override
  List<MentionCandidate> mentions(String query, {required bool commentMode}) {
    final q = query.toLowerCase();
    final res = <MentionCandidate>[];

    void addArticles() {
      for (final a in repo.articles) {
        final sp = repo.spaceById(a.spaceId);
        final hay = '${a.title} ${sp?.name ?? ''}'.toLowerCase();
        if (q.isEmpty || hay.contains(q)) {
          res.add(
            MentionCandidate(
              kind: 'doc',
              id: a.id,
              title: a.title,
              sub: sp?.name ?? '',
              icon: a.icon,
            ),
          );
        }
      }
    }

    void addIssues() {
      for (final it in issuesByReadable.values) {
        final hay = '${it.readableId} ${it.title}'.toLowerCase();
        if (q.isEmpty || hay.contains(q)) {
          final tm = typeMeta(it.type);
          res.add(
            MentionCandidate(
              kind: 'issue',
              id: it.readableId,
              title: it.title,
              sub: it.readableId,
              issueType: tm.icon,
              issueColor: KbTokens.issueChipColor(tm.hue),
            ),
          );
        }
      }
    }

    if (commentMode) {
      addArticles();
      addIssues();
    } else {
      addIssues();
      addArticles();
    }
    for (final u in repo.users) {
      if (q.isEmpty || u.name.toLowerCase().contains(q)) {
        res.add(
          MentionCandidate(kind: 'user', id: u.id, title: u.name, sub: u.title),
        );
      }
    }
    return res;
  }
}

// ── shared mappers (used by both KB and issue-detail resolvers) ──

// Real priorities → display label + kebab lucide glyph (the KB chip family).
const Map<String, (String, String)> _realPriority = {
  'SHOWSTOPPER': ('Showstopper', 'chevrons-up'),
  'CRITICAL': ('Critical', 'chevrons-up'),
  'MAJOR': ('Major', 'chevron-up'),
  'NORMAL': ('Normal', 'equal'),
  'MINOR': ('Minor', 'chevron-down'),
  'TRIVIAL': ('Trivial', 'chevrons-down'),
};

/// Builds a display-ready [SmartIssue] from a real backend [Issue]. [stateColorFor]
/// supplies the workflow-state colour; [nameFor] resolves the assignee's name.
SmartIssue smartIssueFromReal(
  Issue it,
  Color Function(String state) stateColorFor,
  String? Function(String? userId) nameFor,
) {
  final tm = typeMeta(it.type);
  final pri =
      _realPriority[it.priority.toUpperCase()] ?? (it.priority, 'equal');
  return SmartIssue(
    id: it.readableId,
    title: it.title,
    typeIcon: tm.icon,
    typeColor: KbTokens.issueChipColor(tm.hue),
    stateName: stateLabel(it.state),
    stateColor: stateColorFor(it.state),
    priorityLabel: pri.$1,
    priorityIcon: pri.$2,
    assigneeName: nameFor(it.assigneeId),
    tags: it.tags,
  );
}

SmartDoc smartDocFromArticle(KnowledgeRepository repo, KbArticle a) {
  final sp = repo.spaceById(a.spaceId);
  final author = repo.userById(a.authorId);
  return SmartDoc(
    id: a.id,
    title: a.title,
    icon: a.icon,
    spaceName: sp?.name,
    spaceColor: sp == null ? null : KbTokens.spaceChipText(sp.hue),
    authorName: author?.name,
    updated: a.updated,
    reads: a.reads,
    excerpt: kbExcerpt(a.body),
  );
}

/// Plain-text excerpt of a markdown body for the smart-link hover preview.
String kbExcerpt(String body) {
  final cleaned = body
      .replaceAll(RegExp(r'\{\{[^}]+\}\}'), '')
      .replaceAll(RegExp(r'[#>*`|\-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
}
