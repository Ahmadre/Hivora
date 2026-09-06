import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/sse.dart';
import '../../core/events/board_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/deletion_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart' show showGlassModal;
import '../teams/team_modal_kit.dart' show ModalShell, ModalFooter, FieldLabel;
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

// ════════════════════════════════════════════════════════════════════════
//  Cascading-delete flow for boards, projects and teams. A single Liquid-Glass
//  modal that (1) warns about everything the delete touches — sourced from the
//  server's deletion-impact endpoint — (2) for a project that still has issues,
//  lets the user choose to delete or migrate them, and (3) streams live progress
//  over SSE while the server performs the cascade.
// ════════════════════════════════════════════════════════════════════════

/// Deletes a board (and its sprints). Issues are kept and detached. Returns
/// `true` when the board was deleted.
Future<bool?> showDeleteBoardFlow(
  BuildContext context, {
  required String boardId,
  required String boardName,
}) async {
  final deleted = await _show(
    context,
    _DeleteFlow(
      icon: LucideIcons.squareKanban,
      titleKey: 'delete.board.title',
      subtitleKey: 'delete.board.subtitle',
      confirmName: boardName,
      loadImpact: () => context
          .read<BoardRepository>()
          .boardDeletionImpact(boardId)
          .then(_boardImpact),
      openStream: (_, cancel) => context
          .read<BoardRepository>()
          .boardDeleteStream(boardId, cancelToken: cancel),
    ),
  );
  // Announced here rather than in the repository, as the other board mutations
  // are: a delete is a *stream* the server writes as it cascades, and only the
  // flow that reads it to the end knows the board is really gone.
  if (deleted == true) BoardEvents.instance.notifyChanged();
  return deleted;
}

/// Deletes a project, cascading to its boards/sprints/articles and (per the
/// user's choice) deleting or migrating its issues. Returns `true` when deleted.
Future<bool?> showDeleteProjectFlow(
  BuildContext context, {
  required String projectId,
  required String projectName,
}) {
  return _show(
    context,
    _DeleteFlow(
      icon: LucideIcons.folder,
      titleKey: 'delete.project.title',
      subtitleKey: 'delete.project.subtitle',
      confirmName: projectName,
      loadImpact: () => context
          .read<ProjectRepository>()
          .projectDeletionImpact(projectId)
          .then(_projectImpact),
      openStream: (choice, cancel) =>
          context.read<ProjectRepository>().projectDeleteStream(
            projectId,
            strategy: choice.strategy,
            migrateToProjectId: choice.targetId,
            cancelToken: cancel,
          ),
    ),
  );
}

/// Deletes a team. Projects/boards/issues survive; members lose team access.
/// Returns `true` when the team was deleted.
Future<bool?> showDeleteTeamFlow(
  BuildContext context, {
  required String teamId,
  required String teamName,
}) {
  return _show(
    context,
    _DeleteFlow(
      icon: LucideIcons.users,
      titleKey: 'delete.team.title',
      subtitleKey: 'delete.team.subtitle',
      confirmName: teamName,
      loadImpact: () => context
          .read<TeamRepository>()
          .teamDeletionImpact(teamId)
          .then(_teamImpact),
      openStream: (_, cancel) => context
          .read<TeamRepository>()
          .teamDeleteStream(teamId, cancelToken: cancel),
    ),
  );
}

Future<bool?> _show(BuildContext context, _DeleteFlow flow) =>
    showGlassModal<bool>(
      context,
      width: 480,
      // A delete confirmation is three lines; a full-width sheet overstates it.
      adaptive: false,
      builder: (_) => flow,
    );

// ── impact → view model ─────────────────────────────────────────────────────

/// One warning line in the confirmation list.
class _Warn {
  const _Warn(this.icon, this.key, [this.vars = const {}]);
  final IconData icon;
  final String key; // i18n key
  final Map<String, dynamic> vars;
}

/// Normalized impact the modal renders, independent of the entity type.
class _Impact {
  const _Impact({
    required this.warnings,
    this.needsIssueChoice = false,
    this.migrationTargets = const [],
    this.issueCount = 0,
  });

  final List<_Warn> warnings;

  /// True for a project that still has issues — the user must choose delete vs
  /// migrate before the delete can run.
  final bool needsIssueChoice;
  final List<MigrationTarget> migrationTargets;
  final int issueCount;
}

_Impact _boardImpact(BoardDeletionImpact i) => _Impact(
  warnings: [
    if (i.sprints > 0)
      _Warn(LucideIcons.calendarRange, 'delete.board.warnSprints', {
        'count': i.sprints,
      }),
    _Warn(LucideIcons.shieldCheck, 'delete.board.warnIssuesKept', {
      'count': i.affectedIssues,
    }),
  ],
);

_Impact _projectImpact(ProjectDeletionImpact i) => _Impact(
  needsIssueChoice: i.hasIssues,
  migrationTargets: i.migrationTargets,
  issueCount: i.issues,
  warnings: [
    if (i.boards > 0)
      _Warn(LucideIcons.squareKanban, 'delete.project.warnBoards', {
        'count': i.boards,
        'sprints': i.sprints,
      }),
    if (i.sharedBoards > 0)
      _Warn(LucideIcons.unlink, 'delete.project.warnSharedBoards', {
        'count': i.sharedBoards,
      }),
    if (i.teams > 0)
      _Warn(LucideIcons.users, 'delete.project.warnTeams', {'count': i.teams}),
    if (i.articles > 0)
      _Warn(LucideIcons.fileText, 'delete.project.warnArticles', {
        'count': i.articles,
      }),
  ],
);

_Impact _teamImpact(TeamDeletionImpact i) => _Impact(
  warnings: [
    _Warn(LucideIcons.userX, 'delete.team.warnAccess', {
      'members': i.members,
      'projects': i.projects,
      'boards': i.boards,
      'issues': i.issues,
    }),
    const _Warn(LucideIcons.shieldCheck, 'delete.team.warnKept'),
  ],
);

/// The user's choice for a project's issues.
class _Choice {
  IssueStrategy? strategy;
  String? targetId;
}

// ── the modal body ──────────────────────────────────────────────────────────

class _DeleteFlow extends StatefulWidget {
  const _DeleteFlow({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.confirmName,
    required this.loadImpact,
    required this.openStream,
  });

  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final String confirmName;
  final Future<_Impact> Function() loadImpact;
  final Future<Stream<List<int>>> Function(_Choice choice, CancelToken cancel)
  openStream;

  @override
  State<_DeleteFlow> createState() => _DeleteFlowState();
}

enum _Stage { loading, confirm, deleting, error }

class _DeleteFlowState extends State<_DeleteFlow> {
  _Stage _stage = _Stage.loading;
  _Impact? _impact;
  String? _error;

  final _confirmCtrl = TextEditingController();
  final _choice = _Choice();

  // progress
  String? _phase;
  double? _fraction;

  CancelToken? _cancel;
  StreamSubscription<SseEvent>? _sub;
  bool _disposed = false;

  /// Set when the server explicitly streamed an `error` frame — distinguishes a
  /// real cascade failure from the transport simply closing the stream.
  bool _serverError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _cancel?.cancel();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final impact = await widget.loadImpact();
      if (!mounted) return;
      setState(() {
        _impact = impact;
        _stage = _Stage.confirm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.t('delete.loadFailed');
        _stage = _Stage.error;
      });
    }
  }

  bool get _nameOk =>
      _confirmCtrl.text.trim().toLowerCase() ==
      widget.confirmName.trim().toLowerCase();

  bool get _issueChoiceOk {
    final impact = _impact;
    if (impact == null || !impact.needsIssueChoice) return true;
    if (_choice.strategy == IssueStrategy.delete) return true;
    if (_choice.strategy == IssueStrategy.migrate) {
      return _choice.targetId != null;
    }
    return false; // nothing chosen yet
  }

  bool get _canDelete => _nameOk && _issueChoiceOk;

  Future<void> _startDelete() async {
    setState(() {
      _stage = _Stage.deleting;
      _phase = 'starting';
      _fraction = null;
      _error = null;
    });
    _cancel = CancelToken();
    // Resolve the fallback message before any await so the BuildContext is not
    // used across an async gap.
    final failMsg = context.t('delete.failed');
    try {
      final bytes = await widget.openStream(_choice, _cancel!);
      _sub = parseSse(bytes).listen(
        _onEvent,
        onDone: _onStreamEnded,
        // A transport-level close (dio surfaces the server completing the SSE
        // response as an error on some adapters) is NOT a failure — the cascade
        // runs to completion server-side. Only an explicit server `error` frame
        // counts as a real failure.
        onError: (_) => _onStreamEnded(),
        cancelOnError: true,
      );
    } catch (_) {
      // The request itself never started (validation / auth / connection), so
      // nothing was deleted — surface it.
      _fail(failMsg);
    }
  }

  void _onEvent(SseEvent raw) {
    if (_disposed) return;
    final event = DeleteEvent.tryParse(raw);
    if (event == null) return;
    switch (event.kind) {
      case DeleteEventKind.progress:
        setState(() {
          _phase = event.phase;
          _fraction = event.fraction;
        });
      case DeleteEventKind.done:
        _succeed();
      case DeleteEventKind.error:
        _serverError = true;
        _fail(event.message ?? context.t('delete.failed'));
    }
  }

  // The cascade always completes server-side even if the stream closes before a
  // `done` frame reaches us, so the stream ending (cleanly or via a transport
  // error) is treated as success — unless the server reported an explicit error.
  void _onStreamEnded() {
    if (_disposed || _stage != _Stage.deleting || _serverError) return;
    _succeed();
  }

  void _succeed() {
    if (_disposed) return;
    _sub?.cancel();
    if (mounted) Navigator.of(context).pop(true);
  }

  void _fail(String message) {
    if (_disposed) return;
    _sub?.cancel();
    setState(() {
      _error = message;
      _stage = _Stage.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ModalShell(
      icon: _stage == _Stage.deleting ? LucideIcons.loader : widget.icon,
      iconColor: AppColors.danger,
      iconBg: AppColors.dangerSoft,
      title: context.t(
        widget.titleKey,
        variables: {'name': widget.confirmName},
      ),
      subtitle: context.t(widget.subtitleKey),
      body: switch (_stage) {
        _Stage.loading => const _Centered(child: CircularProgressIndicator()),
        _Stage.deleting => _ProgressBody(phase: _phase, fraction: _fraction),
        _Stage.error => _ErrorBody(message: _error ?? ''),
        _Stage.confirm => _confirmBody(),
      },
      footer: _footer(),
    );
  }

  Widget _footer() {
    return switch (_stage) {
      _Stage.deleting => const SizedBox.shrink(),
      _Stage.loading => const SizedBox.shrink(),
      _Stage.error => ModalFooter(
        primaryLabel: context.t('common.close'),
        primaryIcon: LucideIcons.x,
        onPrimary: () => Navigator.of(context).maybePop(false),
      ),
      _Stage.confirm => ModalFooter(
        primaryLabel: context.t('delete.cta'),
        primaryIcon: LucideIcons.trash2,
        danger: true,
        onPrimary: _canDelete ? _startDelete : null,
      ),
    };
  }

  // ── confirm stage ─────────────────────────────────────────────────────────
  Widget _confirmBody() {
    final impact = _impact!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final warn in impact.warnings) ...[
          _WarnRow(warn: warn),
          const SizedBox(height: 8),
        ],
        if (impact.needsIssueChoice) ...[
          const SizedBox(height: 4),
          _IssueChoice(
            issueCount: impact.issueCount,
            targets: impact.migrationTargets,
            choice: _choice,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 6),
        FieldLabel(
          context.t(
            'delete.confirmLabel',
            variables: {'name': widget.confirmName},
          ),
        ),
        TextField(
          controller: _confirmCtrl,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: _fieldDecoration(hint: widget.confirmName),
        ),
      ],
    );
  }
}

// ── shared sub-widgets ──────────────────────────────────────────────────────

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(child: child),
  );
}

class _WarnRow extends StatelessWidget {
  const _WarnRow({required this.warn});
  final _Warn warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warn.icon, size: 16, color: AppColors.accentStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.t(
                warn.key,
                variables: warn.vars.map((k, v) => MapEntry(k, '$v')),
                count: warn.vars['count'] as int?,
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Delete-vs-migrate selector shown for a project that still has issues.
class _IssueChoice extends StatelessWidget {
  const _IssueChoice({
    required this.issueCount,
    required this.targets,
    required this.choice,
    required this.onChanged,
  });

  final int issueCount;
  final List<MigrationTarget> targets;
  final _Choice choice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(
          context.t(
            'delete.project.issuesLabel',
            variables: {'count': '$issueCount'},
            count: issueCount,
          ),
        ),
        _Option(
          icon: LucideIcons.trash2,
          title: context.t('delete.project.deleteIssues'),
          hint: context.t('delete.project.deleteIssuesHint'),
          selected: choice.strategy == IssueStrategy.delete,
          onTap: () {
            choice.strategy = IssueStrategy.delete;
            choice.targetId = null;
            onChanged();
          },
        ),
        const SizedBox(height: 7),
        _Option(
          icon: LucideIcons.arrowRightLeft,
          title: context.t('delete.project.migrateIssues'),
          hint: targets.isEmpty
              ? context.t('delete.project.migrateNoTargets')
              : context.t('delete.project.migrateIssuesHint'),
          selected: choice.strategy == IssueStrategy.migrate,
          disabled: targets.isEmpty,
          onTap: targets.isEmpty
              ? null
              : () {
                  choice.strategy = IssueStrategy.migrate;
                  onChanged();
                },
        ),
        if (choice.strategy == IssueStrategy.migrate && targets.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final target in targets) ...[
            _TargetRow(
              target: target,
              selected: choice.targetId == target.id,
              onTap: () {
                choice.targetId = target.id;
                onChanged();
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: selected
            ? AppColors.accentSoft
            : AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppColors.accentStrong : AppColors.inkSoft,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final MigrationTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.accentSoft
          : AppColors.surface.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: selected ? AppColors.accentLine : AppColors.hairline2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hex(target.color),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  target.key.isNotEmpty ? target.key[0] : '?',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  target.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: AppColors.accentStrong,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.phase, required this.fraction});
  final String? phase;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final label = phase == null
        ? context.t('delete.phase.starting')
        : context.t('delete.phase.$phase');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.hairline2,
              color: AppColors.accentStrong,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.t('delete.progressNote'),
            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.circleAlert,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
  isDense: true,
  hintText: hint,
  filled: true,
  fillColor: AppColors.surface.withValues(alpha: 0.7),
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
  ),
);

Color _hex(String value) {
  final hex = value.replaceFirst('#', '');
  final full = hex.length == 6 ? 'FF$hex' : hex;
  return Color(int.tryParse(full, radix: 16) ?? 0xFFAEC6F4);
}
