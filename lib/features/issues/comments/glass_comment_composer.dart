import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        GlassButton,
        GlassContainer,
        GlassMenuAlignment,
        GlassPopover,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/markdown_toolbar.dart';
import '../../../core/lexical/hinata_markdown_preview.dart';
import '../../knowledge/markdown/mention_field.dart';
import '../../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import 'voice/voice_recorder.dart';

part 'glass_comment_composer.widgets.dart';

/// The composer floats over the scrolling comment feed (phone sticky bar /
/// desktop panel footer), so — unlike the bottom nav, which sits over the solid
/// canvas — its glass must be far more **opaque** or the feed bleeds through and
/// the input becomes unreadable. Same refraction/lighting as the nav preset, but
/// a strong tint (dark slate / near-solid frost) so the field + buttons read
/// clearly in both themes. See `kNavGlassDark/Light` for the transparent siblings.
const _composerGlassDark = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0xD91A1A22), // ~0.85 opaque dark slate
);
const _composerGlassLight = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0xF2FFFFFF), // ~0.95 near-solid frost
);

LiquidGlassSettings _composerGlass(bool dark) =>
    dark ? _composerGlassDark : _composerGlassLight;

/// A rounded composer surface (field pill, popup, recording bar, format editor).
///
/// Always real Liquid Glass — but pinned to [GlassQuality.standard] (the
/// lightweight fragment shader with universal Skia/Impeller/Web support that
/// renders correctly while scrolling). The default `premium` Impeller pipeline
/// is unreadable in dark mode (its refraction samples the dark feed → dark-on-
/// dark) and its captured texture corrupts on device rotation — the composer
/// floats over a scrolling feed, exactly the context `premium` warns against.
/// The strong [_composerGlass] tint then keeps the field legible in both themes.
Widget _composerSurface({
  required bool dark,
  required double radius,
  required Widget child,
  EdgeInsetsGeometry? padding,
  double? width,
  double? height,
}) {
  return GlassContainer(
    width: width,
    height: height,
    useOwnLayer: true,
    quality: GlassQuality.standard,
    settings: _composerGlass(dark),
    clipBehavior: Clip.antiAlias,
    shape: LiquidRoundedSuperellipse(borderRadius: radius),
    padding: padding,
    child: child,
  );
}

const Color _onAccent = Color(0xFF2A2410);

/// Round composer button size. On phones it's a fat 52 touch target; on the
/// wider tablet/desktop/web layouts (macOS + Web included) the composer is
/// pointer-driven, so we trim the [+]/mic/send circles a touch — at 52 they
/// read too large next to the field pill. Keyed off the same compact-width
/// signal the comment thread uses to split phone-chat from desktop layout.
double _composerButtonSize(BuildContext context) => context.isCompact ? 52 : 46;

/// Attachment sources offered by the composer's "+" menu.
enum ComposerAttach { camera, gallery, file }

/// How the composer obtains a recorder.
///
/// A seam, not a setting: a widget test cannot open a microphone, and the one
/// behaviour here that must never regress — a finished recording surviving a
/// failed upload — only exists *after* a recording has been captured. Nothing in
/// the app assigns this.
@visibleForTesting
VoiceRecorder Function() voiceRecorderFactory = VoiceRecorder.new;

/// The Liquid-Glass comment composer from the design. Morphs through:
///   • idle     → [+] · field · mic
///   • typing   → mic becomes the honey-amber send button
///   • popup    → glass "+" menu (camera / gallery / attachment / format)
///   • format   → grows *in place* into a Markdown editor (Edit/Preview switch,
///                drag-to-resize, toolbar pinned) — no modal. Because the
///                composer is always bottom-anchored in its region (the phone
///                sticky bar or the desktop comment panel's footer), the editor
///                expands *upward* with the toolbar staying put.
///   • recording → live-waveform voice recorder with cancel / send
///   • recorded  → a finished recording the upload has not accepted yet: still
///                 in memory, offering "send again" and a deliberate discard
///
/// It wraps a [MentionField] so `@`-mentions and smart-links keep working, and
/// drives formatting through the shared [MarkdownEditingActions]. The parent
/// owns the [controller] (so it can read/clear the text on submit) and handles
/// attachment picking + voice/text sending via the callbacks. When [editing] is
/// set, the composer is editing an existing comment inline — it shows a banner
/// and the parent's submit saves the edit.
class GlassCommentComposer extends StatefulWidget {
  const GlassCommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.actions,
    required this.onSubmitText,
    required this.onSendVoice,
    required this.onAttach,
    this.editing = false,
    this.onCancelEdit,
    this.replyingToName,
    this.replyingToPreview,
    this.onCancelReply,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MarkdownEditingActions actions;
  final VoidCallback onSubmitText;

  /// Uploads [recording] and answers whether it was actually posted.
  ///
  /// The composer holds the audio until this returns true. A `void` callback
  /// could not say "that failed", which is why every failure used to take the
  /// recording with it — there is no file left to retry from once the recorder
  /// has stopped, so the bytes in flight are the only copy. Errors are the
  /// parent's to explain (it is the one that knows whether the content was
  /// refused); the composer only needs the verdict.
  final Future<bool> Function(VoiceRecording recording) onSendVoice;

  final void Function(ComposerAttach kind) onAttach;

  /// True while editing an existing comment inline (shows the edit banner).
  final bool editing;
  final VoidCallback? onCancelEdit;

  /// When set, a WhatsApp-style "replying to …" quote bar floats above the
  /// field; the parent's submit attaches the reply.
  final String? replyingToName;
  final String? replyingToPreview;
  final VoidCallback? onCancelReply;

  final bool enabled;

  @override
  State<GlassCommentComposer> createState() => _GlassCommentComposerState();
}

enum _Mode { idle, recording, recorded, format }

class _GlassCommentComposerState extends State<GlassCommentComposer> {
  _Mode _mode = _Mode.idle;

  // Format mode: the drag-resizable field height + the Edit/Preview toggle.
  double _formatHeight = 200;
  bool _preview = false;

  VoiceRecorder? _recorder;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  bool _starting = false;

  /// The finished recording, held until an upload confirms it was posted.
  ///
  /// The recorder's file is consumed by [VoiceRecorder.stop], so this is the
  /// only copy of what the person just said. It is cleared on exactly two
  /// events: a successful send, or a discard the user asked for.
  VoiceRecording? _recorded;

  /// Whether [_recorded] is being uploaded right now.
  bool _sendingVoice = false;

  bool get _canSend => widget.controller.text.trim().isNotEmpty;

  // Last computed send-ability, so a keystroke only rebuilds this composer (which
  // hosts liquid-glass buttons) when the mic↔send affordance actually flips —
  // not on every character. Typing rebuilt the glass buttons per keystroke
  // before, a measurable source of input lag in the comment field.
  bool _sendable = false;

  @override
  void initState() {
    super.initState();
    _sendable = _canSend;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _recTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Rebuild only when the mic↔send swap actually changes (empty ↔ non-empty),
    // not on every keystroke.
    final sendable = _canSend;
    if (sendable == _sendable) return;
    _sendable = sendable;
    if (mounted) setState(() {});
  }

  // ── recording ──────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_starting) return;
    _starting = true;
    final recorder = voiceRecorderFactory();
    bool ok;
    try {
      ok = await recorder.start();
    } catch (_) {
      // Some platforms throw instead of returning false when the mic is
      // unavailable (e.g. no device / permission race) — treat as denied.
      ok = false;
    }
    _starting = false;
    if (!ok) {
      await recorder.dispose();
      if (mounted) {
        showGlassErrorToast(context, context.t('comments.micDenied'));
      }
      return;
    }
    // The composer may have been disposed while the permission prompt / native
    // start was in flight (issue sheet closed, navigated away). dispose() ran
    // with _recorder still null, so committing here would leak an open mic
    // session + a forever-firing timer. Release it instead.
    if (!mounted) {
      await recorder.cancel();
      await recorder.dispose();
      return;
    }
    _recorder = recorder;
    _recElapsed = Duration.zero;
    _recTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() => _recElapsed += const Duration(milliseconds: 100));
      }
    });
    if (mounted) setState(() => _mode = _Mode.recording);
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    final r = _recorder;
    _recorder = null;
    if (mounted) setState(() => _mode = _Mode.idle);
    await r?.cancel();
    await r?.dispose();
  }

  /// Stops the recorder and hands the audio to the parent — keeping it here
  /// until the parent says it was posted.
  ///
  /// The composer deliberately does *not* return to idle first. Idle is the
  /// state that says "there is nothing of yours in here", and until the upload
  /// is confirmed that is untrue: the recorder's file is already consumed, so
  /// these bytes are the only copy of what was just said.
  Future<void> _sendRecording() async {
    _recTimer?.cancel();
    final r = _recorder;
    _recorder = null;
    if (r == null) return;
    VoiceRecording? recording;
    try {
      recording = await r.stop();
    } catch (_) {
      // Native stop failure / web blob read failure — nothing was captured, so
      // there is nothing to keep; fall through to the error toast below.
      recording = null;
    } finally {
      await r.dispose();
    }
    if (recording == null || recording.durationMs <= 300) {
      if (mounted) {
        setState(() => _mode = _Mode.idle);
        // Without this the bar would just close and the message would vanish
        // with no explanation (stop failed, empty bytes, or too short to be one).
        showGlassErrorToast(context, context.t('comments.voiceFailed'));
      }
      return;
    }
    if (!mounted) {
      // The thread was closed between "send" and the recorder handing the bytes
      // over. There is no composer left to keep them in, so the upload is still
      // worth attempting — losing the message would be the worse outcome — but
      // its verdict has nowhere to go.
      unawaited(widget.onSendVoice(recording));
      return;
    }
    setState(() {
      _recorded = recording;
      _mode = _Mode.recorded;
    });
    await _uploadRecorded();
  }

  /// Uploads [_recorded], clearing it only once the parent confirms the comment
  /// exists. A refusal or a dropped connection leaves the audio — and the bar
  /// offering it — exactly where they were.
  Future<void> _uploadRecorded() async {
    final recording = _recorded;
    if (recording == null || _sendingVoice) return;
    setState(() => _sendingVoice = true);
    final sent = await widget.onSendVoice(recording);
    if (!mounted) return;
    setState(() {
      _sendingVoice = false;
      if (sent) {
        _recorded = null;
        _mode = _Mode.idle;
      }
    });
  }

  /// Throws the kept recording away. The only path that discards it, and it is
  /// a button the user pressed — nothing in an error path may do this.
  void _discardRecorded() {
    setState(() {
      _recorded = null;
      _mode = _Mode.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _Mode.recording) {
      return _RecordingBar(
        elapsed: _recElapsed,
        amplitude: _recorder?.liveAmplitude ?? const Stream.empty(),
        buttonSize: _composerButtonSize(context),
        onCancel: _cancelRecording,
        onSend: _sendRecording,
      );
    }

    final recorded = _recorded;
    if (_mode == _Mode.recorded && recorded != null) {
      return _RecordedBar(
        recording: recorded,
        buttonSize: _composerButtonSize(context),
        sending: _sendingVoice,
        onDiscard: _discardRecorded,
        onSend: _uploadRecorded,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.editing)
          _EditingBanner(onCancel: widget.onCancelEdit ?? () {}),
        if (!widget.editing && widget.replyingToName != null)
          _ReplyBanner(
            name: widget.replyingToName!,
            preview: widget.replyingToPreview ?? '',
            onCancel: widget.onCancelReply ?? () {},
          ),
        if (_mode == _Mode.format) _formatEditor(context) else _idleRow(),
      ],
    );
  }

  /// The single-line composer row: [+] · field · mic/send. While editing an
  /// existing comment, the leading "+" becomes an "×" that abandons the edit.
  Widget _idleRow() {
    return Row(
      // Single-line field and the buttons share one baseline; when the
      // field grows, buttons stay pinned to the bottom edge.
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _leadingButton(),
        const SizedBox(width: 10),
        Expanded(child: _fieldPill()),
        const SizedBox(width: 10),
        _trailingButton(),
      ],
    );
  }

  /// Leading circle: an "×" cancel-edit button while editing, otherwise the "+"
  /// attachment menu trigger.
  ///
  /// The "+" is wrapped in a [GlassPopover] so the attachment menu opens with
  /// the package's full iOS-26 dual-blob metaball morph — the glass literally
  /// pulls a teardrop neck out of the button and rubber-bands into the panel
  /// (and collapses back on close), instead of a plain scale/fade. The popover
  /// owns its own overlay, spring physics, positioning and screen-edge
  /// clamping; we only feed it the trigger, the content, and our dark composer
  /// glass so it matches the rest of the chrome. Pinned to
  /// [GlassMenuAlignment.bottomLeft] so it always grows upward-left out of the
  /// button (the composer is bottom-anchored), never downward over the field.
  Widget _leadingButton() {
    final size = _composerButtonSize(context);
    if (widget.editing) {
      return _CircleButton(
        icon: LucideIcons.x,
        size: size,
        onTap: widget.enabled ? widget.onCancelEdit : null,
      );
    }
    final dark = AppColors.brightness == Brightness.dark;
    return GlassPopover(
      alignment: GlassMenuAlignment.bottomLeft,
      popoverWidth: 268,
      popoverBorderRadius: 24,
      // Same near-opaque dark-slate / frost tint as the rest of the composer so
      // the morphing panel reads identically to the field pill and "+" menu of
      // old — the metaball just adds the liquid growth on top.
      settings: _composerGlass(dark),
      // The metaball neck (SDF blend of the two blobs) only renders on the
      // premium Impeller pipeline; standard silently drops the blend. This is a
      // transient, heavily-tinted overlay (not a surface floating over the
      // scrolling feed), so the usual reasons the composer avoids premium don't
      // apply here — and it degrades gracefully to a plain morph on Skia/web.
      quality: GlassQuality.premium,
      triggerBuilder: (context, toggle) => _CircleButton(
        icon: LucideIcons.plus,
        size: size,
        onTap: widget.enabled ? toggle : null,
      ),
      contentBuilder: (context, close) => _ActionPopup(
        onPick: (kind) {
          close();
          widget.onAttach(kind);
        },
        onFormat: () {
          close();
          _openFormat();
        },
      ),
    );
  }

  /// A single-line glass pill the same height (52) as the buttons; it grows a
  /// little as you type. Short placeholder so the empty state stays on one line.
  Widget _fieldPill() {
    final dark = AppColors.brightness == Brightness.dark;
    return _composerSurface(
      dark: dark,
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: MentionField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        commentMode: true,
        minLines: 1,
        maxLines: 5,
        hintText: context.t('comments.placeholder'),
        onSubmit: _submitText,
      ),
    );
  }

  Widget _trailingButton() {
    final size = _composerButtonSize(context);
    if (_canSend) {
      return _CircleButton(
        icon: LucideIcons.send,
        size: size,
        send: true,
        onTap: widget.enabled ? _submitText : null,
      );
    }
    return _CircleButton(
      icon: LucideIcons.mic,
      size: size,
      onTap: widget.enabled ? _startRecording : null,
    );
  }

  void _submitText() {
    if (!_canSend) return;
    widget.onSubmitText();
  }

  /// Enters the inline Markdown editor. It replaces the single-line row and,
  /// because the composer is bottom-anchored in its region, grows *upward* when
  /// the drag handle is pulled — the toolbar stays pinned at the bottom.
  void _openFormat() {
    setState(() {
      _mode = _Mode.format;
      _preview = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  /// Collapses the editor back to the single-line pill.
  void _closeFormat() {
    if (mounted) setState(() => _mode = _Mode.idle);
  }

  /// The inline Markdown editor shown in format mode. Layout (top→bottom):
  /// drag handle + Edit/Preview switch · resizable field/preview · pinned
  /// toolbar. Bottom-anchored in its parent, so growing the field pushes the
  /// handle up while the toolbar stays put.
  Widget _formatEditor(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    // Cap the field so the editor can't overrun its region — the phone sticky
    // bar or the desktop comment panel, whose height tracks the same viewport
    // fraction (mind the keyboard).
    final maxField = (media.size.height * 0.34 - media.viewInsets.bottom).clamp(
      140.0,
      360.0,
    );
    final fieldHeight = _formatHeight.clamp(140.0, maxField);
    final canSend = widget.controller.text.trim().isNotEmpty;

    return _composerSurface(
      dark: dark,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _DragHandle(
                  onDrag: (dy) => setState(() {
                    // Drag up (dy<0) grows the field; clamp to the viewport cap.
                    _formatHeight = (fieldHeight - dy).clamp(140.0, maxField);
                  }),
                ),
              ),
              _EditPreviewSwitch(
                preview: _preview,
                onChanged: (v) {
                  setState(() => _preview = v);
                  if (!v) widget.focusNode.requestFocus();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: fieldHeight,
            child: _preview
                ? _previewBody(context)
                : MentionField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    commentMode: true,
                    expands: true,
                    hintText: context.t('comments.placeholder'),
                  ),
          ),
          const SizedBox(height: 8),
          _FormatToolbar(
            actions: widget.actions,
            canSend: canSend,
            onClose: _closeFormat,
            onSend: () {
              if (!canSend) return;
              widget.onSubmitText();
              _closeFormat();
            },
          ),
        ],
      ),
    );
  }

  /// Live preview of the current draft, converted exactly as the server will
  /// convert it — mentions, smart-links and images render as they will in the
  /// posted comment because it is the same conversion.
  Widget _previewBody(BuildContext context) {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            context.t('issues.previewEmpty'),
            style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Align(
        alignment: Alignment.topLeft,
        child: HinataMarkdownPreview(markdown: text),
      ),
    );
  }
}
