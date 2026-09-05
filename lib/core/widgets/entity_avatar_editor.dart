import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../util/file_pick.dart';
import '../theme/app_colors.dart';
import '../../features/account/account_modals.dart'
    show AvatarAction, showAvatarActions;
import '../../features/sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'entity_avatar.dart';
import 'hive_loader.dart';

/// The i18n keys one avatar field needs, so a team and a project can each name
/// the thing they edit without the widget growing seven label parameters.
///
/// Keys, never finished strings: they are resolved with `context.t` inside the
/// widget, after the async gaps that would otherwise make a captured
/// translation go stale on a language switch.
class EntityAvatarStrings {
  const EntityAvatarStrings({
    required this.title,
    required this.subtitle,
    required this.change,
    required this.remove,
    required this.updated,
    required this.removed,
    required this.failed,
  });

  final String title;
  final String subtitle;
  final String change;
  final String remove;
  final String updated;
  final String removed;
  final String failed;

  static const team = EntityAvatarStrings(
    title: 'teams.avatar.title',
    subtitle: 'teams.avatar.subtitle',
    change: 'teams.avatar.change',
    remove: 'teams.avatar.remove',
    updated: 'teams.avatar.updated',
    removed: 'teams.avatar.removed',
    failed: 'teams.avatar.failed',
  );

  static const project = EntityAvatarStrings(
    title: 'projectSettings.avatar.title',
    subtitle: 'projectSettings.avatar.subtitle',
    change: 'projectSettings.avatar.change',
    remove: 'projectSettings.avatar.remove',
    updated: 'projectSettings.avatar.updated',
    removed: 'projectSettings.avatar.removed',
    failed: 'projectSettings.avatar.failed',
  );
}

/// A team's or project's picture as an editable field: the square avatar with a
/// camera badge, tapped to upload a new image or drop the current one.
///
/// The whole pick → upload → toast dance lives here rather than in each
/// settings surface, because it is identical everywhere and easy to get subtly
/// wrong (reading `context` across the upload's async gap, forgetting the busy
/// flag, leaving a failure silent). A caller supplies only the two repository
/// calls and stores the URL it is handed back.
///
/// Uploads take effect immediately and are *not* part of any draft/save bar:
/// the picture is server-owned, so there is nothing to commit later.
class EntityAvatarField extends StatefulWidget {
  const EntityAvatarField({
    super.key,
    required this.avatarUrl,
    required this.fallback,
    required this.strings,
    required this.onUpload,
    required this.onRemove,
    required this.onChanged,
    this.size = 72,
    this.radius = 20,
  });

  /// Current server-owned picture URL, or null while the glyph stands in.
  final String? avatarUrl;

  /// The glyph shown when there is no picture (and while one loads).
  final Widget fallback;

  final EntityAvatarStrings strings;

  /// Uploads the picked file and answers the fresh, cache-busted URL.
  final Future<String> Function(MultipartFile file) onUpload;

  /// Deletes the current picture server-side.
  final Future<void> Function() onRemove;

  /// The new URL after an upload, or null after a removal. Storing it is what
  /// swaps the picture — the changed `?v=` token is a new avatar-cache key.
  final ValueChanged<String?> onChanged;

  final double size;
  final double radius;

  @override
  State<EntityAvatarField> createState() => _EntityAvatarFieldState();
}

class _EntityAvatarFieldState extends State<EntityAvatarField> {
  bool _busy = false;

  Future<void> _edit() async {
    if (_busy) return;
    // Nothing to remove yet — go straight to the file picker instead of
    // opening a chooser with one live option.
    if ((widget.avatarUrl ?? '').isEmpty) {
      await _upload();
      return;
    }
    final action = await showAvatarActions(
      context,
      titleKey: widget.strings.title,
      subtitleKey: widget.strings.subtitle,
      changeKey: widget.strings.change,
      removeKey: widget.strings.remove,
    );
    if (!mounted) return;
    if (action == AvatarAction.change) {
      await _upload();
    } else if (action == AvatarAction.remove) {
      await _remove();
    }
  }

  Future<void> _upload() async {
    final file = await pickImageMultipart(context);
    if (file == null) return;
    if (!mounted) return;

    // Resolve every context-derived value before the upload's async gap.
    final updated = context.t(widget.strings.updated);
    final failed = context.t(widget.strings.failed);

    setState(() => _busy = true);
    try {
      final url = await widget.onUpload(file);
      if (!mounted) return;
      widget.onChanged(url);
      showGlassToast(context, updated, kind: GlassToastKind.success);
    } catch (_) {
      if (mounted) showGlassErrorToast(context, failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final removed = context.t(widget.strings.removed);
    final failed = context.t(widget.strings.failed);

    setState(() => _busy = true);
    try {
      await widget.onRemove();
      if (!mounted) return;
      widget.onChanged(null);
      showGlassToast(context, removed, kind: GlassToastKind.success);
    } catch (_) {
      if (mounted) showGlassErrorToast(context, failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = EntityAvatar(
      avatarUrl: widget.avatarUrl,
      size: widget.size,
      radius: widget.radius,
      fallback: widget.fallback,
    );
    return Semantics(
      button: true,
      label: context.t(widget.strings.title),
      child: GestureDetector(
        onTap: _edit,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                  child: const Center(child: HiveLoader(size: 22)),
                ),
              ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(
                  LucideIcons.camera,
                  size: 12,
                  color: Color(0xFF2A2410),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An image chosen in a *create* dialog, held in memory until the thing it
/// belongs to exists and can be uploaded against.
///
/// Bytes rather than a [MultipartFile], deliberately: a MultipartFile may only
/// be sent once, and a creation can fail and be retried. Keeping the raw bytes
/// means every attempt builds a fresh one — and the same bytes draw the preview.
class PickedImage {
  const PickedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  MultipartFile toMultipart() => MultipartFile.fromBytes(bytes, filename: name);
}

/// Opens the platform image picker and keeps the bytes, for a create dialog
/// that cannot upload yet. Null when nothing usable came back.
Future<PickedImage?> pickImageBytes(BuildContext context) async {
  final List<ChosenFile> picked;
  try {
    // Bytes on every platform here (unlike [pickImageMultipart], which streams
    // from a path off-web): they are needed for the preview either way, and
    // the server caps an avatar at 12 MB, so it is a bounded read.
    picked = await pickFilesToUpload(
      context,
      kind: FilePickKind.image,
      withData: true,
    );
  } catch (_) {
    return null;
  }
  if (picked.isEmpty) return null;
  final bytes = picked.first.bytes;
  return bytes == null
      ? null
      : PickedImage(bytes: bytes, name: picked.first.name);
}

/// The picture field for a thing that does not exist yet.
///
/// Same square, same camera badge and same chooser as [EntityAvatarField], but
/// nothing leaves the device: the pick is held by the caller and uploaded once
/// the entity has an id. That is what lets the create dialog offer a picture at
/// all — the avatar endpoints are addressed by entity id, so there is nothing
/// to upload against until the create call has answered.
class PendingAvatarField extends StatelessWidget {
  const PendingAvatarField({
    super.key,
    required this.picked,
    required this.fallback,
    required this.strings,
    required this.onPicked,
    this.size = 72,
    this.radius = 20,
  });

  /// The image chosen so far, or null while the glyph stands in.
  final PickedImage? picked;
  final Widget fallback;
  final EntityAvatarStrings strings;

  /// The new choice, or null when the reader dropped the one they had.
  final ValueChanged<PickedImage?> onPicked;

  final double size;
  final double radius;

  Future<void> _edit(BuildContext context) async {
    if (picked == null) {
      onPicked(await pickImageBytes(context));
      return;
    }
    final action = await showAvatarActions(
      context,
      titleKey: strings.title,
      subtitleKey: strings.subtitle,
      changeKey: strings.change,
      removeKey: strings.remove,
    );
    if (!context.mounted || action == null) return;
    if (action == AvatarAction.change) {
      onPicked(await pickImageBytes(context));
    } else {
      onPicked(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = picked;
    return Semantics(
      button: true,
      label: context.t(strings.title),
      child: GestureDetector(
        onTap: () => _edit(context),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: image == null
                    ? fallback
                    : Image.memory(
                        image.bytes,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(
                  LucideIcons.camera,
                  size: 12,
                  color: Color(0xFF2A2410),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the platform image picker and wraps the choice as a [MultipartFile],
/// or null when nothing usable came back.
///
/// Web has no file path, so bytes are requested there and only there — reading
/// bytes on mobile would pull the whole image into memory for nothing.
Future<MultipartFile?> pickImageMultipart(BuildContext context) async {
  final List<ChosenFile> picked;
  try {
    picked = await pickFilesToUpload(
      context,
      kind: FilePickKind.image,
      withData: kIsWeb,
    );
  } catch (_) {
    return null;
  }
  // An empty list is a cancelled dialog; the catch above is one that would not
  // open. This field reports neither — the avatar stays what it was.
  if (picked.isEmpty) return null;
  final file = picked.first;
  if (kIsWeb) {
    final bytes = file.bytes;
    return bytes == null
        ? null
        : MultipartFile.fromBytes(bytes, filename: file.name);
  }
  final path = file.path;
  return path == null
      ? null
      : await MultipartFile.fromFile(path, filename: file.name);
}
