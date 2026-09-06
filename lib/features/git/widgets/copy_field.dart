import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// A single-line, horizontally-scrollable mono command box with a copy button
/// that ticks green — the reference `.cf`. The command **never wraps or clips**
/// (it scrolls), so long branch names / commands can't overflow the narrow
/// right rail at any width.
class CopyField extends StatefulWidget {
  const CopyField({super.key, required this.text, this.onCopied});

  final String text;

  /// Called after the value is placed on the clipboard (e.g. to toast).
  final VoidCallback? onCopied;

  @override
  State<CopyField> createState() => _CopyFieldState();
}

class _CopyFieldState extends State<CopyField> {
  bool _done = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    widget.onCopied?.call();
    setState(() => _done = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _done = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // A fixed height keeps the row's cross-axis bounded so the trailing button
    // can stretch to a full-height divider. Without it, `stretch` inside the
    // issue sheet's vertical scroll (unbounded height) forces an infinite height
    // and crashes with "BoxConstraints forces an infinite height".
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.text,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 12,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
          _CopyButton(done: _done, onTap: _copy),
        ],
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.hairline)),
          ),
          child: Icon(
            done ? LucideIcons.check : LucideIcons.copy,
            size: 15,
            color: done ? AppColors.success : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}
