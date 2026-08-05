import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart' show ApiFailure;
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/markdown_toolbar.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/repositories/media_repository.dart';
import '../../moderation/content_refused_dialog.dart';
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

  XFile? shot;
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
    return;
  }
  // Null means the user backed out, or the delegate already explained itself.
  if (shot == null) return;

  final bytes = await shot.readAsBytes();
  if (bytes.isEmpty) return;
  final name = shot.name.isNotEmpty ? shot.name : 'photo.jpg';
  final multipart = MultipartFile.fromBytes(bytes, filename: name);

  final token = actions.beginImageUpload(name);
  try {
    final url = await mediaApi.uploadMedia(multipart);
    actions.completeImageUpload(token, url, name);
  } on ApiFailure catch (e) {
    // The placeholder is marked failed, not removed, so the comment the user is
    // writing keeps its shape while the dialog explains the refusal.
    actions.failImageUpload(token);
    if (context.mounted && !handleContentRefusal(context, e)) {
      showGlassErrorToast(context, context.t(e.message));
    }
  } catch (_) {
    actions.failImageUpload(token);
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }
}

/// "Anhang" → pick any file and upload it as an attachment on the issue. Shows
/// a brief "uploading" toast; the issue's attachments section refreshes live.
Future<void> attachFileToIssue(
  BuildContext context,
  String issueId, {
  VoidCallback? onChanged,
}) async {
  final issueApi = context.read<IssueRepository>();

  FilePickerResult? picked;
  try {
    // Web has no file paths, so we always need the bytes there.
    picked = await FilePicker.platform.pickFiles(withData: kIsWeb);
  } catch (_) {
    picked = null;
  }
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.first;

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
    // A refused file is a policy decision, not a failed upload — say so.
    if (context.mounted && !handleContentRefusal(context, e)) {
      showGlassErrorToast(context, context.t(e.message));
    }
  } catch (_) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }
}
