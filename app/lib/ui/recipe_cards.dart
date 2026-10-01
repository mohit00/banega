import 'package:flutter/widgets.dart';

import '../core/engine/fit_engine.dart';
import '../core/l10n/gen/app_localizations.dart';
import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'badges.dart';
import 'buttons.dart';
import 'entrance.dart';
import 'icons.dart';
import 'pressable.dart';
import 'thali_hero.dart';

/// View data shared by [RecipeTile] and [RecipeMiniCard].
@immutable
class RecipeCardData {
  const RecipeCardData({
    required this.name,
    required this.cuisine,
    required this.mins,
    required this.mark,
    required this.color,
    required this.fitKind,
    required this.fitShort,
    this.note,
    this.image,
  });

  final String name;
  final String cuisine;
  final int mins;
  final DietMarkKind mark;

  /// Food colour for the katori placeholder.
  final Color color;
  final FitKind fitKind;
  final String fitShort;

  /// Mini-card note ("Dadi ke liye nahi", "Papa: kam tel mein banao").
  final String? note;

  /// Recipe photo. Falls back to a [KatoriThumb] in [color].
  final ImageProvider? image;
}

class _ImageArea extends StatelessWidget {
  const _ImageArea({required this.data, required this.height, required this.clock});

  final RecipeCardData data;
  final double height;
  final bool clock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: BColors.cream,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data.image != null)
              Image(image: data.image!, fit: BoxFit.cover, excludeFromSemantics: true)
            else
              Center(child: KatoriThumb(food: data.color)),
            Positioned(left: 8, top: 8, child: DietMark(data.mark)),
            Positioned(
              right: 8,
              top: 8,
              child: BBadge(
                label: l.minBadge(data.mins),
                background: BColors.card,
                foreground: BColors.ink2,
                leading: clock ? BIcons.clock : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid recipe tile (`.tile` on Home): 124px cream image area with diet mark
/// and "{n} MIN" badge, name 14/800 (min-height 34), cuisine 11.5/600, footer
/// with [FitBadge] and [BAddButton]. Pops in with a 70 ms stagger per [index].
class RecipeTile extends StatelessWidget {
  const RecipeTile({super.key, required this.data, required this.added, this.onOpen, this.onToggle, this.index = 0});

  final RecipeCardData data;
  final bool added;
  final VoidCallback? onOpen;
  final VoidCallback? onToggle;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Entrance.popIn(
      delay: Motion.stagger(context, index, Motion.staggerTile),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: BColors.card,
          borderRadius: BorderRadius.circular(BRadii.tile),
          border: Border.all(color: BColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pressable(
              onTap: onOpen,
              semanticLabel: data.name,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ImageArea(data: data, height: BSizes.tileImage, clock: true),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 34),
                          child: Text(
                            data.name,
                            style: BText.body(BType.cardTitle, weight: FontWeight.w800, height: 1.2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.cuisine,
                          style: BText.body(BType.cuisine, weight: FontWeight.w600, color: BColors.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: FitBadge(kind: data.fitKind, label: data.fitShort),
                    ),
                  ),
                  const SizedBox(width: 6),
                  BAddButton(added: added, onPressed: onToggle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat recipe card (`.mini`): 212 wide, 112px image, name, note, badge + ADD.
/// Flips in with a 70 ms stagger per [index].
class RecipeMiniCard extends StatelessWidget {
  const RecipeMiniCard({
    super.key,
    required this.data,
    required this.added,
    this.onOpen,
    this.onToggle,
    this.index = 0,
  });

  final RecipeCardData data;
  final bool added;
  final VoidCallback? onOpen;
  final VoidCallback? onToggle;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Entrance.flipIn(
      delay: Motion.stagger(context, index, Motion.staggerTile),
      child: Container(
        width: BSizes.miniWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: BColors.card,
          borderRadius: BorderRadius.circular(BRadii.tile),
          border: Border.all(color: BColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pressable(
              onTap: onOpen,
              semanticLabel: data.name,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ImageArea(data: data, height: BSizes.miniImage, clock: false),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data.name, style: BText.body(BType.cardTitle, weight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 32),
                          child: Text(
                            data.note ?? '',
                            style: BText.body(BType.caption, color: BColors.ink3, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: FitBadge(kind: data.fitKind, label: data.fitShort),
                    ),
                  ),
                  const SizedBox(width: 6),
                  BAddButton(added: added, onPressed: onToggle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
