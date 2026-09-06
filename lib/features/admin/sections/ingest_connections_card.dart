import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/ingest_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../sprint/modals/glass_modal.dart';
import '../admin_form_helpers.dart';
import 'ingest_connection_editor.dart';

/// E-mail-to-ticket connection management: any number of IMAP mailbox/folder
/// connections, each feeding a different project. Replaces the former single
/// fixed mailbox config.
class IngestConnectionsCard extends StatefulWidget {
  const IngestConnectionsCard({super.key});

  @override
  State<IngestConnectionsCard> createState() => _IngestConnectionsCardState();
}

class _IngestConnectionsCardState extends State<IngestConnectionsCard> {
  AdminRepository get _repo => context.read<AdminRepository>();

  List<IngestConnection> _connections = [];

  /// Resolved project labels ("KEY · Name") per project id, for the tiles.
  final Map<String, IngestProjectOption> _projects = {};
  bool _loading = true;
  String? _errorKey;

  /// The connection whose mailbox is being reprocessed right now (drives the
  /// per-row spinner); null when idle.
  String? _reprocessingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final connections = await _repo.ingestConnections();
      await _resolveProjects(connections);
      if (!mounted) return;
      setState(() {
        _connections = connections;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  /// Best-effort: map the referenced project ids to display options so tiles
  /// can show "KEY · Name" instead of a raw id.
  Future<void> _resolveProjects(List<IngestConnection> connections) async {
    final missing = connections
        .map((c) => c.projectId)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_projects.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    try {
      var page = 0;
      while (missing.isNotEmpty) {
        final result = await _repo.ingestProjectOptions(page: page, size: 100);
        if (result.items.isEmpty) break;
        for (final option in result.items) {
          _projects[option.id] = option;
          missing.remove(option.id);
        }
        page++;
        if (page * 100 >= result.total) break;
      }
    } on ApiFailure {
      // Tiles fall back to the raw id — never block the list on this.
    }
  }

  Future<void> _toggle(IngestConnection connection, bool enabled) async {
    final index = _connections.indexOf(connection);
    setState(() => _connections[index] = connection.copyWith(enabled: enabled));
    try {
      final saved = await _repo.updateIngestConnection(
        connection.copyWith(enabled: enabled),
      );
      if (!mounted) return;
      setState(() => _connections[index] = saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _connections[index] = connection);
      _showError(failure);
    }
  }

  Future<void> _edit([IngestConnection? connection]) async {
    final result = await showIngestConnectionEditor(
      context,
      connection: connection,
      initialProject: connection?.projectId != null
          ? _projects[connection!.projectId]
          : null,
    );
    if (result == null || !mounted) return;
    _projects[result.project.id] = result.project;
    setState(() {
      final index = _connections.indexWhere(
        (c) => c.id == result.connection.id,
      );
      if (index >= 0) {
        _connections[index] = result.connection;
      } else {
        _connections = [..._connections, result.connection];
      }
    });
  }

  Future<void> _delete(IngestConnection connection) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('admin.ingest.deleteTitle'),
      message: context.t(
        'admin.ingest.deleteBody',
        variables: {'name': connection.label},
      ),
      confirmLabel: context.t('common.delete'),
      destructive: true,
      confirmIcon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo.deleteIngestConnection(connection.id!);
      if (!mounted) return;
      setState(
        () => _connections = _connections
            .where((c) => c.id != connection.id)
            .toList(),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _showError(failure);
    }
  }

  Future<void> _reprocess(IngestConnection connection, Rect? anchorRect) async {
    if (_reprocessingId != null) return;
    // Let the admin choose the scope: repair existing tickets only (safe default),
    // or also (re-)create tickets for e-mails that no longer have one. On wide
    // screens this anchors as a popover under the button; on mobile it falls back
    // to a bottom sheet (handled by showGlassOptions).
    final mode = await showGlassOptions<String>(
      context,
      title: context.t('admin.ingest.reprocessTitle'),
      anchorRect: anchorRect,
      options: [
        (
          value: 'existing',
          child: _reprocessModeOption(
            icon: LucideIcons.refreshCw,
            title: context.t('admin.ingest.reprocessExisting'),
            subtitle: context.t('admin.ingest.reprocessExistingHint'),
          ),
        ),
        (
          value: 'full',
          child: _reprocessModeOption(
            icon: LucideIcons.mailPlus,
            title: context.t('admin.ingest.reprocessFull'),
            subtitle: context.t('admin.ingest.reprocessFullHint'),
            emphasis: true,
          ),
        ),
      ],
    );
    if (mode == null || !mounted) return;

    // The create path can resurrect deliberately deleted tickets — confirm it.
    if (mode == 'full') {
      final confirmed = await showGlassConfirm(
        context,
        icon: LucideIcons.triangleAlert,
        title: context.t('admin.ingest.reprocessFullTitle'),
        message: context.t(
          'admin.ingest.reprocessFullBody',
          variables: {'name': connection.label},
        ),
        confirmLabel: context.t('admin.ingest.reprocessFullConfirm'),
        destructive: true,
        confirmIcon: LucideIcons.mailPlus,
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _reprocessingId = connection.id);
    try {
      final result = await _repo.reprocessIngestConnection(
        connection.id!,
        createMissing: mode == 'full',
      );
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(
          'admin.ingest.reprocessDone',
          variables: {
            'scanned': result.scanned,
            'updated': result.updated,
            'created': result.created,
          },
        ),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _showError(failure);
    } finally {
      if (mounted) setState(() => _reprocessingId = null);
    }
  }

  Widget _reprocessModeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    bool emphasis = false,
  }) {
    final tint = emphasis ? AppColors.accentStrong : AppColors.inkSoft;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: tint),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showError(ApiFailure failure) {
    showGlassErrorToast(context, context.t(failure.message));
  }

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      icon: LucideIcons.inbox,
      title: context.t('admin.emailIngest'),
      subtitle: context.t('admin.emailIngestHint'),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: HiveLoader(size: 28)),
          )
        else if (_errorKey != null)
          HiveEmptyState(
            card: false,
            title: context.t(_errorKey!),
            action: OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          )
        else if (_connections.isEmpty)
          HiveEmptyState(
            card: false,
            title: context.t('admin.ingest.emptyTitle'),
            message: context.t('admin.ingest.emptyMessage'),
            action: OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(context.t('admin.ingest.addConnection')),
            ),
          )
        else ...[
          for (final connection in _connections)
            _ConnectionTile(
              connection: connection,
              project: connection.projectId != null
                  ? _projects[connection.projectId]
                  : null,
              busy: _reprocessingId == connection.id,
              onToggle: (v) => _toggle(connection, v),
              onEdit: () => _edit(connection),
              onReprocess: (rect) => _reprocess(connection, rect),
              onDelete: () => _delete(connection),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(context.t('admin.ingest.addConnection')),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.project,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onReprocess,
    required this.onDelete,
  });

  final IngestConnection connection;
  final IngestProjectOption? project;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  /// Receives the reprocess button's global rect so the mode chooser can anchor
  /// as a popover beneath it on wide screens (null → bottom sheet fallback).
  final ValueChanged<Rect?> onReprocess;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final reprocessKey = GlobalKey();
    final enabled = connection.enabled;
    final projectLabel = project != null
        ? '${project!.key} · ${project!.name}'
        : (connection.projectId ?? context.t('admin.ingest.noProject'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled ? AppColors.accentLine : AppColors.hairline2,
        ),
      ),
      child: Row(
        children: [
          HiveSwitch(value: enabled, onChanged: onToggle),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  connection.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: enabled ? AppColors.ink : AppColors.inkSoft,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetaChip(
                      icon: LucideIcons.server,
                      text: '${connection.host}:${connection.port}',
                    ),
                    _MetaChip(
                      icon: LucideIcons.folder,
                      text: connection.folder,
                    ),
                    _MetaChip(
                      icon: LucideIcons.squareKanban,
                      text: projectLabel,
                      color: project != null
                          ? colorFromHex(project!.color)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          _CompactIconButton(
            tooltip: context.t('common.edit'),
            icon: LucideIcons.pencil,
            onPressed: busy ? null : onEdit,
          ),
          if (busy)
            const SizedBox(
              width: 34,
              height: 34,
              child: Center(child: HiveLoader(size: 16, strokeWidth: 2)),
            )
          else
            _CompactIconButton(
              key: reprocessKey,
              tooltip: context.t('admin.ingest.reprocess'),
              icon: LucideIcons.refreshCw,
              onPressed: () {
                final box =
                    reprocessKey.currentContext?.findRenderObject()
                        as RenderBox?;
                final rect = box != null && box.attached
                    ? box.localToGlobal(Offset.zero) & box.size
                    : null;
                onReprocess(rect);
              },
            ),
          _CompactIconButton(
            tooltip: context.t('common.delete'),
            icon: LucideIcons.trash2,
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

/// Tight icon button so the switch plus edit/reprocess/delete actions fit one
/// row without overflowing on narrow (mobile) screens.
class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16, color: AppColors.inkSoft),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? AppColors.inkFaint),
        const SizedBox(width: 4),
        // Flexible so a long value ellipsizes within the row instead of
        // overflowing the wrap line on narrow screens.
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
