part of 'attachments_section.dart';

// ════════════════════════════ Tile ════════════════════════════════════════
class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile.uploading({
    required this.upload,
    required this.onRetry,
    required this.onCancel,
  }) : attachment = null,
       subtitle = '',
       imagePath = null,
       onOpen = null,
       onDownload = null,
       onDelete = null;

  const _AttachmentTile.done({
    required this.attachment,
    required this.subtitle,
    required this.imagePath,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
  }) : upload = null,
       onRetry = null,
       onCancel = null;

  final _Upload? upload;
  final IssueAttachment? attachment;
  final String subtitle;

  /// Relative API download path for [attachment]'s bytes (image thumbnails are
  /// fetched authenticated from it). Null for the uploading tile.
  final String Function(String id)? imagePath;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _hover = false;

  bool get _touch {
    final p = Theme.of(context).platform;
    return p == TargetPlatform.iOS || p == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.upload;
    final att = widget.attachment;
    final name = up?.src.name ?? att!.fileName;
    final size = up?.src.size ?? att!.size;
    final kind = up?.kind ?? kindFromName(att!.fileName, att.contentType);
    final km = kindMeta(kind);
    final showActions = att != null && (_hover || _touch);

    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: _hover ? AppColors.accentLine : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumb / preview.
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(att, kind, km),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _KindTag(label: kindTag(kind, name)),
                  ),
                  if (up != null) _progressOverlay(up),
                ],
              ),
            ),
            // Meta footer.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      up != null ? formatBytes(size) : widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: att != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Stack(
          children: [
            tile,
            if (showActions)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    _TileAction(
                      icon: LucideIcons.download,
                      tooltip: context.t('issues.attachments.download'),
                      onTap: widget.onDownload!,
                    ),
                    const SizedBox(width: 6),
                    _TileAction(
                      icon: LucideIcons.trash2,
                      tooltip: context.t('issues.attachments.remove'),
                      danger: true,
                      onTap: widget.onDelete!,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(IssueAttachment? att, String kind, AttachmentKindMeta km) {
    final glyph = ColoredBox(
      color: AppColors.canvas2,
      child: Center(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: km.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(km.icon, size: 22, color: Colors.white),
        ),
      ),
    );
    if (att == null || !kindHasPreview(kind) || widget.imagePath == null) {
      return glyph;
    }
    // The server-side thumbnail — the picture itself, or a PDF's first page —
    // fetched authenticated (the object store is internal-only). Until it
    // arrives the tile shows the attachment's BlurHash, a blurred version of
    // that very preview, instead of an empty box.
    final path = widget.imagePath!(att.id);
    // Decode at (roughly) the tile's on-screen pixel size, never the source's
    // full resolution: a legacy attachment with no stored thumbnail still serves
    // the original, and a 48 MP photo drawn in a ~168 px tile would otherwise
    // decode into a ~200 MB bitmap and OOM-crash a photo-dense grid. ResizeImage
    // is a no-op when the source is already smaller. 168 dp is the widest tile
    // extent; ×dpr covers the densest screens.
    final cacheW = (168 * MediaQuery.devicePixelRatioOf(context)).round();
    return HivePreviewImage(
      key: ValueKey(path),
      image: ResizeImage(
        ApiImage(path, api: context.read<ApiClient>()),
        width: cacheW,
        allowUpscaling: false,
      ),
      blurHash: att.blurHash,
      fallback: glyph,
    );
  }

  Widget _progressOverlay(_Upload up) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.82),
        ),
        child: Center(
          child: up.failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TileAction(
                          icon: LucideIcons.refreshCw,
                          tooltip: context.t('issues.attachments.retry'),
                          onTap: widget.onRetry!,
                        ),
                        const SizedBox(width: 6),
                        _TileAction(
                          icon: LucideIcons.x,
                          tooltip: context.t('common.cancel'),
                          danger: true,
                          onTap: widget.onCancel!,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('issues.attachments.uploadFailed'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: up.progress <= 0 ? null : up.progress,
                        strokeWidth: 4,
                        backgroundColor: AppColors.hairline,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.accentStrong,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(up.progress * 100).round()}%',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _KindTag extends StatelessWidget {
  const _KindTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF14122D).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            onTap();
          },
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              size: 15,
              color: danger ? AppColors.danger : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════ Chrome ══════════════════════════════════════
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: const BorderSide(color: AppColors.accentLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.paperclip,
                size: 14,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bulk actions of the section header, in the same "…" overflow spot the
/// rest of the app uses. Sits next to the add button and applies to every
/// uploaded file at once.
enum _BulkAction { downloadAll, deleteAll }

class _BulkMenuButton extends StatelessWidget {
  const _BulkMenuButton({
    required this.count,
    required this.busy,
    required this.onDownloadAll,
    required this.onDeleteAll,
  });

  /// Number of uploaded files the actions would touch (shown in the labels).
  final int count;

  /// While the archive is being prepared the button shows a loader and the menu
  /// stays closed — a second request would just re-zip the same files.
  final bool busy;

  final VoidCallback onDownloadAll;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.canvas2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: SizedBox(
          width: 18,
          height: 18,
          child: busy
              ? const Center(child: HiveLoader(size: 14, strokeWidth: 2))
              : Icon(LucideIcons.ellipsis, size: 16, color: AppColors.inkSoft),
        ),
      ),
    );
    if (busy) return button;

    return Tooltip(
      message: context.t('issues.attachments.bulkActions'),
      child: GlassPopupMenu<_BulkAction?>(
        value: null,
        width: 260,
        onSelected: (action) => switch (action) {
          _BulkAction.downloadAll => onDownloadAll(),
          _BulkAction.deleteAll => onDeleteAll(),
          null => null,
        },
        items: [
          GlassMenuItem(
            value: _BulkAction.downloadAll,
            label: context.t(
              'issues.attachments.downloadAll',
              variables: {'count': count},
            ),
            leading: Icon(
              LucideIcons.download,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
          GlassMenuItem(
            value: _BulkAction.deleteAll,
            dividerAbove: true,
            color: AppColors.danger,
            label: context.t(
              'issues.attachments.deleteAll',
              variables: {'count': count},
            ),
            leading: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: AppColors.danger,
            ),
          ),
        ],
        child: button,
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accentSoft.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppColors.accent,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      // Scale the contents down when the zone is shorter than the icon+label
      // stack (e.g. the compact empty dropzone) so the overlay never overflows.
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.5),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.cloudUpload,
                    size: 22,
                    color: AppColors.accentStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('issues.attachments.dropHere'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentStrong,
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

/// A dashed-border rounded box for the empty dropzone (Flutter has no native
/// dashed border, so it is painted).
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppColors.hairline,
        radius: AppTheme.radiusCard,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
