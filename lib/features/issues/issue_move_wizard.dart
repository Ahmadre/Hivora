import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/issue_move.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/project_picker.dart';
import '../sprint/modals/glass_modal.dart';

/// Moves one or more issues into another project.
///
/// Two steps, mirroring Jira's Move wizard:
///
/// 1. **Target project** — where the issues should go.
/// 2. **Status mapping + review** — an issue's status is a name from *its
///    project's* workflow, so it has to be re-pointed at a status the target
///    project actually defines. The server pre-fills every row (matching by
///    name, then by the semantic hue, then by position) and marks which rows are
///    a free carry-over and which are a real decision; this step also shows what
///    travels along, what detaches, and the id each issue will end up with.
///
/// Returns true when the move went through, so the caller can refresh.
Future<bool?> showIssueMoveWizard(
  BuildContext context, {
  required List<String> issueIds,
  String? currentProjectId,
}) {
  final issueRepo = context.read<IssueRepository>();
  final projectRepo = context.read<ProjectRepository>();
  return showGlassModal<bool>(
    context,
    width: 620,
    builder: (_) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: issueRepo),
        RepositoryProvider.value(value: projectRepo),
      ],
      child: _MoveWizardBody(
        issueIds: issueIds,
        currentProjectId: currentProjectId,
      ),
    ),
  );
}

class _MoveWizardBody extends StatefulWidget {
  const _MoveWizardBody({required this.issueIds, this.currentProjectId});

  final List<String> issueIds;
  final String? currentProjectId;

  @override
  State<_MoveWizardBody> createState() => _MoveWizardBodyState();
}

class _MoveWizardBodyState extends State<_MoveWizardBody> {
  String? _error;

  /// Step 1 selection — a single target project.
  Project? _target;

  MovePreflight? _preflight;
  bool _analysing = false;
  bool _moving = false;

  /// Confirmed source-status → target-status, seeded from the server's
  /// suggestions and overridable per row.
  final Map<String, String> _stateMap = {};

  bool _includeEpicChildren = false;
  bool _keepSprint = true;

  /// Runs (or re-runs) the analysis. Re-run whenever an input the server
  /// reasons about changes — currently the epic-children opt-in, which decides
  /// whether an epic's children travel and therefore which statuses need
  /// mapping at all.
  Future<void> _analyse() async {
    final target = _target?.id;
    if (target == null) return;
    setState(() {
      _analysing = true;
      _error = null;
    });
    try {
      final result = await context.read<IssueRepository>().movePreflight(
        widget.issueIds,
        target,
        includeEpicChildren: _includeEpicChildren,
      );
      if (!mounted) return;
      setState(() {
        _preflight = result;
        _stateMap
          ..clear()
          ..addEntries([
            for (final m in result.stateMappings)
              if (m.suggestedTo != null) MapEntry(m.fromState, m.suggestedTo!),
          ]);
        _analysing = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _move() async {
    final target = _preflight?.targetProject.id;
    if (target == null || _moving) return;
    setState(() {
      _moving = true;
      _error = null;
    });
    try {
      await context.read<IssueRepository>().moveIssues(
        widget.issueIds,
        target,
        stateMap: _stateMap,
        includeEpicChildren: _includeEpicChildren,
        keepSprint: _keepSprint,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _moving = false;
        _error = failure.message;
      });
    }
  }

  /// Every status row must resolve to a target status before the move can run.
  bool get _mappingComplete {
    final preflight = _preflight;
    if (preflight == null) return false;
    return preflight.stateMappings.every(
      (m) => (_stateMap[m.fromState] ?? '').isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preflight = _preflight;
    final onTargetStep = preflight == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.folderInput,
          title: context.t(
            'issues.move.title',
            variables: {'count': '${widget.issueIds.length}'},
          ),
          subtitle: onTargetStep
              ? context.t('issues.move.stepTarget')
              : context.t('issues.move.stepMapping'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: onTargetStep ? _targetStep() : _mappingStep(preflight),
          ),
        ),
        GlassModalFooter(
          confirmLabel: onTargetStep
              ? context.t('common.next')
              : context.t('issues.move.confirm'),
          confirmIcon: onTargetStep
              ? LucideIcons.arrowRight
              : LucideIcons.folderInput,
          busy: _analysing || _moving,
          hint: onTargetStep ? null : _backButton(),
          onConfirm: onTargetStep
              ? (_target == null ? null : _analyse)
              : (_mappingComplete ? _move : null),
        ),
      ],
    );
  }

  Widget _backButton() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _moving ? null : () => setState(() => _preflight = null),
      icon: const Icon(LucideIcons.arrowLeft, size: 15),
      label: Text(context.t('common.back')),
    ),
  );

  // ---- step 1: target project ----

  Widget _targetStep() {
    final target = _target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassField(
          label: context.t('issues.move.targetProject'),
          child: ProjectPickerField(
            projects: [?target],
            placeholderKey: 'projects.picker.chooseOne',
            onTap: _pickTarget,
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorText()],
      ],
    );
  }

  Future<void> _pickTarget(Rect anchor) async {
    final picked = await showProjectPicker(
      context,
      anchorRect: anchor,
      selected: {?_target?.id},
      titleKey: 'issues.move.targetProject',
      multi: false,
      // Moving into the project the issues already live in is a no-op the
      // server rejects — don't offer it.
      excludeProjectId: widget.currentProjectId,
      emptyLabelKey: 'issues.move.noTargets',
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _target = picked.first);
  }

  // ---- step 2: status mapping + review ----

  Widget _mappingStep(MovePreflight preflight) {
    final target = preflight.targetProject;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassField(
          label: context.t('issues.move.statusMapping'),
          trailing: preflight.needsDecision
              ? _Pill(
                  text: context.t('issues.move.needsChoice'),
                  color: AppColors.warning,
                )
              : _Pill(
                  text: context.t('issues.move.allMatched'),
                  color: AppColors.success,
                ),
          child: Column(
            children: [
              for (final mapping in preflight.stateMappings)
                _MappingRow(
                  mapping: mapping,
                  target: target,
                  value: _stateMap[mapping.fromState],
                  options: preflight.targetStates,
                  onChanged: (state) =>
                      setState(() => _stateMap[mapping.fromState] = state),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _options(preflight),
        if (preflight.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          GlassField(
            label: context.t('issues.move.warnings'),
            child: Column(
              children: [
                for (final warning in preflight.warnings)
                  _WarningRow(warning: warning),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        GlassField(
          label: context.t(
            'issues.move.summary',
            variables: {'count': '${preflight.issues.length}'},
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 190),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: preflight.issues.length,
              itemBuilder: (_, i) => _PreviewRow(
                preview: preflight.issues[i],
                nextState: _stateMap[preflight.issues[i].state],
              ),
            ),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorText()],
      ],
    );
  }

  Widget _options(MovePreflight preflight) {
    final hasEpicWarning = preflight.warnings.any(
      (w) => w.code == MoveWarningCode.epicChildrenStay,
    );
    final hasSprintWarning = preflight.warnings.any(
      (w) => w.code == MoveWarningCode.sprintDetached,
    );
    // Only offer a switch when it can actually change the outcome.
    if (!hasEpicWarning && !_includeEpicChildren && !hasSprintWarning) {
      return const SizedBox.shrink();
    }
    return GlassField(
      label: context.t('issues.move.options'),
      child: Column(
        children: [
          if (hasEpicWarning || _includeEpicChildren)
            _OptionRow(
              title: context.t('issues.move.takeEpicChildren'),
              subtitle: context.t('issues.move.takeEpicChildrenHint'),
              value: _includeEpicChildren,
              // Re-analyse: whether the children travel changes which issues
              // move and therefore which statuses need mapping.
              onChanged: _analysing
                  ? null
                  : (v) {
                      setState(() => _includeEpicChildren = v);
                      _analyse();
                    },
            ),
          if (hasSprintWarning)
            _OptionRow(
              title: context.t('issues.move.keepSprint'),
              subtitle: context.t('issues.move.keepSprintHint'),
              value: _keepSprint,
              onChanged: (v) => setState(() => _keepSprint = v),
            ),
        ],
      ),
    );
  }

  Widget _errorText() => Text(
    context.t(_error!),
    style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
  );
}

// ─────────────────────────── rows ─────────────────────────────────────────

/// One "from → to" status row. An unmatched status is tinted amber, because
/// that is the row the user has to think about.
class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.mapping,
    required this.target,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final MoveStateMapping mapping;
  final Project target;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final unmatched = !mapping.existsInTarget;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(child: StateDotBadge(state: mapping.fromState)),
                if (mapping.issueCount > 1) ...[
                  const SizedBox(width: 6),
                  Text(
                    '×${mapping.issueCount}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            LucideIcons.arrowRight,
            size: 15,
            color: unmatched ? AppColors.warning : AppColors.inkFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassPopupMenu<String>(
              // Empty sentinel until a status is picked — it simply matches no
              // item, so no row is shown as selected.
              value: value ?? '',
              width: 240,
              onSelected: onChanged,
              items: [
                for (final state in options)
                  GlassMenuItem(
                    value: state,
                    label: state,
                    leading: _StateDot(hue: target.hueForState(state)),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(
                    color: unmatched
                        ? AppColors.warning.withValues(alpha: 0.55)
                        : AppColors.hairline,
                  ),
                ),
                child: Row(
                  children: [
                    _StateDot(
                      hue: value == null ? null : target.hueForState(value!),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value ?? context.t('issues.move.chooseStatus'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 15,
                      color: AppColors.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({this.hue});

  final int? hue;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: hue != null ? hueColor(hue!) : AppColors.inkFaint,
      shape: BoxShape.circle,
    ),
  );
}

/// One issue's before → after, including the id it will carry in the target.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.preview, this.nextState});

  final MovePreview preview;
  final String? nextState;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          if (preview.pulledIn) ...[
            Tooltip(
              message: context.t('issues.move.pulledIn'),
              child: Icon(
                LucideIcons.cornerDownRight,
                size: 13,
                color: AppColors.inkFaint,
              ),
            ),
            const SizedBox(width: 6),
          ],
          IdMono(preview.readableId, fontSize: 11.5),
          const SizedBox(width: 6),
          Icon(LucideIcons.arrowRight, size: 12, color: AppColors.inkFaint),
          const SizedBox(width: 6),
          IdMono(preview.nextReadableId, fontSize: 11.5),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              preview.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          if (nextState != null) ...[
            const SizedBox(width: 8),
            StateDotBadge(state: nextState!),
          ],
        ],
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning});

  final MoveWarning warning;

  @override
  Widget build(BuildContext context) {
    final variables = {
      'issue': warning.readableId ?? '',
      'detail': warning.detail ?? '',
    };
    final text = switch (warning.code) {
      MoveWarningCode.sprintDetached => context.t(
        'issues.move.warn.sprint',
        variables: variables,
      ),
      MoveWarningCode.parentDetached => context.t(
        'issues.move.warn.parent',
        variables: variables,
      ),
      MoveWarningCode.epicChildrenStay => context.t(
        'issues.move.warn.epicChildren',
        variables: variables,
      ),
      MoveWarningCode.assigneeNotMember => context.t(
        'issues.move.warn.assignee',
        variables: variables,
      ),
      MoveWarningCode.unknown => context.t('issues.move.warn.generic'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              LucideIcons.triangleAlert,
              size: 14,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          HiveSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}
