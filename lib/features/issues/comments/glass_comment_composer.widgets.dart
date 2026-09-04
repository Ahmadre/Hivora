part of 'glass_comment_composer.dart';

// ── circle buttons ─────────────────────────────────────────────────────────
/// A round composer button. The honey-amber [send] state is intentionally solid
/// accent; every other state is real Liquid Glass ([GlassButton]) so it refracts
/// like the rest of the app's chrome.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    this.onTap,
    this.send = false,
    this.danger = false,
    this.size = 52,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool send;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;

    // Solid accent send button.
    if (send) {
      final decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE7B24A), AppColors.accent, AppColors.accentStrong],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.5),
            blurRadius: 16,
            spreadRadius: -5,
            offset: const Offset(0, 6),
          ),
        ],
      );
      return Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: decoration,
            child: Icon(icon, size: 22, color: _onAccent),
          ),
        ),
      );
    }

    // Real Liquid Glass for the idle "+", mic, trash and format-close buttons —
    // pinned to the standard (lightweight) shader so it renders correctly over
    // the scrolling feed and on rotation, unlike the default premium pipeline.
    //
    // Shape: a superellipse with radius = size/2 (a perfect circle), NOT the
    // default LiquidOval. An oval glass surface is clipped with ClipPath, which
    // the engine can't forward to the descendant BackdropFilter layer — so the
    // backdrop blur stays a rectangle behind the circle and its vertical edges
    // leak as faint seams beside the button (worst over the bright desktop/web
    // footer). ClipRRect (used for the superellipse) forwards the clip, killing
    // the halo. See lightweight_liquid_glass.dart's LiquidOval note.
    return GlassButton(
      icon: Icon(icon, size: 22),
      iconColor: danger ? AppColors.danger : AppColors.ink,
      onTap: onTap ?? () {},
      enabled: onTap != null,
      width: size,
      height: size,
      iconSize: 22,
      shape: LiquidRoundedSuperellipse(borderRadius: size / 2),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _composerGlass(dark),
      glowColor: AppColors.accent,
      stretch: 0.15,
    );
  }
}

/// Inline-edit banner shown above the composer while editing an existing
/// comment, with a quick way to abandon the edit.
class _EditingBanner extends StatelessWidget {
  const _EditingBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          const Icon(
            LucideIcons.pencil,
            size: 14,
            color: AppColors.accentStrong,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.t('comments.editingComment'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          InkWell(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                context.t('common.cancel'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// WhatsApp-style "replying to …" quote bar shown above the composer field: an
/// accent rule, the replied-to author and a one-line preview, plus a dismiss.
class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({
    required this.name,
    required this.preview,
    required this.onCancel,
  });

  final String name;
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(9),
          border: const Border(
            left: BorderSide(color: AppColors.accent, width: 3),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            const Icon(
              LucideIcons.reply,
              size: 14,
              color: AppColors.accentStrong,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t('comments.replyingTo', variables: {'name': name}),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentStrong,
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onCancel,
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ── drag handle (format mode only) ──────────────────────────────────────────
/// Grip shown above the editor while formatting: drag up to grow the text area,
/// down to shrink it.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDrag});

  final void Function(double dy) onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.inkFaint.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── "+" action popup ────────────────────────────────────────────────────────
class _ActionPopup extends StatelessWidget {
  const _ActionPopup({required this.onPick, required this.onFormat});

  final void Function(ComposerAttach kind) onPick;
  final VoidCallback onFormat;

  @override
  Widget build(BuildContext context) {
    // No glass here: this content is rendered directly inside the
    // [GlassPopover]'s morphing glass container, which supplies the tint, blur
    // and the metaball shape. Wrapping it in our own [_composerSurface] would
    // double-stack the glass. mainAxisSize.min so the popover can measure the
    // intrinsic height and morph to exactly the right size.
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ask the active image_picker implementation instead of testing the
            // platform: on desktop the camera works only once a
            // cameraDelegate is installed (see desktop_camera_delegate.dart),
            // and `supportsImageSource` reports exactly that. Offering the row
            // unconditionally used to throw a StateError on Windows/Linux and
            // on any desktop build without the delegate.
            if (ImagePickerPlatform.instance.supportsImageSource(
              ImageSource.camera,
            ))
              _row(
                context,
                LucideIcons.camera,
                context.t('comments.actionCamera'),
                () => onPick(ComposerAttach.camera),
              ),
            _row(
              context,
              LucideIcons.image,
              context.t('comments.actionGallery'),
              () => onPick(ComposerAttach.gallery),
            ),
            _row(
              context,
              LucideIcons.paperclip,
              context.t('comments.actionFile'),
              () => onPick(ComposerAttach.file),
            ),
            _row(
              context,
              LucideIcons.baseline,
              context.t('comments.actionFormat'),
              onFormat,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Icon(icon, size: 22, color: AppColors.inkSoft),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Markdown format toolbar ─────────────────────────────────────────────────
class _FormatToolbar extends StatelessWidget {
  const _FormatToolbar({
    required this.tools,
    required this.canSend,
    required this.onClose,
    required this.onSend,
  });

  /// The formatting buttons, left to right. Supplied by the composer so this
  /// row does not care whether it is driving markdown or a document.
  final List<(IconData, VoidCallback)> tools;
  final bool canSend;
  final VoidCallback onClose;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: LucideIcons.x, size: 46, onTap: onClose),
        const SizedBox(width: 5),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (icon, run) in tools)
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      onTap: run,
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(
                        height: 44,
                        child: Icon(icon, size: 19, color: AppColors.inkSoft),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        _CircleButton(
          icon: LucideIcons.send,
          size: 46,
          send: true,
          onTap: canSend ? onSend : null,
        ),
      ],
    );
  }
}

/// Segmented Editor / Preview switcher shown top-right in the format editor.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.amplitude,
    required this.buttonSize,
    required this.onCancel,
    required this.onSend,
  });

  final Duration elapsed;
  final Stream<double> amplitude;
  final double buttonSize;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final s = elapsed.inMilliseconds ~/ 1000;
    final tenths = (elapsed.inMilliseconds % 1000) ~/ 100;
    final time = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')},$tenths';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CircleButton(
          icon: LucideIcons.trash2,
          size: buttonSize,
          danger: true,
          onTap: onCancel,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _composerSurface(
            dark: dark,
            radius: 26,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const _PulsingDot(),
                const SizedBox(width: 12),
                Text(
                  time,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _LiveWave(amplitude: amplitude)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        _CircleButton(
          icon: LucideIcons.send,
          size: buttonSize,
          send: true,
          onTap: onSend,
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
      child: Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(
          color: Color(0xFFE5675C),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Scrolling live waveform driven by the recorder's amplitude stream (newest
/// bars on the right, WhatsApp-style).
class _LiveWave extends StatefulWidget {
  const _LiveWave({required this.amplitude});

  final Stream<double> amplitude;

  @override
  State<_LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<_LiveWave> {
  final List<double> _bars = [];
  StreamSubscription<double>? _sub;

  /// Each bar is 3px wide + 1px margin either side (see [_barSlot]). Capped so a
  /// long recording doesn't grow an unbounded backing list.
  static const double _barSlot = 5;
  static const int _hardCap = 60;

  @override
  void initState() {
    super.initState();
    _sub = widget.amplitude.listen((v) {
      if (!mounted) return;
      setState(() {
        _bars.add(v);
        if (_bars.length > _hardCap) _bars.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fit the bar count to the space the Expanded actually hands us, so the
    // waveform never overruns the pill (the timer/dot leave little room on a
    // narrow phone). Newest bars stay on the right; older ones scroll off.
    return LayoutBuilder(
      builder: (context, constraints) {
        final capacity = constraints.maxWidth.isFinite
            ? (constraints.maxWidth ~/ _barSlot).clamp(0, _hardCap)
            : _hardCap;
        final visible = _bars.length > capacity
            ? _bars.sublist(_bars.length - capacity)
            : _bars;
        return SizedBox(
          height: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final v in visible)
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: (4 + v * 24).clamp(4, 28).toDouble(),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
