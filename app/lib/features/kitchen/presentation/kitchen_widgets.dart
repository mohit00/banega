import 'package:flutter/material.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../domain/kitchen_models.dart';

/// Ticket status pill (Naya / Accept ho gaya / Ban raha hai / …).
class TicketStatusChip extends StatelessWidget {
  const TicketStatusChip({super.key, required this.status, this.large = false});

  final TicketStatus status;

  /// Cook-mode size (16/800, 32 high).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = ticketStatusColours(status);
    final label = AppLocalizations.of(context).ticketStatus(status);
    return Container(
      key: ValueKey('status-${status.wire}'),
      constraints: BoxConstraints(minHeight: large ? 32 : BSizes.badge),
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(large ? BRadii.small : BRadii.badge)),
      child: Text(
        label,
        style: BText.body(large ? 16 : BType.badge, weight: FontWeight.w800, color: fg),
      ),
    );
  }
}

/// Stock pill on a Saaman row: Hai / Kam hai / Khatam / Pata nahi.
class ItemStatusPill extends StatelessWidget {
  const ItemStatusPill({super.key, required this.status, this.large = false});

  final ItemStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = itemStatusColours(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 4 : 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(BRadii.pill)),
      child: Text(
        AppLocalizations.of(context).itemStatus(status),
        style: BText.body(large ? 16 : BType.badge, weight: FontWeight.w800, color: fg),
      ),
    );
  }
}

/// Small tag ("Badla gaya", "Bheja nahi gaya", "Saaman khatam").
class KitchenTag extends StatelessWidget {
  const KitchenTag({super.key, required this.label, this.icon, this.large = false});

  final String label;
  final BIconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 4 : 2),
      decoration: BoxDecoration(color: BColors.noBg, borderRadius: BorderRadius.circular(BRadii.badge)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[BIcon(icon!, size: large ? 16 : 12, color: BColors.noFg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              style: BText.body(large ? 16 : BType.badge, weight: FontWeight.w800, color: BColors.noFg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading used on Plan and ticket detail (15/800).
class KitchenSectionTitle extends StatelessWidget {
  const KitchenSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: BText.body(BType.sectionLabel, weight: FontWeight.w800)),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// White bordered card (16 radius).
class KitchenCard extends StatelessWidget {
  const KitchenCard({super.key, required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: BColors.card,
        borderRadius: BorderRadius.circular(BRadii.tile),
        border: Border.all(color: BColors.border),
      ),
      child: child,
    );
  }
}

/// Haldi header with a back button and a title (+ optional subtitle).
class KitchenHeader extends StatelessWidget {
  const KitchenHeader({super.key, required this.title, this.subtitle, this.onBack, this.trailing, this.titleSize});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final double? titleSize;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      color: BColors.haldi,
      padding: EdgeInsets.fromLTRB(14, 12 + topInset, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BIconButton(
                icon: BIcons.chevronLeft,
                semanticLabel: l.back,
                background: BColors.card.withValues(alpha: .55),
                onPressed: onBack,
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: BText.display(titleSize ?? BType.h1Alt, height: 1.05)),
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              style: BText.body(13.5, weight: FontWeight.w600, color: BColors.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

/// −/+ stepper for small counts (guests, servings override).
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    this.onLess,
    this.onMore,
    required this.lessLabel,
    required this.moreLabel,
    this.width = 48,
  });

  final String value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;
  final String lessLabel;
  final String moreLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    Widget button(BIconData icon, String label, VoidCallback? onTap) => Opacity(
      opacity: onTap == null ? .4 : 1,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, pressed) => PressScale(
          pressed: pressed,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BColors.addBg,
                borderRadius: BorderRadius.circular(BRadii.add),
                border: Border.all(color: BColors.green, width: 1.5),
              ),
              child: BIcon(icon, size: 16, color: BColors.green),
            ),
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(BIcons.minus, lessLabel, onLess),
        SizedBox(
          width: width,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: BText.body(BType.body, weight: FontWeight.w800),
          ),
        ),
        button(BIcons.plus, moreLabel, onMore),
      ],
    );
  }
}
