import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_image.dart';
import '../../../core/util/file_download.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/preview_image.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/api/sse.dart';
import '../../../core/api/sse_connection.dart';
import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import 'attachment_kind.dart';
import 'attachment_viewer.dart';
import 'upload_source_sheet.dart';

part 'attachments_section.tiles.dart';

/// A picked/dropped source file, abstracting file_picker's `PlatformFile` and
/// desktop_drop's `DropItem` into the bits the upload needs.
class _Src {
  _Src({required this.name, required this.size, this.path, this.bytes});
  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;
}

/// An in-flight (or failed) upload shown optimistically as a tile.
class _Upload {
  _Upload(this.src) : kind = kindFromName(src.name);
  final _Src src;
  final String kind;
  double progress = 0;
  bool failed = false;
  CancelToken cancel = CancelToken();

  String get id => 'up:${identityHashCode(this)}';
}

/// Issue attachments: drag-drop + click upload, a responsive image/file grid
/// with per-tile upload progress, download/remove actions, a Liquid-Glass
/// lightbox, and live sync over SSE. Mirrors `view_attachments.jsx`.
class AttachmentsSection extends StatefulWidget {
  const AttachmentsSection({
    super.key,
    required this.issueId,
    required this.initial,
    this.issueKey,
    this.userNames = const {},
    this.onChanged,
  });

  final String issueId;

  /// Readable issue id (e.g. `HIN-42`), used to name the "download all"
  /// archive. Falls back to a generic name when absent.
  final String? issueKey;

  final List<IssueAttachment> initial;
  final Map<String, String> userNames;
  final VoidCallback? onChanged;

  @override
  State<AttachmentsSection> createState() => AttachmentsSectionState();
}

class AttachmentsSectionState extends State<AttachmentsSection> {
  late List<IssueAttachment> _server = List.of(widget.initial);
  final List<_Upload> _uploads = [];

  bool _dragging = false;
  bool _disposed = false;

  /// True while the "download all" archive is being built + fetched — the bulk
  /// menu shows a loader and stays inert so the request can't be fired twice.
  bool _archiving = false;

  // Live sync over the shared resilient SSE connection: heartbeat-driven
  // liveness detection + reconnect-with-catch-up (see [_reconcile]).
  late final SseConnection _sse = SseConnection(
    open: (cancelToken) =>
        _repo.attachmentEventStream(widget.issueId, cancelToken: cancelToken),
    onEvent: _onSseEvent,
    onReconnect: _reconcile,
  );

  IssueRepository get _repo => context.read<IssueRepository>();

  UploadLimits get _limits {
    try {
      return context.read<AppConfigBloc>().state.meta?.uploadLimits ??
          const UploadLimits();
    } catch (_) {
      return const UploadLimits();
    }
  }

  @override
  void initState() {
    super.initState();
    _sse.start();
  }

  @override
  void dispose() {
    _disposed = true;
    _sse.stop();
    for (final u in _uploads) {
      if (!u.cancel.isCancelled) u.cancel.cancel();
    }
    super.dispose();
  }

  // ── SSE live sync ─────────────────────────────────────────────────────────
  /// Re-fetches the authoritative attachment list after a reconnect so anything
  /// added/removed while the stream was down is reconciled — live frames carry
  /// only deltas (`added`/`removed`), which a dropped connection would miss.
  Future<void> _reconcile() async {
    try {
      final issue = await _repo.issue(widget.issueId);
      if (_disposed || !mounted) return;
      setState(() => _server = List.of(issue.attachments));
    } catch (_) {
      // Keep the current view; the next event or reconnect reconciles.
    }
  }

  void _onSseEvent(SseEvent ev) {
    if (_disposed) return;
    try {
      final data = jsonDecode(ev.data);
      if (ev.event == 'added' && data is Map<String, dynamic>) {
        final att = IssueAttachment.fromJson(data);
        if (!_server.any((a) => a.id == att.id)) {
          setState(() => _server = [..._server, att]);
          widget.onChanged?.call();
        }
      } else if (ev.event == 'removed' && data is Map<String, dynamic>) {
        final id = data['id'] as String?;
        if (id != null && _server.any((a) => a.id == id)) {
          setState(() {
            _server = _server.where((a) => a.id != id).toList();
          });
          widget.onChanged?.call();
        }
      }
    } catch (_) {
      // Malformed frame — ignore, the next event reconciles state.
    }
  }

  // ── Pick / drop / validate ────────────────────────────────────────────────

  /// Whether to offer the native gallery/camera source chooser. Only touch
  /// platforms have a photo library + camera distinct from the file browser;
  /// desktop and web go straight to the document picker.
  bool get _offersMediaSources =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Public entry for external "add attachment" affordances (e.g. the comment
  /// composer's "+" → Anhang). Opens the document picker and uploads through the
  /// *same* optimistic flow as the section's own button — so the new tile shows
  /// up live here without relying on the SSE `added` event (which may not stream
  /// on web) or a full issue reload.
  Future<void> pickFiles() => _pickFiles();

  /// Entry point for every "add" affordance (header button + empty dropzone).
  /// On mobile it asks the user where to source from; elsewhere it opens the
  /// document picker directly.
  Future<void> _add() async {
    if (!_offersMediaSources) {
      await _pickFiles();
      return;
    }
    final source = await showUploadSourceSheet(context);
    if (source == null || _disposed) return;
    switch (source) {
      case UploadSource.gallery:
        await _pickFromGallery();
      case UploadSource.photo:
        await _capture(ImageSource.camera, video: false);
      case UploadSource.video:
        await _capture(ImageSource.camera, video: true);
      case UploadSource.files:
        await _pickFiles();
    }
  }

  /// System document picker (PDF, Office docs, archives, …). Allows any type and
  /// multiple selection; the kind/size/blocked-extension gate runs in [_enqueue].
  Future<void> _pickFiles() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb, // web has no file path; we need the bytes
      );
    } catch (_) {
      if (mounted) _toast(context.t('issues.attachments.pickFailed'));
      return;
    }
    if (result == null || _disposed) return;
    // On web `PlatformFile.path` throws — only the bytes are available there.
    _enqueue([
      for (final f in result.files)
        _Src(
          name: f.name,
          size: f.size,
          path: kIsWeb ? null : f.path,
          bytes: f.bytes,
        ),
    ]);
  }

  /// Photo library: images *and* videos, multi-select.
  Future<void> _pickFromGallery() async {
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultipleMedia();
    } on Exception {
      if (mounted) _toast(context.t('issues.attachments.pickFailed'));
      return;
    }
    if (picked.isEmpty || _disposed) return;
    final srcs = await Future.wait(picked.map(_srcFromXFile));
    if (!_disposed) _enqueue(srcs);
  }

  /// Camera capture — a single new photo or video.
  Future<void> _capture(ImageSource source, {required bool video}) async {
    final XFile? file;
    try {
      file = video
          ? await ImagePicker().pickVideo(source: source)
          : await ImagePicker().pickImage(source: source);
    } on Exception {
      if (mounted) _toast(context.t('issues.attachments.pickFailed'));
      return;
    }
    if (file == null || _disposed) return;
    _enqueue([await _srcFromXFile(file)]);
  }

  /// Adapts an [XFile] (from image_picker) into the upload's [_Src]. On web
  /// there is no usable path, so the bytes are read eagerly; on native the path
  /// is streamed straight from disk by [_multipart].
  Future<_Src> _srcFromXFile(XFile f) async {
    final bytes = kIsWeb ? await f.readAsBytes() : null;
    final size = bytes?.length ?? await f.length();
    return _Src(
      name: f.name,
      size: size,
      path: kIsWeb ? null : f.path,
      bytes: bytes,
    );
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    final srcs = <_Src>[];
    var failed = false;
    for (final item in detail.files) {
      // Read each item independently so one unreadable drop (a folder, a file
      // deleted mid-drag, a permission-denied path) doesn't abort the whole
      // batch — the valid files in the same drop still upload.
      try {
        final len = await item.length();
        final bytes = kIsWeb ? await item.readAsBytes() : null;
        srcs.add(
          _Src(
            name: item.name,
            size: len,
            path: kIsWeb ? null : item.path,
            bytes: bytes,
          ),
        );
      } catch (_) {
        failed = true;
      }
    }
    if (_disposed) return;
    if (srcs.isNotEmpty) _enqueue(srcs);
    if (failed && mounted) {
      _toast(context.t('issues.attachments.pickFailed'));
    }
  }

  void _enqueue(List<_Src> files) {
    if (files.isEmpty) return;
    final limits = _limits;
    final accepted = <_Src>[];
    for (final f in files) {
      if (isBlockedFileName(f.name)) {
        _toast(
          context.t('issues.attachments.blocked', variables: {'name': f.name}),
          kind: GlassToastKind.warning,
        );
        continue;
      }
      if (f.size > limits.maxFileBytes) {
        _toast(
          context.t(
            'issues.attachments.tooLarge',
            variables: {'name': f.name, 'size': limits.maxFileMb},
          ),
          kind: GlassToastKind.warning,
        );
        continue;
      }
      accepted.add(f);
    }
    if (accepted.isEmpty) return;
    if (accepted.length > limits.maxFiles) {
      _toast(
        context.t(
          'issues.attachments.tooManyFiles',
          variables: {'count': limits.maxFiles},
        ),
        kind: GlassToastKind.warning,
      );
      accepted.removeRange(limits.maxFiles, accepted.length);
    }
    final total = accepted.fold<int>(0, (sum, f) => sum + f.size);
    if (total > limits.maxRequestBytes) {
      _toast(
        context.t(
          'issues.attachments.batchTooLarge',
          variables: {'size': limits.maxRequestMb},
        ),
        kind: GlassToastKind.warning,
      );
      return;
    }
    final ups = accepted.map(_Upload.new).toList();
    setState(() => _uploads.insertAll(0, ups));
    for (final u in ups) {
      _startUpload(u);
    }
  }

  Future<void> _startUpload(_Upload u) async {
    try {
      final file = await _multipart(u.src);
      final issue = await _repo.uploadAttachment(
        widget.issueId,
        file,
        cancelToken: u.cancel,
        onProgress: (p) {
          if (!_disposed) setState(() => u.progress = p);
        },
      );
      if (_disposed) return;
      setState(() {
        _server = issue.attachments; // authoritative list (atomic on server)
        _uploads.remove(u);
      });
      widget.onChanged?.call();
      // Confirm success — the new tile may be off-screen (e.g. when uploaded
      // from the comment composer's "+"), so close the loop with a toast.
      if (mounted) {
        _toast(
          context.t('issues.attachments.uploaded'),
          kind: GlassToastKind.success,
        );
      }
    } on ApiFailure catch (e) {
      if (_disposed || !mounted) return;
      setState(() => u.failed = true);
      _toast(context.t(e.message));
    } catch (_) {
      if (_disposed) return;
      setState(() => u.failed = true);
    }
  }

  Future<MultipartFile> _multipart(_Src s) async {
    if (!kIsWeb && (s.path?.isNotEmpty ?? false)) {
      return MultipartFile.fromFile(s.path!, filename: s.name);
    }
    if (s.bytes != null) {
      return MultipartFile.fromBytes(s.bytes!, filename: s.name);
    }
    throw ApiFailure('errors.unexpected');
  }

  void _retry(_Upload u) {
    setState(() {
      u.failed = false;
      u.progress = 0;
      u.cancel = CancelToken();
    });
    _startUpload(u);
  }

  void _cancelUpload(_Upload u) {
    if (!u.cancel.isCancelled) u.cancel.cancel();
    setState(() => _uploads.remove(u));
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  /// Relative API path that streams an attachment's bytes through the
  /// authenticated server endpoint (used for download + inline previews). The
  /// object store is internal-only, so the client never gets a storage URL.
  String _downloadPath(String id) =>
      '/api/v1/issues/${widget.issueId}/attachments/$id/download';

  /// Relative API path of an image attachment's small server-side preview. A
  /// grid of tiles costs one downscaled picture each instead of the originals;
  /// the endpoint falls back to the full image when no thumbnail exists.
  String _thumbnailPath(String id) =>
      '/api/v1/issues/${widget.issueId}/attachments/$id/thumbnail';

  Future<void> _download(IssueAttachment a) =>
      _fetchAndSave(_downloadPath(a.id), a.fileName);

  /// Fetches [path] through the authenticated client and hands the bytes to the
  /// browser / OS share sheet as [fileName]. The bytes go through the server
  /// endpoint because the object store is internal-only — its presigned URLs
  /// aren't reachable from a client.
  Future<void> _fetchAndSave(
    String path,
    String fileName, {
    String? fallbackMime,
  }) async {
    // Capture the iPad share-popover anchor before any async gap (the render
    // object is only valid on the current frame's context).
    final box = context.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final res = await context.read<ApiClient>().getBytes(path);
      if (res == null) {
        if (mounted) _toast(context.t('errors.unexpected'));
        return;
      }
      final outcome = await downloadBytes(
        fileName,
        Uint8List.fromList(res.bytes),
        res.contentType.isEmpty ? (fallbackMime ?? '') : res.contentType,
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      switch (outcome) {
        case DownloadOutcome.browser:
          _toast(
            context.t('issues.attachments.downloadStarted'),
            kind: GlassToastKind.info,
          );
        case DownloadOutcome.failed:
          _toast(context.t('errors.unexpected'));
        // Native: the OS share sheet is the feedback — no toast (and none on a
        // deliberate dismiss).
        case DownloadOutcome.shared:
        case DownloadOutcome.dismissed:
          break;
      }
    } catch (_) {
      if (mounted) _toast(context.t('errors.unexpected'));
    }
  }

  /// "Download all": the server zips every attachment of the issue in one
  /// streamed response, so this stays a single authenticated request instead of
  /// N downloads the browser would block or the share sheet would queue.
  Future<void> _downloadAll() async {
    if (_archiving || _server.isEmpty) return;
    setState(() => _archiving = true);
    _toast(
      context.t('issues.attachments.archivePreparing'),
      kind: GlassToastKind.info,
    );
    // Mirrors the name the server puts in Content-Disposition (the byte fetch
    // doesn't surface response headers).
    final key = widget.issueKey?.trim();
    final archiveName =
        '${key == null || key.isEmpty ? 'issue' : key}'
        '-attachments.zip';
    try {
      await _fetchAndSave(
        _repo.attachmentsArchivePath(widget.issueId),
        archiveName,
        fallbackMime: 'application/zip',
      );
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  /// "Delete all": one bulk call carrying exactly the ids currently on screen,
  /// so an attachment that arrived meanwhile (SSE) is not swept away with them.
  Future<void> _deleteAll() async {
    final targets = List.of(_server);
    if (targets.isEmpty) return;
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t(
        'issues.attachments.deleteAllTitle',
        count: targets.length,
      ),
      message: context.t(
        'issues.attachments.deleteAllBody',
        count: targets.length,
      ),
      confirmLabel: context.t('issues.attachments.remove'),
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (confirmed != true || _disposed || !mounted) return;
    final prev = _server;
    final ids = targets.map((a) => a.id).toSet();
    setState(
      () => _server = _server.where((a) => !ids.contains(a.id)).toList(),
    );
    widget.onChanged?.call();
    try {
      await _repo.deleteAttachments(widget.issueId, ids.toList());
    } on ApiFailure catch (e) {
      if (_disposed || !mounted) return;
      setState(() => _server = prev);
      widget.onChanged?.call();
      _toast(context.t(e.message));
    }
  }

  Future<void> _delete(IssueAttachment a) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: a.fileName,
      message: context.t('issues.attachments.removeConfirm'),
      confirmLabel: context.t('issues.attachments.remove'),
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (confirmed != true || _disposed) return;
    final prev = _server;
    setState(() => _server = _server.where((x) => x.id != a.id).toList());
    widget.onChanged?.call();
    try {
      await _repo.deleteAttachment(widget.issueId, a.id);
    } on ApiFailure catch (e) {
      if (_disposed || !mounted) return;
      setState(() => _server = prev);
      _toast(context.t(e.message));
    }
  }

  /// Opens the full-screen viewer on the tapped file, with *every* attachment
  /// of the issue in the pager — pictures, documents and text alike, in the
  /// order the grid shows them. Paging used to cover the pictures only, so
  /// looking through what is attached meant returning to the grid each time.
  Future<void> _open(IssueAttachment tapped) async {
    final ordered = _server.reversed.toList(); // newest first, like the grid
    final items = [for (final a in ordered) _toViewerItem(a)];
    final idx = ordered.indexWhere((a) => a.id == tapped.id);
    await showAttachmentViewer(
      context,
      items: items,
      initialIndex: idx < 0 ? 0 : idx,
      onDownload: (it) => _downloadById(it.id, it.name),
    );
  }

  Future<void> _downloadById(String id, String name) async {
    final att = _server.firstWhere(
      (a) => a.id == id,
      orElse: () => IssueAttachment(id: id, fileName: name, size: 0),
    );
    await _download(att);
  }

  ViewerItem _toViewerItem(IssueAttachment a) {
    final kind = kindFromName(a.fileName, a.contentType);
    return ViewerItem(
      id: a.id,
      name: a.fileName,
      kind: kind,
      size: a.size,
      // Always the download path: the viewer decides what (if anything) to
      // fetch from the file's type and size, and only ever reads bytes for a
      // stage that can actually render them.
      url: _downloadPath(a.id),
      // Pictures and PDFs have a server-rendered preview to show while the
      // original downloads; nothing else does.
      thumbnailUrl: kindHasPreview(kind) ? _thumbnailPath(a.id) : null,
      blurHash: a.blurHash,
      mime: a.contentType,
      subtitle: _subtitle(a),
    );
  }

  String _subtitle(IssueAttachment a) {
    final parts = <String>[formatBytes(a.size)];
    final by = a.uploaderId == null ? null : widget.userNames[a.uploaderId];
    if (by != null && by.isNotEmpty) parts.add(by);
    if (a.uploadedAt != null) {
      parts.add(relativeAgeLabel(context, a.uploadedAt!.toLocal()));
    }
    return parts.join(' · ');
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.error}) {
    if (!mounted) return;
    showGlassToast(context, message, kind: kind);
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final count = _server.length + _uploads.length;
    final phone = MediaQuery.sizeOf(context).width < 610;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(count),
        const SizedBox(height: 12),
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) {
            setState(() => _dragging = false);
            _onDrop(d);
          },
          child: Stack(
            children: [
              if (count == 0) _empty() else _grid(phone),
              if (_dragging) const Positioned.fill(child: _DropOverlay()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(int count) {
    return Row(
      children: [
        Text(
          context.t('issues.attachments.title').toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkFaint,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.canvas2,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
        const Spacer(),
        // Always-available add affordance (the empty dropzone only shows when
        // there are no attachments yet).
        if (count > 0)
          _AddButton(onTap: _add, label: context.t('issues.attachments.add')),
        // Bulk actions apply to the uploaded files only — in-flight uploads have
        // nothing to download or delete yet.
        if (_server.isNotEmpty) ...[
          const SizedBox(width: 8),
          _BulkMenuButton(
            count: _server.length,
            busy: _archiving,
            onDownloadAll: _downloadAll,
            onDeleteAll: _deleteAll,
          ),
        ],
      ],
    );
  }

  Widget _empty() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: _add,
      child: DottedBorderBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.canvas2,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.paperclip,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('issues.attachments.emptyTitle'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      context.t(
                        'issues.attachments.emptyHint',
                        variables: {'size': _limits.maxFileMb},
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
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

  Widget _grid(bool phone) {
    final extent = phone ? 140.0 : 168.0;
    final mainAxisExtent = (extent * 10 / 16).ceilToDouble() + 56;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: _uploads.length + _server.length,
      itemBuilder: (context, i) {
        if (i < _uploads.length) {
          final u = _uploads[i];
          return _AttachmentTile.uploading(
            upload: u,
            onRetry: () => _retry(u),
            onCancel: () => _cancelUpload(u),
          );
        }
        // Server attachments newest-first below the in-flight uploads.
        final a = _server[_server.length - 1 - (i - _uploads.length)];
        return _AttachmentTile.done(
          attachment: a,
          subtitle: _subtitle(a),
          imagePath: _thumbnailPath,
          onOpen: () => _open(a),
          onDownload: () => _download(a),
          onDelete: () => _delete(a),
        );
      },
    );
  }
}
