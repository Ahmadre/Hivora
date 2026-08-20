import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart' show ApiFailure;
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/markdown_toolbar.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/repositories/media_repository.dart';
import '../../../core/util/file_pick.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassErrorToast, showGlassToast;

/// Composer "+" actions. Camera & gallery insert an inline Markdown image into
/// the comment (the comment body is Markdown, exactly like the issue/KB
/// editors); "Anhang" uploads any file — including video, PDF, etc. — as an
/// issue attachment (the comment model itself is text-only, so files ride on
/// the issue's attachment list, which already streams updates live).

/// Camera / gallery photo → uploaded as inline Markdown media, then dropped at
/// the caret as `![name](url)` (placeholder swaps in when the upload returns).
Future<void> insertCommentPhoto(
  BuildContext context,
  MarkdownEditingActions actions,
  ImageSource source,
) async {
  final mediaApi = context.read<MediaRepository>();

  // Where the gallery is only a file dialog anyway — Linux — take the seam's
  // dialog instead of image_picker's. Both end up in the same GTK chooser, but
  // image_picker_linux passes a hard-coded English `Images` filter and no
  // accept-button text, so this entry showed `_Open` on a German desktop one
  // row above an "Anhang" entry showing `Öffnen`. See [galleryIsAFileDialog].
  final file = source == ImageSource.gallery && galleryIsAFileDialog()
      ? await _pickPhotoFromDisk(context)
      : await _shootOrBrowse(context, source);
  if (file == null) return;

  // Comments store the image as `![name](url)`, so the upload is always by
  // bytes — there is no attachment record to stream a path into.
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return;
  final name = file.name.isNotEmpty ? file.name : 'photo.jpg';
  final multipart = MultipartFile.fromBytes(bytes, filename: name);

  final token = actions.beginImageUpload(name);
  try {
    final upload = await mediaApi.uploadMedia(multipart);
    actions.completeImageUpload(token, upload.url, name);
  } on ApiFailure catch (e) {
    actions.failImageUpload(token);
    if (context.mounted) showGlassErrorToast(context, context.t(e.message));
  } catch (_) {
    actions.failImageUpload(token);
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }
}

/// The camera — and, everywhere with a real photo library, the gallery too.
Future<ChosenFile?> _shootOrBrowse(
  BuildContext context,
  ImageSource source,
) async {
  final XFile? shot;
  try {
    shot = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2400,
    );
  } catch (e) {
    // A cancelled pick comes back as null, never as a throw, and the desktop
    // camera delegate reports its own failures — so anything landing here is
    // unexpected and must not vanish (that is what made the Windows camera
    // entry look like a dead button).
    debugPrint('pickImage failed: $e');
    if (context.mounted) {
      showGlassErrorToast(context, context.t('camera.failed'));
    }
    return null;
  }
  // Null means the user backed out, or the delegate already explained itself.
  if (shot == null) return null;
  return describeChosenFile(shot, true);
}

/// The gallery on a platform whose gallery is a file dialog (Linux).
Future<ChosenFile?> _pickPhotoFromDisk(BuildContext context) async {
  final List<ChosenFile> picked;
  try {
    // `withData` earns its read here, unlike the editor's image button: the
    // bytes are what gets uploaded.
    picked = await pickFilesToUpload(
      context,
      kind: FilePickKind.image,
      withData: true,
    );
  } catch (_) {
    // A dialog that never opened used to end here in silence, which reads as a
    // dead menu entry.
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.filePickFailed'));
    }
    return null;
  }
  // An empty list means cancelled — nothing to report.
  return picked.isEmpty ? null : picked.first;
}

/// "Anhang" → pick any file and upload it as an attachment on the issue. Shows
/// a brief "uploading" toast; the issue's attachments section refreshes live.
Future<void> attachFileToIssue(
  BuildContext context,
  String issueId, {
  VoidCallback? onChanged,
}) async {
  final issueApi = context.read<IssueRepository>();

  final List<ChosenFile> picked;
  try {
    // Web has no file paths, so we always need the bytes there.
    picked = await pickFilesToUpload(context, withData: kIsWeb);
  } catch (_) {
    // A dialog that never opened used to end here in silence, which reads as a
    // dead menu entry.
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.filePickFailed'));
    }
    return;
  }
  // An empty list means cancelled — nothing to report.
  if (picked.isEmpty) return;
  final file = picked.first;

  MultipartFile multipart;
  if (!kIsWeb && (file.path?.isNotEmpty ?? false)) {
    multipart = await MultipartFile.fromFile(file.path!, filename: file.name);
  } else if (file.bytes != null) {
    multipart = MultipartFile.fromBytes(file.bytes!, filename: file.name);
  } else {
    return;
  }

  if (context.mounted) {
    showGlassToast(context, context.t('comments.attaching'));
  }
  try {
    await issueApi.uploadAttachment(issueId, multipart);
    onChanged?.call();
    if (context.mounted) {
      showGlassToast(
        context,
        context.t('comments.attached'),
        kind: GlassToastKind.success,
      );
    }
  } on ApiFailure catch (e) {
    if (context.mounted) showGlassErrorToast(context, context.t(e.message));
  } catch (_) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }
}
