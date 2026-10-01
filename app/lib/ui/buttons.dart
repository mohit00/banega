import 'package:flutter/widgets.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'icons.dart';
import 'pressable.dart';

/// Primary CTA (`.cta`): 52 high, green, 14 radius, 16/800 white, with a
/// `0 4px 0 #095A29` bottom shadow that collapses to 1px and moves the
/// button down 3px while pressed.
class BCta extends StatelessWidget {
  const BCta({super.key, required this.label, this.onPressed, this.trailing, this.leading, this.expand = true});

  final String label;
  final VoidCallback? onPressed;

  /// Optional icon before the label (Plan's send arrow).
  final BIconData? leading;

  /// Optional icon after the label (e.g. [BIcons.arrowRight]).
  final BIconData? trailing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final dur = Motion.of(context, Motion.press);
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Pressable(
        onTap: onPressed,
        semanticLabel: label,
        builder: (context, pressed) => AnimatedContainer(
          duration: dur,
          // 52 minimum; at large text sizes the label wraps to two lines and
          // the button grows instead of clipping.
          constraints: const BoxConstraints(minHeight: BSizes.cta),
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: expand ? 12 : 20, vertical: 6),
          transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0),
          decoration: BoxDecoration(
            color: BColors.green,
            borderRadius: BorderRadius.circular(BRadii.cta),
            boxShadow: pressed ? BShadows.ctaPressed : BShadows.ctaRest,
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[BIcon(leading!, size: 18, color: BColors.card), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: BText.body(BType.cta, weight: FontWeight.w800, color: BColors.card),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), BIcon(trailing!, size: 18, color: BColors.card)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary outline button (`.ghost`): 52 high, 1.5px green border, 15/800.
class BGhostButton extends StatelessWidget {
  const BGhostButton({super.key, required this.label, this.onPressed, this.leading, this.trailing});

  final String label;
  final VoidCallback? onPressed;
  final BIconData? leading;

  /// Icon after the label (Detail's "Video recipe ↗").
  final BIconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, pressed) => Container(
        height: BSizes.cta,
        decoration: BoxDecoration(
          color: BColors.card,
          borderRadius: BorderRadius.circular(BRadii.cta),
          border: Border.all(color: BColors.green, width: 1.5),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[BIcon(leading!, size: 18, color: BColors.green), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BText.body(BType.ghost, weight: FontWeight.w800, color: BColors.green),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), BIcon(trailing!, size: 16, color: BColors.green)],
            ],
          ),
        ),
      ),
    );
  }
}

/// ADD / ADDED toggle (`.add`): 32 high, min 68 wide, 8 radius.
class BAddButton extends StatelessWidget {
  const BAddButton({super.key, required this.added, this.onPressed});

  final bool added;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = added ? l.addedLabel : l.addLabel;
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      selected: added,
      builder: (context, pressed) => AnimatedContainer(
        duration: Motion.of(context, Motion.chip),
        height: BSizes.add,
        constraints: const BoxConstraints(minWidth: BSizes.addMinWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: added ? BColors.green : BColors.addBg,
          borderRadius: BorderRadius.circular(BRadii.add),
          border: Border.all(color: BColors.green, width: 1.5),
        ),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: BText.body(BType.chip, weight: FontWeight.w800, color: added ? BColors.card : BColors.green),
          ),
        ),
      ),
    );
  }
}

/// 44×44 square icon button (back buttons etc.).
class BIconButton extends StatelessWidget {
  const BIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.background = BColors.paper,
    this.size = BSizes.iconButton,
    this.iconSize = 20,
    this.iconColor = BColors.ink,
  });

  final BIconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color background;
  final double size;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      builder: (context, pressed) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(BRadii.icon)),
        child: BIcon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

/// Plain text button (e.g. "Demo family ke saath dekho"): 44 high, 14/700.
class BTextButton extends StatelessWidget {
  const BTextButton({super.key, required this.label, this.onPressed, this.color = BColors.ink2});

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, pressed) => SizedBox(
        height: BSizes.iconButton,
        child: Center(
          child: ExcludeSemantics(
            child: Text(
              label,
              style: BText.body(BType.body, weight: FontWeight.w700, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
