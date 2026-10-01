import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/motion/motion.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models.dart';
import '../../../labels/labels.dart';
import '../../../ui/ui.dart';
import '../../account/application/account_providers.dart';
import '../../account/domain/account_models.dart';
import '../../account/presentation/paywall_screen.dart';
import '../../kitchen/domain/kitchen_models.dart' show slotFromKey;
import '../../menu/application/day_menu.dart';
import '../application/recipe_providers.dart';

/// S7 — Recipe detail (prototype DETAIL): 290px Ken Burns image, meta line,
/// H1, sub, household fit badge, "Kaun khayega", "Saaman" scaled by a
/// servings stepper, "Kaise banega" steps, and a "Video recipe" /
/// "Menu mein daalo" footer.
class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId, this.menuDate, this.menuSlot});

  final String recipeId;

  /// The day menu "Menu mein daalo" edits (`YYYY-MM-DD` + slot wire key, set
  /// when opened from Plan); null → Home's (date, slot).
  final String? menuDate;
  final String? menuSlot;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  /// Null until the user touches the stepper (then the household default).
  int? _servings;

  /// Last loaded detail, shown while a new servings count loads (API mode).
  RecipeDetail? _last;

  static const _minServings = 1;
  static const _maxServings = 30;

  MenuKey? _menuKey() {
    final d = widget.menuDate == null ? null : DateTime.tryParse(widget.menuDate!);
    final s = widget.menuSlot == null ? null : slotFromKey(widget.menuSlot!);
    return d == null || s == null ? null : menuKey(d, s);
  }

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final int servings = _servings ?? ref.watch(defaultServingsProvider);
    final async = ref.watch(recipeDetailProvider((widget.recipeId, servings)));
    final detail = async.value ?? _last;
    if (async.value != null) _last = async.value;
    final key = _menuKey();
    final inMenu = (ref.watch(dayMenuProvider)[key ?? ref.watch(homeMenuKeyProvider)] ?? const <MenuEntry>[]).any(
      (e) => e.id == widget.recipeId,
    );
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (detail == null) {
      return Scaffold(
        backgroundColor: BColors.card,
        body: Stack(
          children: [
            if (async.hasError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.homeLoadError, style: BText.display(BType.section)),
                      const SizedBox(height: 10),
                      BChip(
                        label: l.retry,
                        onTap: () => ref.invalidate(recipeDetailProvider((widget.recipeId, servings))),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(height: 290 + top, color: BColors.cream),
            Positioned(
              left: 14,
              top: 14 + top,
              child: _BackButton(onPressed: _back),
            ),
          ],
        ),
      );
    }

    void setServings(int n) => setState(() => _servings = n.clamp(_minServings, _maxServings));

    return Scaffold(
      backgroundColor: BColors.card,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: 290 + top,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: BColors.cream,
                        child: KenBurns(
                          child: detail.imageUrl != null
                              ? Image.network(detail.imageUrl!, fit: BoxFit.cover, excludeFromSemantics: true)
                              : Padding(
                                  padding: EdgeInsets.only(top: top),
                                  child: Center(child: KatoriThumb(food: detail.colour, diameter: 150)),
                                ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14 + top,
                        child: _BackButton(onPressed: _back),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(18, 18, 18, 130 + bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleBlock(detail: detail),
                      const SizedBox(height: 20),
                      _FitsBlock(fits: detail.fits),
                      if (ref.watch(ratingSummaryProvider(detail.id)).value case final rating?) ...[
                        const SizedBox(height: 16),
                        _HomeRating(summary: rating),
                      ],
                      const SizedBox(height: 20),
                      _SaamanBlock(
                        detail: detail,
                        servings: servings,
                        onLess: servings > _minServings ? () => setServings(servings - 1) : null,
                        onMore: servings < _maxServings ? () => setServings(servings + 1) : null,
                      ),
                      const SizedBox(height: 20),
                      _StepsBlock(steps: detail.steps),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 18 + bottom),
              decoration: const BoxDecoration(
                color: BColors.card,
                border: Border(top: BorderSide(color: BColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: BGhostButton(
                      label: l.videoRecipe,
                      trailing: BIcons.arrowUpRight,
                      onPressed: () async {
                        final ok = await openExternal(
                          ref.read(urlLauncherProvider),
                          videoUriFor(detail.name, detail.videoUrl),
                        );
                        if (!ok && context.mounted) BToast.show(context, l.videoOpenFailed);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 13,
                    child: BCta(
                      label: inMenu ? l.menuMeinHai : l.menuMeinDaalo,
                      onPressed: () => guardWrite(
                        context,
                        ref,
                        () => ref.read(dayMenuProvider.notifier).toggle(detail.id, detail.name, key: key),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating white 44×44 back button with `0 2px 6px rgba(27,27,24,.12)`.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BRadii.icon),
        boxShadow: const [BoxShadow(color: Color(0x1F1B1B18), offset: Offset(0, 2), blurRadius: 6)],
      ),
      child: BIconButton(
        icon: BIcons.chevronLeft,
        semanticLabel: AppLocalizations.of(context).back,
        background: BColors.card,
        onPressed: onPressed,
      ),
    );
  }
}

/// `.kb`: 14 s ease-in-out alternate, scale 1.02 → 1.14 and translate −2%.
/// Static at the first frame under reduce-motion.
class KenBurns extends StatefulWidget {
  const KenBurns({super.key, required this.child, this.duration = const Duration(seconds: 14)});

  final Widget child;
  final Duration duration;

  @override
  State<KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<KenBurns> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _t,
          child: widget.child,
          builder: (context, child) {
            final v = _t.value;
            final scale = 1.02 + .12 * v;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scaleByDouble(scale, scale, 1, 1)
                ..translateByDouble(-.02 * box.maxWidth * v, -.02 * box.maxHeight * v, 0, 1),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.detail});

  final RecipeDetail detail;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DietMark(DietMark.kindFor(detail.diet)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.detailMeta(
                  l.recipeDietLabel(detail.diet, jainSafe: detail.jainSafe),
                  l.cuisineLabel(detail.cuisine),
                  detail.mins,
                ),
                style: BText.body(BType.caption, weight: FontWeight.w700, color: BColors.ink3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(header: true, child: Text(detail.name, style: BText.display(BType.h1Family, height: 1.05))),
        const SizedBox(height: 8),
        Text(detail.sub, style: BText.body(BType.body, color: BColors.ink2)),
        const SizedBox(height: 8),
        FitBadge(kind: detail.summary.badge, label: l.summaryLabel(detail.summary)),
      ],
    );
  }
}

Widget _sectionTitle(String text) => Text(text, style: BText.body(BType.sectionLabel, weight: FontWeight.w800));

/// "Kaun khayega": one row per member with a Perfect / Tweak / Nahi badge.
class _FitsBlock extends StatelessWidget {
  const _FitsBlock({required this.fits});

  final List<MemberFit> fits;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l.kaunKhayega),
        const SizedBox(height: 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BRadii.tile),
            border: Border.all(color: BColors.border),
          ),
          child: Column(
            children: [
              for (final f in fits)
                Container(
                  key: ValueKey('fit-${f.memberId}'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: BColors.borderSoft)),
                  ),
                  child: Row(
                    children: [
                      BAvatar(initial: f.initial, color: f.colour, size: 32, fontSize: 12),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.name, style: BText.body(BType.body, weight: FontWeight.w700)),
                            Text(
                              l.reasonText(f.reasonKey, f.reasonParams),
                              style: BText.body(BType.caption, color: BColors.ink3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FitBadge(kind: f.status, label: l.verdict(f.status)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Saaman": ingredient chips scaled to [servings], with the stepper.
class _SaamanBlock extends StatelessWidget {
  const _SaamanBlock({required this.detail, required this.servings, this.onLess, this.onMore});

  final RecipeDetail detail;
  final int servings;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle(l.saaman)),
            ServingsStepper(servings: servings, onLess: onLess, onMore: onMore),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final i in detail.ingredients) _IngredientChip(i.scaledText)]),
        if (detail.batchWarning) ...[
          const SizedBox(height: 8),
          Text(
            l.batchWarning,
            style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.tweakFg),
          ),
        ],
      ],
    );
  }
}

/// Non-interactive `.chip` at 32 high, 12.5px.
class _IngredientChip extends StatelessWidget {
  const _IngredientChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: BColors.card,
        borderRadius: BorderRadius.circular(BRadii.pill),
        border: Border.all(color: BColors.chipBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: BText.body(BType.captionL, weight: FontWeight.w600, color: BColors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// "− 5 log +" (not in the prototype; F-5.5-01 servings).
class ServingsStepper extends StatelessWidget {
  const ServingsStepper({super.key, required this.servings, this.onLess, this.onMore});

  final int servings;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget button(BIconData icon, String label, VoidCallback? onTap) => Opacity(
      opacity: onTap == null ? .4 : 1,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, pressed) => PressScale(
          pressed: pressed,
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
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(BIcons.minus, l.servingsLess, onLess),
        SizedBox(
          width: 64,
          child: Text(
            l.servingsCount(servings),
            textAlign: TextAlign.center,
            style: BText.body(BType.chip, weight: FontWeight.w800),
          ),
        ),
        button(BIcons.plus, l.servingsMore, onMore),
      ],
    );
  }
}

/// "Kaise banega": haldi step numbers + text.
class _StepsBlock extends StatelessWidget {
  const _StepsBlock({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l.kaiseBanega),
        for (var i = 0; i < steps.length; i++) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StepNumber(i + 1),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(steps[i], style: BText.body(BType.body, height: 1.45)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "Ghar ki rating": the family's average (per member when the server sends
/// names; a hired cook gets the aggregate only, F-5.10-01).
class _HomeRating extends StatelessWidget {
  const _HomeRating({required this.summary});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String avg(double v) => v.toStringAsFixed(1);
    return Container(
      key: const ValueKey('home-rating'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: BColors.fitBg, borderRadius: BorderRadius.circular(BRadii.tile)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.recipeHomeRating,
            style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.fitFg),
          ),
          const SizedBox(height: 2),
          Text(
            l.recipeRatingValue(avg(summary.average), summary.count),
            style: BText.body(BType.chip, weight: FontWeight.w700),
          ),
          if (summary.members.any((m) => m.name != null)) ...[
            const SizedBox(height: 4),
            Text(
              [
                for (final m in summary.members)
                  if (m.name != null) '${m.name} ${avg(m.average)}',
              ].join(' · '),
              style: BText.body(BType.caption, color: BColors.ink3),
            ),
          ],
        ],
      ),
    );
  }
}
