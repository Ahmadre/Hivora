import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'team_modal_kit.dart';
import 'team_widgets.dart';

/// Add-project modal: attach an existing project or create a new one.
Future<bool?> showAddProjectModal(
  BuildContext context, {
  required Team team,
  required List<Project> available,
  required List<DirectoryUser> leadCandidates,
  required String currentUserId,
}) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<bool>(
    context,
    _AddProjectBody(
      repo: repo,
      team: team,
      available: available,
      leadCandidates: leadCandidates,
      currentUserId: currentUserId,
    ),
  );
}

class _AddProjectBody extends StatefulWidget {
  const _AddProjectBody({
    required this.repo,
    required this.team,
    required this.available,
    required this.leadCandidates,
    required this.currentUserId,
  });

  final TeamRepository repo;
  final Team team;
  final List<Project> available;
  final List<DirectoryUser> leadCandidates;
  final String currentUserId;

  @override
  State<_AddProjectBody> createState() => _AddProjectBodyState();
}

class _AddProjectBodyState extends State<_AddProjectBody> {
  late bool _attachMode = widget.available.isNotEmpty;
  final _selected = <String>{};
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _desc = TextEditingController();
  late int _hue = widget.team.colorHue;
  late String _lead = widget.currentUserId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _desc.dispose();
    super.dispose();
  }

  String get _effectiveKey {
    final typed = _key.text.trim().toUpperCase();
    if (typed.isNotEmpty) return typed;
    final from = _name.text.trim();
    return from.isEmpty
        ? ''
        : from.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _attach() => _run(
    () => widget.repo.attachTeamProjects(widget.team.id, _selected.toList()),
  );

  Future<void> _create() => _run(() async {
    await widget.repo.createTeamProject(
      widget.team.id,
      key: _effectiveKey,
      name: _name.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      color: teamHueHex(_hue),
      leadId: _lead,
    );
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = _attachMode
        ? _selected.isNotEmpty
        : _name.text.trim().isNotEmpty;
    return ModalShell(
      icon: LucideIcons.folderPlus,
      title: context.t('teams.addProjectTitle'),
      subtitle: context.t(
        'teams.addProjectSubtitle',
        variables: {'name': widget.team.name},
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeToggle(
            attachMode: _attachMode,
            onChanged: (v) => setState(() => _attachMode = v),
          ),
          const SizedBox(height: 18),
          if (_attachMode) ..._attachStep(context) else ..._createStep(context),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footer: ModalFooter(
        primaryLabel: _attachMode
            ? context.t(
                'teams.attachCta',
                variables: {'count': '${_selected.length}'},
                count: _selected.length,
              )
            : context.t('teams.createProjectCta'),
        primaryIcon: _attachMode ? LucideIcons.link : LucideIcons.check,
        busy: _busy,
        onPrimary: canSubmit ? (_attachMode ? _attach : _create) : null,
      ),
    );
  }

  List<Widget> _attachStep(BuildContext context) {
    if (widget.available.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            context.t('teams.allProjectsAttached'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < widget.available.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        () {
          final p = widget.available[i];
          final lead = p.leadId != null
              ? widget.leadCandidates
                    .where((u) => u.id == p.leadId)
                    .map((u) => u.displayName.split(' ').first)
                    .cast<String?>()
                    .firstOrNull
              : null;
          return CheckRow(
            selected: _selected.contains(p.id),
            onTap: () => setState(
              () => _selected.contains(p.id)
                  ? _selected.remove(p.id)
                  : _selected.add(p.id),
            ),
            leading: ProjectKeyGlyph(
              label: p.key,
              color: projectHexColor(p.color),
              avatarUrl: p.avatarUrl,
              size: 32,
              radius: 8,
            ),
            title: p.name,
            subtitle: lead != null
                ? context.t('teams.leadName', variables: {'name': lead})
                : null,
          );
        }(),
      ],
    ];
  }

  List<Widget> _createStep(BuildContext context) {
    final color = teamHueColor(_hue);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ProjectKeyGlyph(
            label: _effectiveKey.isEmpty ? 'P' : _effectiveKey,
            color: color,
            size: 52,
            radius: 15,
            fontSize: 14,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(context.t('teams.projectName')),
                TextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: teamFieldDecoration(
                    context,
                    hint: context.t('teams.projectNamePlaceholder'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldLabel(context.t('teams.key')),
                TextField(
                  controller: _key,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  maxLength: 4,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: AppTheme.fontMono),
                  decoration: teamFieldDecoration(context, hint: 'BILL'),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      FieldLabel(context.t('teams.description'), optional: true),
      TextField(
        controller: _desc,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        minLines: 2,
        maxLines: 3,
        decoration: teamFieldDecoration(
          context,
          hint: context.t('teams.projectDescriptionPlaceholder'),
        ),
      ),
      const SizedBox(height: 16),
      FieldLabel(context.t('teams.projectLead')),
      _LeadDropdown(
        candidates: widget.leadCandidates,
        value: _lead,
        currentUserId: widget.currentUserId,
        onChanged: (v) => setState(() => _lead = v),
      ),
      const SizedBox(height: 16),
      FieldLabel(context.t('teams.colorLabel')),
      ColorPicker(hue: _hue, onChanged: (h) => setState(() => _hue = h)),
    ];
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.attachMode, required this.onChanged});

  final bool attachMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          _seg(
            context,
            true,
            LucideIcons.link,
            context.t('teams.attachExisting'),
          ),
          const SizedBox(width: 6),
          _seg(context, false, LucideIcons.plus, context.t('teams.createNew')),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, bool mode, IconData icon, String label) {
    final on = attachMode == mode;
    return Expanded(
      child: Material(
        color: on ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: on ? AppColors.ink : AppColors.inkSoft,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: on ? AppColors.ink : AppColors.inkSoft,
                    ),
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

class _LeadDropdown extends StatelessWidget {
  const _LeadDropdown({
    required this.candidates,
    required this.value,
    required this.currentUserId,
    required this.onChanged,
  });

  final List<DirectoryUser> candidates;
  final String value;
  final String currentUserId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: candidates.any((u) => u.id == value)
              ? value
              : (candidates.isNotEmpty ? candidates.first.id : null),
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          items: [
            for (final u in candidates)
              DropdownMenuItem(
                value: u.id,
                child: Text(
                  u.id == currentUserId
                      ? context.t(
                          'teams.youName',
                          variables: {'name': u.displayName},
                        )
                      : u.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.ink),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
