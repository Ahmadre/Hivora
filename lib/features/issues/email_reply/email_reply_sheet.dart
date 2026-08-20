import 'dart:math' as math;

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/util/file_pick.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, glassWoltSurface, showGlassErrorToast, showGlassToast;

/// Opens the "Reply by email" composer for an email-sourced issue, presented the
/// same way as the issue detail itself — a Liquid-Glass [WoltModalSheet] (a wide
/// centred dialog on desktop, a bottom sheet on mobile) with the shared
/// [glassWoltSurface] material and glass top bar. A reply goes to the issue's
/// original sender ([Issue.reporterEmail]) via the platform SMTP; attachments
/// are uploaded onto the issue and referenced by id.
///
/// The sheet can be *maximized* into [EmailReplyScreen] — a full-page route that
/// renders inside the app shell exactly like a maximized issue — via the top-bar
/// button; closing it (send, cancel, back) returns to the issue. [initialDraft]
/// restores what was typed/attached when minimizing back.
Future<void> showEmailReplySheet(
  BuildContext context, {
  required Issue issue,
  required IssueRepository repo,
  EmailReplyDraft? initialDraft,
}) {
  final composerKey = GlobalKey<EmailReplyComposerState>();
  // Bumped by the composer whenever the send button's enabled/busy state can
  // change (field edits, attachment progress) so the sticky action bar — a
  // separate subtree from the body — rebuilds. Mirrors the issue sheet.
  final rev = ValueNotifier<int>(0);

  return WoltModalSheet.show<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: false,
    barrierDismissible: true,
    pageContentDecorator: glassWoltSurface,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _EmailWideDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // Don't let the keyboard shrink the whole sheet (Wolt's Scaffold would
        // resize the modal to the remaining space); the form scrolls instead.
        resizeToAvoidBottomInset: false,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        leadingNavBarWidget: const Padding(
          padding: EdgeInsets.only(left: 14.0),
          child: _EmailSheetTitle(),
        ),
        trailingNavBarWidget: Padding(
          padding: const EdgeInsets.only(right: 6.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.t('issues.maximize'),
                icon: Icon(
                  LucideIcons.maximize2,
                  size: 19,
                  color: AppColors.inkSoft,
                ),
                onPressed: () {
                  final draft = composerKey.currentState?.currentDraft;
                  final rootNav = Navigator.of(
                    modalContext,
                    rootNavigator: true,
                  );
                  final router = GoRouter.of(modalContext);
                  // Reveal the shell by closing this sheet AND the issue sheet
                  // beneath it, then render the composer as a full-page route
                  // whose parent is `/issues/:id` — so backing out lands on the
                  // issue exactly like a maximized issue does.
                  rootNav.popUntil((r) => r.isFirst);
                  router.push(
                    '/issues/${issue.id}/reply-email',
                    extra: EmailReplyRouteArgs(
                      issue: issue,
                      draft: draft,
                      fromModal: true,
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: context.t('common.cancel'),
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
                onPressed: () => Navigator.of(modalContext).maybePop(),
              ),
            ],
          ),
        ),
        stickyActionBar: ValueListenableBuilder<int>(
          valueListenable: rev,
          builder: (ctx, _, _) {
            final state = composerKey.currentState;
            return _EmailSendBar(
              busy: state?.sending ?? false,
              canSend: state?.canSend ?? false,
              onSend: () => composerKey.currentState?.send(),
              onCancel: () => Navigator.of(ctx).maybePop(),
            );
          },
        ),
        child: EmailReplyComposer(
          key: composerKey,
          issue: issue,
          repo: repo,
          initialDraft: initialDraft,
          revision: rev,
        ),
      ),
    ],
  ).whenComplete(rev.dispose);
}

/// Arguments handed to the `/issues/:id/reply-email` route via GoRouter `extra`
/// when the sheet is maximized: the issue to reply to, the carried-over draft,
/// and whether it can shrink back to the sheet ([fromModal]).
class EmailReplyRouteArgs {
  const EmailReplyRouteArgs({
    required this.issue,
    this.draft,
    this.fromModal = false,
  });

  final Issue issue;
  final EmailReplyDraft? draft;
  final bool fromModal;
}

/// Centred dialog sized like the issue detail's wide dialog, so the maximized
/// email composer matches its proportions on desktop.
class _EmailWideDialogType extends WoltDialogType {
  const _EmailWideDialogType();

  @override
  BoxConstraints layoutModal(Size availableSize) {
    const pad = 48.0;
    final width = math.min(
      720.0,
      math.max(360.0, availableSize.width - pad * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: 0,
      maxHeight: math.max(360, availableSize.height * 0.88),
    );
  }
}

/// The sheet's top-bar title: the mail glyph tile + "Reply by email".
class _EmailSheetTitle extends StatelessWidget {
  const _EmailSheetTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            LucideIcons.mail,
            size: 16,
            color: AppColors.accentStrong,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          context.t('issues.replyEmail.title'),
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

/// Full-page email composer — the maximized counterpart to the sheet, rendered
/// by the `/issues/:id/reply-email` route inside the app shell (nav rail + header
/// stay visible, exactly like a maximized issue). Closing or backing out returns
/// to the issue.
class EmailReplyScreen extends StatefulWidget {
  const EmailReplyScreen({
    super.key,
    required this.issue,
    this.initialDraft,
    this.canMinimize = false,
  });

  final Issue issue;
  final EmailReplyDraft? initialDraft;

  /// Offer an "exit full screen" button back to the sheet (set when promoted
  /// from it). A cold deep-link into this route has nothing to shrink to.
  final bool canMinimize;

  @override
  State<EmailReplyScreen> createState() => _EmailReplyScreenState();
}

class _EmailReplyScreenState extends State<EmailReplyScreen> {
  // Allocated ONCE for the screen's lifetime. Building these in build() handed
  // the composer a fresh GlobalKey every keyboard-animation frame (viewInsetsOf
  // is a dependency), which destroyed and re-created the composer State — wiping
  // the draft and bouncing the keyboard closed.
  final composerKey = GlobalKey<EmailReplyComposerState>();
  final rev = ValueNotifier<int>(0);

  @override
  void dispose() {
    rev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final repo = context.read<IssueRepository>();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          _EmailRouteTopBar(
            recipient: issue.reporterEmail ?? '',
            onBack: () => Navigator.of(context).maybePop(),
            onMinimize: widget.canMinimize
                ? () {
                    // Leave this route THROUGH GoRouter (pop), never via
                    // Navigator.removeRoute: removing a page-based route behind
                    // the router's back leaves its location stuck on
                    // `/reply-email`, and a later back-navigation re-syncs the
                    // stack and resurrects this screen out of nowhere.
                    final draft = composerKey.currentState?.currentDraft;
                    // The sheet must be shown from a context that survives this
                    // route's disposal — the root navigator's, not ours.
                    final rootCtx = Navigator.of(
                      context,
                      rootNavigator: true,
                    ).context;
                    context.pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!rootCtx.mounted) return;
                      showEmailReplySheet(
                        rootCtx,
                        issue: issue,
                        repo: repo,
                        initialDraft: draft,
                      );
                    });
                  }
                : null,
          ),
          Expanded(
            // The content keeps its full height ALWAYS — the send bar floats
            // over it as an overlay and simply rides above the keyboard, so
            // opening the keyboard never shrinks/resizes the form.
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    // Clear the floating send bar at the bottom.
                    padding: const EdgeInsets.only(bottom: 72),
                    child: EmailReplyComposer(
                      key: composerKey,
                      issue: issue,
                      repo: repo,
                      initialDraft: widget.initialDraft,
                      revision: rev,
                      expandBody: true,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: keyboard,
                  child: SafeArea(
                    top: false,
                    child: ValueListenableBuilder<int>(
                      valueListenable: rev,
                      builder: (ctx, _, _) {
                        final state = composerKey.currentState;
                        return _EmailSendBar(
                          busy: state?.sending ?? false,
                          canSend: state?.canSend ?? false,
                          onSend: () => composerKey.currentState?.send(),
                          onCancel: () => Navigator.of(ctx).maybePop(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A draft handed between the sheet composer and the full-page composer when
/// maximizing/minimizing, so the user never loses what they've typed or attached
/// across the transition.
class EmailReplyDraft {
  const EmailReplyDraft({
    this.subject = '',
    this.body = '',
    this.attachments = const [],
  });

  final String subject;
  final String body;
  final List<EmailDraftAttachment> attachments;
}

/// One already-resolved attachment carried across a maximize/minimize. In-flight
/// uploads aren't handed over (they can't resume in a fresh composer); the file
/// keeps uploading onto the issue regardless.
class EmailDraftAttachment {
  const EmailDraftAttachment({
    required this.name,
    this.id,
    this.failed = false,
  });

  final String name;
  final String? id;
  final bool failed;
}

/// The shared compose fields (recipient · subject · body · attachments). The
/// title + maximize/minimize/close live in the host chrome (the sheet's top bar
/// or the route's top bar); the send/attach action bar is host-provided too.
/// The host reads [currentDraft]/[canSend]/[sending] and calls [send] via a
/// [GlobalKey], and rebuilds its sticky send bar from [revision].
class EmailReplyComposer extends StatefulWidget {
  const EmailReplyComposer({
    super.key,
    required this.issue,
    required this.repo,
    this.initialDraft,
    this.revision,
    this.expandBody = false,
  });

  final Issue issue;
  final IssueRepository repo;
  final EmailReplyDraft? initialDraft;

  /// Bumped whenever [canSend]/[sending] can change, so a host sticky bar can
  /// rebuild.
  final ValueNotifier<int>? revision;

  /// Let the body field grow to fill available height (full-page); otherwise it
  /// is capped and the whole form scrolls (sheet).
  final bool expandBody;

  @override
  State<EmailReplyComposer> createState() => EmailReplyComposerState();
}

/// One attachment the user added to the draft. It is uploaded onto the issue
/// immediately on pick (so the reply can reference it by id), showing a spinner
/// while in flight and an error affordance if the upload fails.
class _Draft {
  _Draft(this.name);
  final String name;
  String? id; // set once uploaded
  bool uploading = true;
  bool failed = false;
}

class EmailReplyComposerState extends State<EmailReplyComposer> {
  late final TextEditingController _subject = TextEditingController(
    text: widget.initialDraft?.subject ?? _prefillSubject(),
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.initialDraft?.body ?? '',
  );
  late final List<_Draft> _drafts = [
    for (final a
        in widget.initialDraft?.attachments ?? const <EmailDraftAttachment>[])
      _Draft(a.name)
        ..id = a.id
        ..uploading = false
        ..failed = a.failed,
  ];
  bool _sending = false;

  String _prefillSubject() {
    final original = widget.issue.inboundSubject?.trim();
    if (original == null || original.isEmpty) return '';
    // Don't stack "Re: Re: …" if the source subject already carries one.
    return original.toLowerCase().startsWith('re:')
        ? original
        : 'Re: $original';
  }

  @override
  void initState() {
    super.initState();
    // The host's sticky send bar reads our state via a GlobalKey, which is null
    // until we've mounted. Nudge it once so an initial draft (restored on
    // minimize, or a prefilled subject) enables Send without needing a keystroke.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.revision?.value++;
    });
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  // ── host-facing API ───────────────────────────────────────────────────────
  bool get sending => _sending;

  bool get canSend =>
      !_sending &&
      _subject.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty &&
      !_drafts.any((d) => d.uploading);

  /// The current draft to carry across a maximize/minimize. Only settled
  /// attachments travel — an in-flight upload can't resume in a fresh composer.
  EmailReplyDraft get currentDraft => EmailReplyDraft(
    subject: _subject.text,
    body: _body.text,
    attachments: [
      for (final d in _drafts)
        if (!d.uploading)
          EmailDraftAttachment(name: d.name, id: d.id, failed: d.failed),
    ],
  );

  Future<void> send() async {
    if (!canSend) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _set(() => _sending = true);
    try {
      await widget.repo.replyEmail(
        widget.issue.id,
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        attachmentIds: [
          for (final d in _drafts)
            if (d.id != null && !d.failed) d.id!,
        ],
      );
      if (!mounted) return;
      // GlassToast lives on the root overlay, so it survives the pop that
      // returns us to the issue (sheet or full-page route, same call).
      showGlassToast(
        context,
        context.t('issues.replyEmail.sent'),
        kind: GlassToastKind.success,
      );
      Navigator.of(context).maybePop();
    } on ApiFailure catch (e) {
      if (!mounted) return;
      _set(() => _sending = false);
      showGlassErrorToast(context, context.t(e.message));
    } catch (_) {
      if (!mounted) return;
      _set(() => _sending = false);
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }

  // Rebuild AND notify the host (its sticky send bar is a separate subtree).
  void _set(VoidCallback fn) {
    setState(fn);
    widget.revision?.value++;
  }

  Future<void> _pick() async {
    final List<ChosenFile> result;
    try {
      result = await pickFilesToUpload(
        context,
        allowMultiple: true,
        withData: kIsWeb, // web has no path; bytes are required
      );
    } catch (_) {
      if (mounted) {
        showGlassErrorToast(
          context,
          context.t('issues.attachments.pickFailed'),
        );
      }
      return;
    }
    // An empty list means cancelled — nothing to report.
    if (result.isEmpty || !mounted) return;
    // Show every chip immediately (as uploading)…
    final pending = [for (final f in result) (_Draft(f.name), f)];
    _set(() => _drafts.addAll(pending.map((e) => e.$1)));
    // …then upload them one at a time. The endpoint returns the whole issue and
    // we read the new id off `attachments.last`, so concurrent uploads would
    // race and mis-assign ids (or duplicate one). Serializing keeps each POST's
    // returned issue unambiguously ending with THIS file's attachment.
    for (final (draft, f) in pending) {
      if (!mounted) return;
      await _upload(draft, f);
    }
  }

  Future<void> _upload(_Draft draft, ChosenFile file) async {
    try {
      final multipart = kIsWeb || file.path == null
          ? MultipartFile.fromBytes(file.bytes ?? const [], filename: file.name)
          : await MultipartFile.fromFile(file.path!, filename: file.name);
      final saved = await widget.repo.uploadAttachment(
        widget.issue.id,
        multipart,
      );
      // The just-added attachment is the newest one on the returned issue.
      final id = saved.attachments.isNotEmpty
          ? saved.attachments.last.id
          : null;
      if (!mounted) return;
      _set(() {
        draft.id = id;
        draft.uploading = false;
        draft.failed = id == null;
      });
    } catch (_) {
      if (!mounted) return;
      _set(() {
        draft.uploading = false;
        draft.failed = true;
      });
    }
  }

  Future<void> _removeDraft(_Draft draft) async {
    _set(() => _drafts.remove(draft));
    // Best-effort: also detach it from the issue so a cancelled attachment
    // doesn't linger. Ignore failures — the reply simply won't reference it.
    if (draft.id != null) {
      try {
        await widget.repo.deleteAttachment(widget.issue.id, draft.id!);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachments = _AttachmentsRow(
      drafts: _drafts,
      onAdd: _sending ? null : _pick,
      onRemove: _sending ? null : _removeDraft,
    );

    if (widget.expandBody) {
      // Full-page: recipient/subject pinned, body grows, attachments below it.
      return GestureDetector(
        // Tap anywhere outside a field → collapse the keyboard.
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _recipientLine(),
              const SizedBox(height: 16),
              _subjectField(),
              const SizedBox(height: 16),
              Expanded(child: _bodyField(expand: true)),
              const SizedBox(height: 16),
              attachments,
            ],
          ),
        ),
      );
    }

    // Sheet: the whole form scrolls (Wolt owns the scroll view); pad the bottom
    // so the last field clears the sticky send bar. The keyboard must NOT
    // shrink the sheet (resizeToAvoidBottomInset: false), so instead the form
    // grows by the keyboard inset and the focused field scrolls above it
    // (see the TextFields' scrollPadding).
    return GestureDetector(
      // Tap anywhere outside a field → collapse the keyboard.
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          8,
          22,
          96 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _recipientLine(),
            const SizedBox(height: 16),
            _subjectField(),
            const SizedBox(height: 16),
            _bodyField(expand: false),
            const SizedBox(height: 16),
            attachments,
          ],
        ),
      ),
    );
  }

  Widget _recipientLine() {
    final recipient = widget.issue.reporterEmail ?? '';
    return _GlassInfoLine(
      icon: LucideIcons.atSign,
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
          children: [
            TextSpan(text: '${context.t('issues.replyEmail.to')} '),
            TextSpan(
              text: recipient,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ).copyWith(color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectField() {
    return _LabeledField(
      label: context.t('issues.replyEmail.subject'),
      child: TextField(
        controller: _subject,
        onChanged: (_) => _set(() {}),
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.sentences,
        // Scroll the focused field clear of keyboard + sticky send bar (the
        // sheet doesn't resize for the keyboard).
        scrollPadding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 120,
        ),
        decoration: _inputDecoration(
          context.t('issues.replyEmail.subjectHint'),
        ),
      ),
    );
  }

  Widget _bodyField({required bool expand}) {
    final field = TextField(
      controller: _body,
      onChanged: (_) => _set(() {}),
      expands: expand,
      minLines: expand ? null : 6,
      maxLines: expand ? null : 12,
      textAlignVertical: expand ? TextAlignVertical.top : null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      scrollPadding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 120,
      ),
      decoration: _inputDecoration(context.t('issues.replyEmail.bodyHint')),
    );
    return _LabeledField(
      label: context.t('issues.replyEmail.body'),
      child: expand ? Expanded(child: field) : field,
    );
  }
}

// ── shared small widgets ──────────────────────────────────────────────────

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: true,
  fillColor: AppColors.surface.withValues(alpha: 0.7),
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: BorderSide(color: AppColors.hairline),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
  ),
);

/// A labelled form field (mirrors the sprint modals' GlassField, kept local so
/// this feature owns its layout in both the sheet and full-page hosts).
class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// The read-only recipient line on the glass material.
class _GlassInfoLine extends StatelessWidget {
  const _GlassInfoLine({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The pinned Cancel / Send bar, hosted by the sheet (sticky) and the full-page
/// route (bottom).
class _EmailSendBar extends StatelessWidget {
  const _EmailSendBar({
    required this.busy,
    required this.canSend,
    required this.onSend,
    required this.onCancel,
  });

  final bool busy;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: busy ? null : onCancel,
            child: Text(context.t('common.cancel')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy || !canSend ? null : onSend,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
            ),
            icon: busy
                ? const HiveLoader(size: 15, color: Colors.white)
                : const Icon(LucideIcons.send, size: 15),
            label: Text(context.t('issues.replyEmail.send')),
          ),
        ],
      ),
    );
  }
}

/// The full-page route's glass top bar: back · title · minimize.
class _EmailRouteTopBar extends StatelessWidget {
  const _EmailRouteTopBar({
    required this.recipient,
    required this.onBack,
    this.onMinimize,
  });

  final String recipient;
  final VoidCallback onBack;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 6, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppColors.hairline.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: context.t('common.back'),
              icon: Icon(LucideIcons.arrowLeft, size: 22, color: AppColors.ink),
              onPressed: onBack,
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                LucideIcons.mail,
                size: 16,
                color: AppColors.accentStrong,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t('issues.replyEmail.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    recipient,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onMinimize != null)
              IconButton(
                tooltip: context.t('issues.minimize'),
                icon: Icon(
                  LucideIcons.minimize2,
                  size: 19,
                  color: AppColors.inkSoft,
                ),
                onPressed: onMinimize,
              ),
          ],
        ),
      ),
    );
  }
}

/// The "Add attachment" affordance plus a wrapping list of attachment chips.
class _AttachmentsRow extends StatelessWidget {
  const _AttachmentsRow({
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_Draft> drafts;
  final VoidCallback? onAdd;
  final ValueChanged<_Draft>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _AddChip(onTap: onAdd),
        for (final d in drafts)
          _AttachmentChip(
            draft: d,
            onRemove: onRemove == null ? null : () => onRemove!(d),
          ),
      ],
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.paperclip,
                size: 15,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 7),
              Text(
                context.t('issues.replyEmail.attach'),
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

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.draft, required this.onRemove});
  final _Draft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final failed = draft.failed;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
      decoration: BoxDecoration(
        color: failed
            ? AppColors.danger.withValues(alpha: 0.10)
            : AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: failed
              ? AppColors.danger.withValues(alpha: 0.5)
              : AppColors.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draft.uploading)
            const HiveLoader(size: 13)
          else
            Icon(
              failed ? LucideIcons.circleAlert : LucideIcons.file,
              size: 14,
              color: failed ? AppColors.danger : AppColors.inkSoft,
            ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              draft.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: failed ? AppColors.danger : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            icon: Icon(LucideIcons.x, size: 14, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
