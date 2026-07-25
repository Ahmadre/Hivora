import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../core/api/api_client.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/api/sse_connection.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../search/search_tokens.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassErrorToast, showGlassOptions;
import 'issue_form.dart' show showIssueForm;

part 'issue_links_section.parts.dart';

/// Jira-style "Verknüpfte Vorgänge" panel: the directed relationships between
/// this issue and others (blocks / is blocked by / duplicates / relates to …).
///
/// Shown under the sub-tasks card on the issue detail. Loads its own links,
/// stays live via SSE (a link added on the other end of a relationship appears
/// here in real time), and offers an inline, animated editor to add new links —
/// a relationship-type dropdown on the left and a searchable, multi-select
/// issue field (with selected chips) on the right.
class IssueLinksSection extends StatefulWidget {
  const IssueLinksSection({
    super.key,
    required this.issueId,
    required this.projectId,
    required this.project,
    required this.userNames,
    required this.userAvatars,
    this.onOpenIssue,
    this.onChanged,
  });

  final String issueId;
  final String projectId;

  /// The issue's project — supplies per-project workflow-state colours.
  final Project? project;
  final Map<String, String> userNames;
  final Map<String, String?> userAvatars;

  /// Opens a linked issue (by readable id) — reuses the detail-sheet navigator.
  final void Function(String readableId)? onOpenIssue;

  /// Fired after any link change so the host can refresh dependent surfaces.
  final VoidCallback? onChanged;

  @override
  State<IssueLinksSection> createState() => _IssueLinksSectionState();
}

class _IssueLinksSectionState extends State<IssueLinksSection> {
  IssueRepository get _repo => context.read<IssueRepository>();

  List<IssueLink> _links = const [];
  bool _loading = true;
  bool _adding = false;
  bool _loadError = false;

  // SSE live sync (mirrors AttachmentsSection): a payload-free `changed` ping
  // triggers a re-fetch; the shared [SseConnection] adds heartbeat-driven
  // liveness detection and reconnect-with-catch-up.
  late final SseConnection _sse = SseConnection(
    open: (cancelToken) =>
        _repo.issueLinkEventStream(widget.issueId, cancelToken: cancelToken),
    onEvent: (_) => _load(),
    onReconnect: _load,
  );

  @override
  void initState() {
    super.initState();
    _load();
    _sse.start();
  }

  @override
  void dispose() {
    _sse.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final links = await _repo.issueLinks(widget.issueId);
      if (mounted) {
        setState(() {
          _links = links;
          _loading = false;
          _loadError = false;
        });
      }
    } on ApiFailure {
      // Surface the failure instead of rendering as an empty (no-links) panel —
      // a transient fetch error is indistinguishable from "no links" otherwise.
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  // ── mutations ──────────────────────────────────────────────────────────────
  Future<void> _submit(IssueLinkOption option, List<String> targetIds) async {
    try {
      final links = await _repo.addIssueLinks(
        widget.issueId,
        type: option.type,
        outward: option.outward,
        targetIds: targetIds,
      );
      if (mounted) {
        setState(() {
          _links = links;
          _adding = false;
        });
      }
      widget.onChanged?.call();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }

  Future<void> _remove(IssueLink link) async {
    // Optimistic removal — the SSE ping / returned list reconciles truth.
    final previous = _links;
    setState(
      () => _links = [
        for (final l in _links)
          if (l.id != link.id) l,
      ],
    );
    try {
      final links = await _repo.deleteIssueLink(widget.issueId, link.id);
      if (mounted) setState(() => _links = links);
      widget.onChanged?.call();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _links = previous);
      _toast(failure.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    showGlassErrorToast(context, context.t(message));
  }

  /// Links already present, so the picker can hint they're connected and the
  /// editor can avoid offering an exact duplicate of the selected relationship.
  Set<String> get _linkedIssueIds => {for (final l in _links) l.issue.id};

  /// Groups links by their relationship (type + direction) in the canonical
  /// [kIssueLinkOptions] order, so the sections always read blocks → is blocked
  /// by → clones → … Grouping on the i18n key rather than the server's English
  /// verb keeps the groups stable in every language. A type the app doesn't
  /// know yet still gets its own group, appended at the end.
  List<MapEntry<String, List<IssueLink>>> get _grouped {
    final byKey = <String, List<IssueLink>>{};
    for (final link in _links) {
      byKey.putIfAbsent(link.verbKey, () => []).add(link);
    }
    final ordered = <MapEntry<String, List<IssueLink>>>[];
    for (final opt in kIssueLinkOptions) {
      final group = byKey.remove(opt.verbKey);
      if (group != null) ordered.add(MapEntry(opt.verbKey, group));
    }
    ordered.addAll(byKey.entries);
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final hasLinks = _links.isNotEmpty;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('issues.links.title'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (hasLinks)
                Text(
                  '${_links.length}',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: HiveLoader(size: 16),
            )
          else if (_loadError && _links.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 15,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.t('issues.links.loadFailed'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _loading = true);
                      _load();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.stTodo,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: Text(context.t('common.retry')),
                  ),
                ],
              ),
            )
          else ...[
            for (final group in _grouped) ...[
              const SizedBox(height: 12),
              _LinkGroup(
                verbKey: group.key,
                links: group.value,
                project: widget.project,
                userNames: widget.userNames,
                userAvatars: widget.userAvatars,
                onOpen: widget.onOpenIssue,
                onRemove: _remove,
              ),
            ],
            const SizedBox(height: 6),
            // Animated transform: the text-only "add" button morphs into the
            // inline link editor and back.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(sizeFactor: anim, child: child),
                ),
                child: _adding
                    ? _LinkEditor(
                        key: const ValueKey('editor'),
                        projectId: widget.projectId,
                        issueId: widget.issueId,
                        linkedIssueIds: _linkedIssueIds,
                        project: widget.project,
                        onSubmit: _submit,
                        onCancel: () => setState(() => _adding = false),
                      )
                    : Align(
                        key: const ValueKey('button'),
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _adding = true),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.stTodo,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: Text(context.t('issues.links.add')),
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
