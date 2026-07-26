import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/project_picker.dart';
import '../deletion/delete_flows.dart';
import '../sprint/modals/glass_modal.dart';
import 'board_columns_editor.dart';

/// Opens the board management menu (Rename · Delete) as an anchored popover at
/// the trigger and runs the chosen action. Shared by the board overview and the
/// project-boards list so gating, design and flows stay identical. Calls
/// [onChanged] after a rename (or delete, unless [onDeleted] is given). Pass the
/// triggering widget's own [context] (e.g. via a Builder) so the popover anchors
/// to it. Only call when the user may manage the board — the server re-checks.
Future<void> openBoardManageMenu(
  BuildContext context, {
  required AgileBoard board,
  required Future<void> Function() onChanged,
  Future<void> Function()? onDeleted,
}) async {
  final action = await _showAnchoredMenu<String>(
    context,
    width: 240,
    builder: (_) => _BoardMenuBody(boardName: board.name),
  );
  if (!context.mounted || action == null) return;
  if (action == 'rename') {
    final renamed = await _showRenameBoardModal(context, board);
    if (renamed == true) await onChanged();
  } else if (action == 'projects') {
    final changed = await _editBoardProjects(context, board);
    if (changed) await onChanged();
  } else if (action == 'columns') {
    final changed = await showBoardColumnsEditor(context, board);
    if (changed == true) await onChanged();
  } else if (action == 'delete') {
    final deleted = await showDeleteBoardFlow(
      context,
      boardId: board.id,
      boardName: board.name,
    );
    if (deleted == true) await (onDeleted ?? onChanged)();
  }
}

/// Shows [builder] as a popover anchored to [anchorContext]'s widget — below it
/// when there's room, otherwise above — right-aligned to the trigger and clamped
/// to the screen. A transparent barrier dismisses it on outside tap.
Future<T?> _showAnchoredMenu<T>(
  BuildContext anchorContext, {
  required double width,
  required WidgetBuilder builder,
}) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  if (box == null || overlay == null) return Future<T?>.value(null);

  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorSize = box.size;
  final screen = overlay.size;
  const margin = 8.0;
  const estHeight = 168.0;

  final left = (anchor.dx + anchorSize.width - width).clamp(
    margin,
    screen.width - width - margin,
  );
  final belowTop = anchor.dy + anchorSize.height + 6;
  final fitsBelow = belowTop + estHeight <= screen.height - margin;
  final top = fitsBelow
      ? belowTop
      : (anchor.dy - estHeight - 6).clamp(margin, screen.height - margin);

  return showGeneralDialog<T>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(
      anchorContext,
    ).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: _MenuCard(
            fromTop: fitsBelow,
            child: Builder(builder: builder),
          ),
        ),
      ],
    ),
    transitionBuilder: (ctx, anim, _, child) => child,
  );
}

/// Anchored popover card with a soft shadow and a self-contained scale+fade
/// entrance from the trigger corner (no scrim blur — it's a menu, not a modal).
class _MenuCard extends StatefulWidget {
  const _MenuCard({required this.child, required this.fromTop});

  final Widget child;
  final bool fromTop;

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    final card = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x222D2B55),
              blurRadius: 28,
              spreadRadius: -6,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
    return FadeTransition(
      opacity: curve,
      child: AnimatedBuilder(
        animation: curve,
        child: card,
        builder: (_, child) => Transform.scale(
          alignment: widget.fromTop
              ? Alignment.topRight
              : Alignment.bottomRight,
          scale: 0.96 + 0.04 * curve.value,
          child: child,
        ),
      ),
    );
  }
}

/// Compact board action menu content: Rename · Delete.
class _BoardMenuBody extends StatelessWidget {
  const _BoardMenuBody({required this.boardName});

  final String boardName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MenuRow(
          icon: LucideIcons.pencil,
          label: context.t('board.renameBoard'),
          onTap: () => Navigator.of(context).pop('rename'),
        ),
        _MenuRow(
          icon: LucideIcons.folderKanban,
          label: context.t('board.editProjects'),
          onTap: () => Navigator.of(context).pop('projects'),
        ),
        _MenuRow(
          icon: LucideIcons.columns3,
          label: context.t('board.editColumns'),
          onTap: () => Navigator.of(context).pop('columns'),
        ),
        _MenuRow(
          icon: LucideIcons.trash2,
          label: context.t('board.deleteBoard'),
          danger: true,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liquid-Glass "Rename board" modal. Returns true if the board was renamed.
Future<bool?> _showRenameBoardModal(BuildContext context, AgileBoard board) {
  final repo = context.read<BoardRepository>();
  return showGlassModal<bool>(
    context,
    width: 460,
    builder: (_) => RepositoryProvider.value(
      value: repo,
      child: _RenameBoardBody(board: board),
    ),
  );
}

/// Changes which projects a board spans — the surface that turns an existing
/// single-project board into a cross-project one (and back).
///
/// Opens the project picker straight from the menu, anchored where the menu was:
/// choosing projects *is* the whole interaction, so wrapping it in a modal would
/// only add a second layer of chrome around the same list. The picker's own
/// confirm button ends it, and the board is patched from the result.
///
/// Returns whether the span actually changed.
Future<bool> _editBoardProjects(BuildContext context, AgileBoard board) async {
  final box = context.findRenderObject() as RenderBox?;
  final anchor = (box != null && box.hasSize)
      ? box.localToGlobal(Offset.zero) & box.size
      : Rect.zero;
  final picked = await showProjectPicker(
    context,
    anchorRect: anchor,
    selected: {...board.projectIds},
    titleKey: 'board.editProjectsTitle',
  );
  if (picked == null || !context.mounted) return false;

  final ids = [for (final project in picked) project.id];
  final unchanged =
      ids.length == board.projectIds.length &&
      ids.toSet().containsAll(board.projectIds);
  if (ids.isEmpty || unchanged) return false;

  try {
    await context.read<BoardRepository>().updateBoardProjects(board.id, ids);
    return true;
  } on ApiFailure catch (failure) {
    if (context.mounted) {
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
    return false;
  }
}

class _RenameBoardBody extends StatefulWidget {
  const _RenameBoardBody({required this.board});

  final AgileBoard board;

  @override
  State<_RenameBoardBody> createState() => _RenameBoardBodyState();
}

class _RenameBoardBodyState extends State<_RenameBoardBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.board.name,
  );
  bool _busy = false;
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
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BoardRepository>().renameBoard(widget.board.id, name);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.pencil,
          title: context.t('board.renameTitle'),
          subtitle: context.t('board.renameSubtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
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
          confirmLabel: context.t('common.save'),
          busy: _busy,
          onConfirm: _name.text.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}
