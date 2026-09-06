part of 'comment_thread.dart';

/// Text comment body — the stored document, rendered.
///
/// Flat, on a transparent background (no bubble); the timestamp lives in the
/// row header, and the block rhythm is tightened because the renderer pads
/// below the last block too.
class _TextBody extends StatelessWidget {
  const _TextBody({required this.comment});

  final IssueComment comment;

  /// Comments read at a smaller size than an article does.
  static const double _fontSize = 14;

  @override
  Widget build(BuildContext context) {
    // A comment written before the format change, or one whose document failed
    // to convert, still has its plain text — showing that beats showing nothing.
    if ((comment.textDoc ?? '').isEmpty) {
      if (comment.text.trim().isEmpty) return const SizedBox.shrink();
      return Text(
        comment.text,
        style: TextStyle(
          fontFamily: AppTheme.fontUi,
          fontSize: _fontSize,
          height: 1.35,
          color: AppColors.ink,
        ),
      );
    }

    return HinataDocument(
      doc: comment.textDoc,
      fontSize: _fontSize,
      // Tight: a comment row is close quarters, and the renderer pads below the
      // last block too — the default rhythm would read as a gap before the
      // reactions.
      blockSpacing: 4,
    );
  }
}

/// A playable voice message: amber play/pause, tappable/scrubbable waveform and
/// a live-updating timecode. Audio is fetched lazily on first play.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.voice, required this.loader});

  final CommentVoice voice;
  final VoiceAudioLoader loader;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  late VoicePlaybackController _controller = VoicePlaybackController(
    loader: widget.loader,
    fallbackDuration: widget.voice.duration,
  );

  /// Whether the current failure has already been put into words, so a retry
  /// that fails the same way does not stack a second identical toast.
  bool _explained = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_explainFailure);
  }

  /// Says *why* a bubble refuses to play, once.
  ///
  /// The button already flips to a retry glyph, which shows that something went
  /// wrong and nothing about what. Only one failure is worth spelling out, and
  /// it is the one a user can fix: a Linux desktop without GStreamer's base
  /// plugins cannot build a pipeline at all, and that is one package away from
  /// working.
  void _explainFailure() {
    if (!_controller.failed) {
      _explained = false;
      return;
    }
    final key = _controller.failureKey;
    if (key == null || _explained) return;
    _explained = true;
    // After the frame: this runs from the controller's own notification, and
    // the toast inserts itself into an overlay that is about to rebuild for
    // the same notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showGlassErrorToast(context, context.t(key));
    });
  }

  @override
  void didUpdateWidget(VoiceBubble old) {
    super.didUpdateWidget(old);
    // If Flutter reuses this State for a different comment (the keyless 'All'
    // feed can reconcile adjacent voice rows by position after a live reorder),
    // rebuild the controller so a fresh, idle player fetches the new clip
    // instead of replaying the previous comment's audio.
    if (old.voice != widget.voice || old.loader != widget.loader) {
      _controller.removeListener(_explainFailure);
      _controller.dispose();
      _controller = VoicePlaybackController(
        loader: widget.loader,
        fallbackDuration: widget.voice.duration,
      )..addListener(_explainFailure);
      _explained = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_explainFailure);
    _controller.dispose();
    super.dispose();
  }

  String _mmss(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final playing = _controller.playing;
        final loading = _controller.loading;
        final elapsed = _controller.position.inMilliseconds > 0
            ? _controller.position
            : Duration.zero;
        final total = _controller.duration;
        final timeStyle = TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10.5,
          color: AppColors.inkFaint,
        );
        return SizedBox(
          width: 230,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Play button and waveform share one centred row, so the play
              // glyph sits exactly on the waveform's centre line (WhatsApp-style
              // — the 40px button and 30px waveform both centre to the row).
              Row(
                children: [
                  _PlayButton(
                    playing: playing,
                    loading: loading,
                    failed: _controller.failed,
                    onTap: _controller.toggle,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: _Waveform(
                        peaks: widget.voice.peaks,
                        progress: _controller.progress,
                        onSeek: _controller.seekFraction,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Timecodes below the waveform, indented past the play button
              // (40px button + 11px gap) so they align under the peaks.
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 51),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _mmss(
                        playing || elapsed > Duration.zero ? elapsed : total,
                      ),
                      style: timeStyle,
                    ),
                    Text(_mmss(total), style: timeStyle),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2A2410),
                  ),
                )
              : Icon(
                  failed
                      ? LucideIcons.rotateCw
                      : (playing ? LucideIcons.pause : LucideIcons.play),
                  size: 18,
                  color: const Color(0xFF2A2410),
                ),
        ),
      ),
    );
  }
}

/// Waveform bars: amber up to [progress], muted after; tap or drag to scrub.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.peaks,
    required this.progress,
    required this.onSeek,
  });

  final List<int> peaks;
  final double progress;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final idle = dark ? const Color(0x3DFFFFFF) : const Color(0x33000000);
    final bars = peaks.isEmpty ? List<int>.filled(36, 30) : peaks;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx) =>
            onSeek((dx / constraints.maxWidth).clamp(0.0, 1.0));
        // A CustomPaint keeps the static peaks out of the widget rebuild: the
        // enclosing AnimatedBuilder ticks many times a second during playback,
        // but only `progress` changes, so the painter just repaints the fill
        // instead of reconstructing ~36 Container widgets each frame.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          child: CustomPaint(
            size: Size.infinite,
            painter: _WaveformPainter(
              bars: bars,
              progress: progress,
              fill: AppColors.accent,
              idle: idle,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.fill,
    required this.idle,
  });

  final List<int> bars;
  final double progress;
  final Color fill;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final n = bars.length;
    final cellW = size.width / n;
    const hPad = 0.8; // matches the former per-bar horizontal padding
    final barW = (cellW - hPad * 2).clamp(0.0, cellW);
    final fillPaint = Paint()..color = fill;
    final idlePaint = Paint()..color = idle;
    for (var i = 0; i < n; i++) {
      final h = (4 + bars[i] / 100 * 26).clamp(4, 30).toDouble();
      final cx = i * cellW + cellW / 2;
      final top = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, top, barW, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, (i + 0.5) / n <= progress ? fillPaint : idlePaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.idle != idle ||
      !identical(old.bars, bars);
}

/// Local time as `HH:mm` (24h). Comments store UTC; display in the device zone.
String hhmm(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
