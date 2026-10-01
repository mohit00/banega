import 'package:flutter/widgets.dart';

/// Tap target that reports its pressed state, with button semantics.
/// Used by components that reproduce CSS `:active` styles.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.semanticLabel,
    this.selected,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget Function(BuildContext context, bool pressed) builder;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool? selected;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: widget.builder(context, _pressed),
      ),
    );
  }
}

/// CSS `:active{transform:scale(.96)}` for chips.
class PressScale extends StatelessWidget {
  const PressScale({super.key, required this.pressed, required this.child, this.scale = .96});

  final bool pressed;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: pressed ? scale : 1,
      duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: child,
    );
  }
}
