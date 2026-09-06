import 'package:flutter/material.dart';

/// Keeps the docked comment composer mounted only while the keyboard on screen
/// is the composer's *own*.
///
/// The composer is docked at the bottom of the issue sheet, in a subtree of its
/// own (Wolt's sticky action bar, or the route's `Stack` overlay). Wolt lifts
/// that bar above the keyboard whenever *any* field in the sheet is focused,
/// which is wrong here: with the keyboard up for a sub-task, a linked issue or
/// the inline title, the composer would ride above it for no reason. So while a
/// foreign keyboard is up, the dock takes itself out of the tree.
///
/// **"Ours" means the whole composer, not one field.** The guard used to ask the
/// single-line field's [FocusNode], and format mode swaps that field out for the
/// rich editor — so the instant the editor raised the keyboard, the dock decided
/// the keyboard was somebody else's and unmounted itself, taking the editor with
/// it. From a cold start (nothing focused, keyboard down) that is the whole
/// interaction: tap `+`, tap "Text formatting", watch the editor flash up and
/// vanish as its own keyboard evicts it.
///
/// Asking a [Focus] node wrapped around the entire dock fixes that by
/// construction: [FocusNode.hasFocus] is true when the node *or any descendant*
/// holds primary focus, so every field the composer will ever grow — the pill,
/// the editor, whatever comes next — answers "ours" without being enumerated
/// here. The node cannot take focus itself and is skipped by traversal; it is a
/// listening post, not a stop on the way to the field.
///
/// The keyboard height is read from [View], not from `MediaQuery.viewInsetsOf`:
/// Wolt hosts the sheet in a `Scaffold` with `resizeToAvoidBottomInset`, which
/// strips the bottom inset from this subtree's MediaQuery, so MediaQuery reports
/// zero here even with the keyboard up. The physical view inset is immune to
/// that — and since reading it creates no dependency, this listens to the
/// metrics itself rather than waiting to be rebuilt.
class ComposerKeyboardGate extends StatefulWidget {
  const ComposerKeyboardGate({super.key, required this.child});

  final Widget child;

  @override
  State<ComposerKeyboardGate> createState() => _ComposerKeyboardGateState();
}

class _ComposerKeyboardGateState extends State<ComposerKeyboardGate>
    with WidgetsBindingObserver {
  /// Wraps the dock so its descendants' focus reads as the composer's own.
  final _dockFocus = FocusNode(debugLabel: 'composer dock');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Focus can move without the keyboard moving — tapping a sub-task field
    // while the comment field already has it open. Without this the gate would
    // only re-decide when the keyboard animates, which is what let the old
    // guard look like it worked from a warm start and fail from a cold one.
    _dockFocus.addListener(_reconsider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dockFocus.removeListener(_reconsider);
    _dockFocus.dispose();
    super.dispose();
  }

  /// The keyboard rising or falling changes the answer.
  @override
  void didChangeMetrics() => _reconsider();

  void _reconsider() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keyboardUp = View.of(context).viewInsets.bottom > 0;
    if (keyboardUp && !_dockFocus.hasFocus) return const SizedBox.shrink();
    return Focus(
      focusNode: _dockFocus,
      canRequestFocus: false,
      skipTraversal: true,
      child: widget.child,
    );
  }
}
