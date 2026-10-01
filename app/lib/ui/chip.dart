import 'package:flutter/widgets.dart';

import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'pressable.dart';

/// Chip (`.chip` / `.chip.on`): 36 high, pill, 1px #DEDFD6 border, 13/600.
/// Selected: #E7F4EA fill, green border, #0A5E2C text.
///
/// Size/shape overrides cover the prototype's variants (diet chips are 52 high
/// with 14 radius; member tabs are 44 high with 5px left padding).
class BChip extends StatelessWidget {
  const BChip({
    super.key,
    this.label,
    this.child,
    this.selected = false,
    this.onTap,
    this.leading,
    this.height = BSizes.chip,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.radius = BRadii.pill,
    this.alignment = MainAxisAlignment.center,
    this.borderColor,
    this.foreground,
    this.semanticLabel,
    this.fill = false,
  }) : assert(label != null || child != null);

  final String? label;

  /// Custom content (replaces [label]); inherits the chip's text style.
  final Widget? child;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final double height;
  final EdgeInsetsGeometry padding;
  final double radius;
  final MainAxisAlignment alignment;

  /// Resting border/text overrides (chat follow-up chips are green-outlined).
  final Color? borderColor;
  final Color? foreground;
  final String? semanticLabel;

  /// Set when the chip has a bounded width (e.g. grid cells): the content then
  /// shrinks with an ellipsis instead of overflowing.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? BColors.greenDark : (foreground ?? BColors.ink2);
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: semanticLabel ?? label,
      builder: (context, pressed) => PressScale(
        pressed: pressed,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.chip),
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? BColors.fitBg : BColors.card,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: selected ? BColors.green : (borderColor ?? BColors.chipBorder)),
          ),
          child: DefaultTextStyle(
            style: BText.body(BType.chip, weight: FontWeight.w600, color: fg),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: ExcludeSemantics(
              excluding: semanticLabel != null || label != null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: alignment,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 6)],
                  if (fill) Flexible(child: child ?? Text(label!)) else child ?? Text(label!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One option of a [BSegmentControl].
class BSegment<T> {
  const BSegment(this.value, this.label, {this.leading});
  final T value;
  final String label;
  final Widget? leading;
}

/// Segmented control (`.seg`): a 4px-padded 14-radius track with 40-high,
/// 10-radius segments (13/700 #55544E); the selected one is white with ink
/// text and a soft shadow.
class BSegmentControl<T> extends StatelessWidget {
  const BSegmentControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.trackColor = BColors.segBg,
  });

  final List<BSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// #E9EAE2 on Home, #F4F5EF (paper) on Prefs.
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final dur = Motion.of(context, Motion.seg);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: trackColor, borderRadius: BorderRadius.circular(BRadii.cta)),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Pressable(
                onTap: () => onChanged(segments[i].value),
                selected: segments[i].value == value,
                semanticLabel: segments[i].label,
                builder: (context, pressed) {
                  final on = segments[i].value == value;
                  return AnimatedContainer(
                    duration: dur,
                    height: BSizes.seg,
                    decoration: BoxDecoration(
                      color: on ? BColors.card : BColors.card.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(BRadii.small),
                      boxShadow: on ? BShadows.segOn : const [],
                    ),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (segments[i].leading != null) ...[segments[i].leading!, const SizedBox(width: 4)],
                          Flexible(
                            child: AnimatedDefaultTextStyle(
                              duration: dur,
                              style: BText.body(
                                BType.chip,
                                weight: FontWeight.w700,
                                color: on ? BColors.ink : BColors.ink3,
                              ),
                              child: Text(segments[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
