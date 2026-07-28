import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../repositories/media_repository.dart';
import '../i18n/i18n.dart';
import '../../features/sprint/modals/glass_modal.dart' show showGlassErrorToast;
import 'markdown_toolbar.dart';

/// Picks an image, uploads it as inline Markdown media and swaps the caret
/// placeholder for the resolved `![alt](url)`. Shared by every Markdown surface
/// (issue description, issue comments, KB articles) so they behave identically.
///
/// The upload runs while the caret is freed immediately: [MarkdownEditingActions]
/// drops a placeholder at the caret up-front, so the user can keep typing and
/// the image slots in when the server returns its URL.
Future<void> pickAndInsertMarkdownImage(
  BuildContext context,
  MarkdownEditingActions actions,
) async {
  final repo = context.read<MediaRepository>();

  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      // Web has no file path, so we always need the bytes; harmless elsewhere.
      withData: true,
    );
  } catch (_) {
    picked = null;
  }
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.first;
  final name = file.name;

  MultipartFile multipart;
  if (!kIsWeb && (file.path?.isNotEmpty ?? false)) {
    // dio infers the content type from the file-name extension (same as the
    // attachment upload path); the server re-validates it is a real image.
    multipart = await MultipartFile.fromFile(file.path!, filename: name);
  } else if (file.bytes != null) {
    multipart = MultipartFile.fromBytes(file.bytes!, filename: name);
  } else {
    return;
  }

  final token = actions.beginImageUpload(name);
  try {
    final url = await repo.uploadMedia(multipart);
    actions.completeImageUpload(token, url, name);
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
