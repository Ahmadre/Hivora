import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'hex_mark.dart';
import 'soft_card.dart';

/// Brand empty-state used across every surface: the amber HexMark signet over
/// a title and a soft caption, centred inside a [SoftCard]. Mirrors the v2
/// design `.empty` block (HexMark size 40, accent-line stroke).
///
/// Pass [card] = false to drop the surrounding [SoftCard] when the caller
/// already provides its own card/container.
class HiveEmptyState extends StatelessWidget {
  const HiveEmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.card = true,
    this.padding = const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
  });

  final String title;
  final String? message;
  final Widget? action;
  final bool card;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const HexMark(size: 40, color: AppColors.accentLine),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
    if (!card) return Center(child: content);
    return SoftCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: Center(child: content),
      ),
    );
  }
}
