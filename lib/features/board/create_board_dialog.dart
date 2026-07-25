import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart';
import 'project_multi_select.dart';

/// Liquid-Glass "Create board" modal. First asks the board type (Kanban —
/// continuous flow, default; or Scrum — sprint planning), then name + the
/// projects the board spans.
///
/// A board may cover **several** projects — the classic cross-project board
/// ("Vorstand" + "Ersti-Woche" on one wall). The backend has always modelled
/// this ([AgileBoard.projectIds] is a list) and merges equivalent workflow
/// states of the spanned projects into shared columns, so picking more than one
/// project here needs nothing further.
///
/// Creates the board and returns it, or null when dismissed.
Future<AgileBoard?> showCreateBoardDialog(
  BuildContext context, {
  required List<Project> projects,
  String? initialProjectId,
}) {
  return showGlassModal<AgileBoard>(
    context,
    width: 560,
    builder: (_) => _CreateBoardBody(
      projects: projects,
      initialProjectId: initialProjectId,
    ),
  );
}

class _CreateBoardBody extends StatefulWidget {
  const _CreateBoardBody({required this.projects, this.initialProjectId});

  final List<Project> projects;
  final String? initialProjectId;

  @override
  State<_CreateBoardBody> createState() => _CreateBoardBodyState();
}

class _CreateBoardBodyState extends State<_CreateBoardBody> {
  final _name = TextEditingController();
  BoardType _type = BoardType.kanban;

  /// Insertion-ordered so the first pick stays the board's template project —
  /// the server derives the default column layout from it and aligns the others.
  late final Set<String> _projectIds = {
    widget.initialProjectId ?? widget.projects.first.id,
  };
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _projectIds.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final board = await context.read<BoardRepository>().createBoard(
        _name.text.trim(),
        _projectIds.toList(),
        type: _type,
      );
      if (mounted) Navigator.of(context).pop(board);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.squareKanban,
          title: context.t('board.newBoard'),
          subtitle: context.t('board.createSub'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassField(
                  label: context.t('board.chooseType'),
                  child: Column(
                    children: [
                      _TypeCard(
                        icon: LucideIcons.columns3,
                        title: context.t('board.typeKanban'),
                        description: context.t('board.typeKanbanDesc'),
                        selected: _type == BoardType.kanban,
                        onTap: () => setState(() => _type = BoardType.kanban),
                      ),
                      const SizedBox(height: 8),
                      _TypeCard(
                        icon: LucideIcons.zap,
                        title: context.t('board.typeScrum'),
                        description: context.t('board.typeScrumDesc'),
                        selected: _type == BoardType.scrum,
                        onTap: () => setState(() => _type = BoardType.scrum),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('board.name'),
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: glassInputDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('board.projectsField'),
                  trailing: Text(
                    context.t(
                      'board.projectsSelected',
                      variables: {'count': '${_projectIds.length}'},
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  child: ProjectMultiSelect(
                    projects: widget.projects,
                    selected: _projectIds,
                    onToggle: (id) => setState(() {
                      if (!_projectIds.remove(id)) _projectIds.add(id);
                    }),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.t(_error!),
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.create'),
          busy: _saving,
          onConfirm: _name.text.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : AppColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.hairline,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : AppColors.canvas2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected ? const Color(0xFF2A2410) : AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                LucideIcons.circleCheckBig,
                size: 20,
                color: AppColors.accentStrong,
              ),
          ],
        ),
      ),
    );
  }
}
