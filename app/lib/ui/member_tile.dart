import 'package:flutter/widgets.dart';

import '../core/motion/motion.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'avatar.dart';
import 'badges.dart';
import 'entrance.dart';
import 'icons.dart';
import 'pressable.dart';

/// Family screen member row (`.tile` row variant): 46px avatar, name 16/800,
/// diet badge on paper, one-line summary 12.5/500 with ellipsis, chevron.
/// Pops in with a 60 ms stagger per [index].
class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.name,
    required this.initial,
    required this.color,
    required this.dietLabel,
    required this.summary,
    this.onTap,
    this.index = 0,
  });

  final String name;
  final String initial;
  final Color color;
  final String dietLabel;
  final String summary;
  final VoidCallback? onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Entrance.popIn(
      delay: Motion.stagger(context, index, Motion.staggerMember),
      child: Pressable(
        onTap: onTap,
        semanticLabel: '$name, $dietLabel. $summary',
        builder: (context, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BColors.card,
            borderRadius: BorderRadius.circular(BRadii.tile),
            border: Border.all(color: BColors.border),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                BAvatar(initial: initial, color: color, size: 46, fontSize: 17),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BText.body(BType.memberName, weight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          BBadge(label: dietLabel),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        summary,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: BText.body(BType.captionL, color: BColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const BIcon(BIcons.chevronRight, size: 18, color: BColors.ink4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
