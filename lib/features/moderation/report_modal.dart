import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/moderation_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart';

/// Maximum characters accepted in the free-text note.
///
/// Bounded because the note is the one part of a report a moderator has to read
/// in full, and an unbounded box invites a pasted transcript instead of the one
/// sentence that explains what the category cannot.
const int _kNoteMaxLength = 1000;

/// Opens the "Report" modal for a piece of content or a person and files the
/// report.
///
/// The whole flow lives inside one modal — pick a reason, optionally say more,
/// submit — rather than a confirm-then-submit pair, because a report that costs
/// two dialogs is a report people abandon, and an abandoned report is a piece of
/// abuse nobody ever hears about.
///
/// The repository is read from [context] *before* the modal opens: glass modals
/// render on the root navigator, which sits above the app's providers, so a
/// `context.read` inside the builder would fail. Resolves once the modal closes;
/// the success toast is shown on the caller's context, which is still mounted
/// because the modal was pushed over it.
Future<void> showReportModal(BuildContext context, ReportTarget target) async {
  final repository = context.read<ModerationRepository>();
  final submitted = await showGlassModal<bool>(
    context,
    width: 480,
    builder: (_) => _ReportModalBody(repository: repository, target: target),
  );
  if (submitted == true && context.mounted) {
    showGlassToast(
      context,
      context.t('moderation.report.received'),
      kind: GlassToastKind.success,
    );
  }
}

/// Title/subtitle for the modal header, chosen by what is being reported.
///
/// Reporting a person and reporting a comment are different acts with different
/// consequences, and a header that said "Report" for both would leave the user
/// guessing which one they are about to do — especially when the action was
/// reached from an avatar that sits right next to the comment it wrote.
({String title, String subtitle}) _headerKeys(ReportTargetType type) =>
    switch (type) {
      ReportTargetType.user => (
        title: 'moderation.report.user.title',
        subtitle: 'moderation.report.user.sub',
      ),
      ReportTargetType.issue => (
        title: 'moderation.report.title',
        subtitle: 'moderation.report.issue.sub',
      ),
      ReportTargetType.comment => (
        title: 'moderation.report.title',
        subtitle: 'moderation.report.comment.sub',
      ),
      ReportTargetType.article => (
        title: 'moderation.report.title',
        subtitle: 'moderation.report.article.sub',
      ),
      ReportTargetType.attachment => (
        title: 'moderation.report.title',
        subtitle: 'moderation.report.attachment.sub',
      ),
    };

class _ReportModalBody extends StatefulWidget {
  const _ReportModalBody({required this.repository, required this.target});

  final ModerationRepository repository;
  final ReportTarget target;

  @override
  State<_ReportModalBody> createState() => _ReportModalBodyState();
}

class _ReportModalBodyState extends State<_ReportModalBody> {
  final TextEditingController _note = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;

  /// Inline failure key/message, shown under the form.
  ///
  /// Inline rather than a toast: the modal stays open on failure so the typed
  /// note survives, and a toast that floats above a still-open form reads as a
  /// message about something else.
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.report(
        widget.target,
        reason: reason,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = failure.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'errors.unexpected';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = _headerKeys(widget.target.type);
    final label = widget.target.label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.flag,
          title: context.t(header.title),
          subtitle: context.t(header.subtitle),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null && label.isNotEmpty) ...[
                  GlassInfoLine(
                    icon: LucideIcons.fileText,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                GlassField(
                  label: context.t('moderation.report.reason'),
                  child: ReasonPickerField(
                    reason: _reason,
                    onChanged: (picked) => setState(() => _reason = picked),
                  ),
                ),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('moderation.report.note'),
                  trailing: Text(
                    context.t('moderation.report.optional'),
                    style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                  ),
                  child: TextField(
                    controller: _note,
                    enabled: !_sending,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: _kNoteMaxLength,
                    decoration: glassInputDecoration(
                      hint: context.t('moderation.report.noteHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('moderation.report.privacy'),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.inkFaint,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    // `ApiFailure.message` is either already-localized server
                    // text or a fallback key; `t` is idempotent for the former.
                    context.t(_error!),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('moderation.report.submit'),
          confirmIcon: LucideIcons.flag,
          confirmColor: AppColors.danger,
          busy: _sending,
          onConfirm: _reason == null ? null : _submit,
        ),
      ],
    );
  }
}

/// One-line field that shows the chosen [ReportReason] and opens the picker.
///
/// A field-plus-popover rather than a radio list rendered into the form: the
/// reasons carry a sentence of explanation each, and nine of those inlined turn
/// a two-field modal into a page of scrolling that hides the note box and the
/// submit button below the fold.
class ReasonPickerField extends StatelessWidget {
  const ReasonPickerField({
    super.key,
    required this.reason,
    required this.onChanged,
  });

  final ReportReason? reason;
  final ValueChanged<ReportReason> onChanged;

  Future<void> _open(BuildContext context) async {
    // Capture the field's rect on this frame: after the await the render object
    // may be gone, and the popover needs somewhere to point.
    final box = context.findRenderObject() as RenderBox?;
    final anchor = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    final picked = wide
        ? await showGlassAnchoredPopover<ReportReason>(
            context,
            anchorRect: anchor,
            width: 360,
            minHeight: 240,
            maxHeight: 440,
            builder: (_) => _ReasonList(selected: reason),
          )
        : await showGlassBottomSheet<ReportReason>(
            context,
            builder: (_) => ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: _ReasonList(selected: reason, title: true),
            ),
          );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final selected = reason;
    return Material(
      color: AppColors.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected == null
                      ? context.t('moderation.report.reasonHint')
                      : context.t(selected.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected == null
                        ? AppColors.inkFaint
                        : AppColors.ink,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reason list rendered inside the popover / bottom sheet. Pops the tapped
/// reason.
class _ReasonList extends StatelessWidget {
  const _ReasonList({required this.selected, this.title = false});

  final ReportReason? selected;

  /// Whether to draw the sheet title (the anchored popover sits beside a field
  /// that already carries its label, so it does not repeat it).
  final bool title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Text(
              context.t('moderation.report.reason'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            children: [
              for (final reason in ReportReason.values)
                _ReasonRow(
                  reason: reason,
                  selected: reason == selected,
                  onTap: () => Navigator.of(context).pop(reason),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final ReportReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t(reason.labelKey),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t(reason.hintKey),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: AppColors.accentStrong,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
