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
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart'
    show TextFormat;

import '../../../core/lexical/hinata_editor.dart';
import '../../../core/lexical/hinata_editor_controller.dart';
import '../../../core/lexical/hinata_editing.dart';
import '../../../core/lexical/hinata_markdown_preview.dart' show markdownToDocument;
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

/// The Liquid-Glass comment composer from the design. Morphs through:
///   • idle     → [+] · field · mic
///   • typing   → mic becomes the honey-amber send button
///   • popup    → glass "+" menu (camera / gallery / attachment / format)
///   • format   → grows *in place* into the same rich editor the description
///                uses (drag-to-resize, buttons pinned along the bottom) — no
///                modal. Because the composer is always bottom-anchored in its
///                region (the phone sticky bar or the desktop comment panel's
///                footer), the editor expands *upward* with the buttons
///                staying put.
///   • recording → live-waveform voice recorder with cancel / send
///
/// The single-line row wraps a [MentionField], so `@`-mentions and smart-links
/// keep working in a one-line remark. Format mode is a [HinataEditor] with its
/// own toolbar turned off: the buttons stay in this composer's bottom row, and
/// drive the document through editor commands. The parent
/// owns the [controller] (so it can read/clear the text on submit) and handles
/// attachment picking + voice/text sending via the callbacks. When [editing] is
/// set, the composer is editing an existing comment inline — it shows a banner
/// and the parent's submit saves the edit.
class GlassCommentComposer extends StatefulWidget {
  const GlassCommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
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

  /// Posts the draft. Carries the Lexical document when format mode wrote one,
  /// and null from the single-line field, which has none.
  final void Function(String? doc) onSubmitText;
  final void Function(VoiceRecording recording) onSendVoice;
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

enum _Mode { idle, recording, format }

class _GlassCommentComposerState extends State<GlassCommentComposer> {
  _Mode _mode = _Mode.idle;

  // Format mode: the drag-resizable field height.
  double _formatHeight = 200;

  /// The document behind format mode.
  ///
  /// Created on entry from whatever is in the single-line field, and read back
  /// out as markdown on the way out — the wire format for a comment is still a
  /// markdown string, and this is a change of editor, not of API.
  HinataEditorController? _doc;


  /// Reaches the editor so this composer's own button row can drive it.
  final GlobalKey<HinataEditorState> _docKey = GlobalKey<HinataEditorState>();

  /// The buttons along the bottom, in the order they have always been in.
  ///
  /// Same icons, same row, same design — they dispatch document commands now
  /// instead of splicing markdown characters into a string.
  List<(IconData, VoidCallback)> get _docTools {
    void format(TextFormat f) => _docKey.currentState?.format(f);
    void block(BlockKind kind) => _docKey.currentState?.block(kind);
    return [
      (LucideIcons.bold, () => format(TextFormat.bold)),
      (LucideIcons.italic, () => format(TextFormat.italic)),
      (LucideIcons.strikethrough, () => format(TextFormat.strikethrough)),
      (LucideIcons.link, () => _docKey.currentState?.editLink()),
      (LucideIcons.code, () => format(TextFormat.code)),
      (LucideIcons.list, () => block(BlockKind.bulletList)),
      (LucideIcons.listOrdered, () => block(BlockKind.numberList)),
    ];
  }

  VoiceRecorder? _recorder;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  bool _starting = false;

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
    _doc?.dispose();
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
    final recorder = VoiceRecorder();
    bool ok;
    // The message matters as much as the failure: a denied microphone and a
    // desktop missing `parecord`/`ffmpeg` both stop the recording, and only one
    // of them is about permissions.
    String message = 'comments.micDenied';
    Map<String, Object>? variables;
    try {
      ok = await recorder.start();
    } on MissingRecorderTool catch (e) {
      ok = false;
      message = 'comments.recorderToolMissing';
      variables = {'tool': e.executable};
    } catch (_) {
      // Some platforms throw instead of returning false when the mic is
      // unavailable (e.g. no device / permission race) — treat as denied.
      ok = false;
    }
    _starting = false;
    if (!ok) {
      await recorder.dispose();
      if (mounted) {
        showGlassErrorToast(context, context.t(message, variables: variables));
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

  Future<void> _sendRecording() async {
    _recTimer?.cancel();
    final r = _recorder;
    _recorder = null;
    if (mounted) setState(() => _mode = _Mode.idle);
    if (r == null) return;
    VoiceRecording? recording;
    try {
      recording = await r.stop();
    } catch (_) {
      // Native stop failure / web blob read failure — fall through to the
      // error toast below rather than throwing into the void.
      recording = null;
    } finally {
      await r.dispose();
    }
    if (recording != null && recording.durationMs > 300) {
      widget.onSendVoice(recording);
    } else if (mounted) {
      // The recording bar already closed; without this the message would just
      // vanish with no explanation (stop failed, empty bytes, or too short).
      showGlassErrorToast(context, context.t('comments.voiceFailed'));
    }
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
    widget.onSubmitText(null);
  }

  /// Enters the inline Markdown editor. It replaces the single-line row and,
  /// because the composer is bottom-anchored in its region, grows *upward* when
  /// the drag handle is pulled — the toolbar stays pinned at the bottom.
  void _openFormat() {
    final draft = widget.controller.text;
    setState(() {
      _doc?.dispose();
      _doc = HinataEditorController(doc: markdownToDocument(draft));
      _mode = _Mode.format;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _docKey.currentState?.focus();
    });
  }

  /// Collapses the editor back to the single-line pill.
  ///
  /// The draft goes back into the plain field on the way out, so closing the
  /// editor never loses what was written in it.
  void _closeFormat() {
    if (!mounted) return;
    _syncDraft();
    setState(() {
      _mode = _Mode.idle;
      _doc?.dispose();
      _doc = null;
    });
  }

  /// Mirrors the rich draft's plain reading into the single-line field.
  ///
  /// The document itself is what gets posted — this is only so the collapsed
  /// pill shows what was written, and so the send button's "is there anything
  /// here" check has something to read. Nothing is converted: the plain text
  /// is the document's own, exactly as the server derives it.
  void _syncDraft() {
    final doc = _doc;
    if (doc == null) return;
    widget.controller.text = doc.hasContent ? doc.plainText.trim() : '';
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
    final canSend = _doc?.hasContent ?? false;

    return _composerSurface(
      dark: dark,
      radius: 28,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // No Edit/Preview switch any more: the editor renders what it will
          // post, so there is nothing left for a preview to reveal. It also
          // takes the reported bug with it — on a phone, switching to the
          // preview dropped the field's focus and dismissed the whole sheet,
          // so the draft could not be previewed at all.
          _DragHandle(
            onDrag: (dy) => setState(() {
              // Drag up (dy<0) grows the field; clamp to the viewport cap.
              _formatHeight = (fieldHeight - dy).clamp(140.0, maxField);
            }),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: fieldHeight,
            child: HinataEditor(
              key: _docKey,
              controller: _doc!,
              autofocus: true,
              // The controls live along the bottom of the sheet, in the row
              // this composer has always drawn. A second strip above the text
              // is the one thing this rebuild must not introduce.
              showToolbar: false,
              framed: false,
              placeholderKey: 'comments.placeholder',
              fontSize: 14,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          ),
          const SizedBox(height: 8),
          _FormatToolbar(
            tools: _docTools,
            canSend: canSend,
            onClose: _closeFormat,
            onSend: () {
              if (!canSend) return;
              _syncDraft();
              // The document, not a rendering of it: callouts, smart links,
              // images and tables have no markdown to survive as.
              widget.onSubmitText(_doc?.doc);
              _closeFormat();
            },
          ),
        ],
      ),
    );
  }


}
