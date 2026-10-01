// Port of the prototype's fitFor / summarize / constraintLine
// (design/prototype_logic.js), extended with the FRD review's rules
// (allergens, dislikes, vrat, no-onion-garlic, pescatarian, non-veg
// exclusions, no dairy). The engine returns keys only; the app turns them into
// locale strings in lib/labels/labels.dart. The backend engine is the source
// of truth in API mode — keep the rule order here in sync with it.
import 'package:flutter/foundation.dart';

import '../../features/members/domain/member.dart';
import '../../features/recipe/domain/recipe.dart';

enum FitKind {
  fit,
  tweak,
  no;

  /// Wire value (`fit` / `tweak` / `no`) used by the API.
  String get wire => name;

  static FitKind fromWire(String? v) => switch (v) {
    'fit' || 'perfect' => FitKind.fit,
    'tweak' => FitKind.tweak,
    _ => FitKind.no,
  };
}

/// Reason keys, in rule order. [key] is the wire/ARB key shared with the
/// backend engine (build-plan §1.4: the engine returns keys, never text).
enum FitReason {
  // no
  allergen('allergen'),
  onionGarlic('onion_garlic'),
  rootVeg('root_veg'),
  egg('has_egg'),
  nonveg('non_veg'),
  maida('maida'),
  dairy('dairy'),
  dislikeMain('dislike_main'),
  vrat('vrat'),
  // tweak
  lessChilli('less_chilli_katori'),
  extraChilli('add_chilli'),
  lowSugar('small_portion_salad'),
  lowOil('less_oil'),
  protein('add_dahi_paneer'),
  kid('kid_separate_mild'),
  dislikeSkip('dislike_skip'),
  // fit
  favCuisine('favourite_cuisine'),
  perfect('perfect');

  const FitReason(this.key);
  final String key;

  static final Map<String, FitReason> _byKey = {for (final r in values) r.key: r};

  /// Null for keys this build does not know (the labels then show the key).
  static FitReason? fromKey(String key) => _byKey[key];
}

@immutable
class FitResult {
  const FitResult(this.kind, this.reason, [this.params = const {}]);
  final FitKind kind;
  final FitReason reason;

  /// Reason placeholders, e.g. `{item: 'peanut'}` for [FitReason.allergen].
  final Map<String, String> params;
}

/// Case-insensitive "does [text] mention [word]".
bool _mentions(String text, String word) => text.toLowerCase().contains(word.trim().toLowerCase());

/// One member's verdict for one recipe (prototype `fitFor`, extended per the
/// FRD review). The first No wins, then the first Tweak:
///
/// 1. allergen in the recipe (F-5.2-03)
/// 2. Jain and not jain-safe (onion/garlic; root veg when that is the cause)
/// 3. no-onion-garlic diet and the recipe has onion/garlic
/// 4. veg / Jain / no-onion-garlic vs egg or non-veg; egg vs non-veg;
///    pescatarian vs non-fish meat; the member's non-veg exclusions
/// 5. no maida, then no dairy
/// 6. disliked main ingredient
/// 7. vrat today and the recipe is not vrat-ok (F-5.2-02)
/// 8. tweaks: spice, low sugar, low oil, high protein, kid, disliked minor
///    ingredient
/// 9. fit, "Favourite cuisine bhi" when the cuisine matches
///
/// [date] decides whether today is one of the member's vrat days.
FitResult fitFor(Member m, Recipe r, {DateTime? date}) {
  for (final a in m.allergens) {
    if (r.allergens.contains(a)) return FitResult(FitKind.no, FitReason.allergen, {'item': a});
  }
  if (m.diet == Diet.jain && !r.jain) {
    return FitResult(FitKind.no, !r.onionGarlic && r.rootVeg ? FitReason.rootVeg : FitReason.onionGarlic);
  }
  if (m.diet == Diet.noOnionGarlic && r.onionGarlic) return const FitResult(FitKind.no, FitReason.onionGarlic);
  final vegOnly = m.diet == Diet.veg || m.diet == Diet.jain || m.diet == Diet.noOnionGarlic;
  if (vegOnly && r.diet != RecipeDiet.veg) {
    return FitResult(FitKind.no, r.diet == RecipeDiet.egg ? FitReason.egg : FitReason.nonveg);
  }
  if (m.diet == Diet.egg && r.diet == RecipeDiet.nonveg) return const FitResult(FitKind.no, FitReason.nonveg);
  if (m.diet == Diet.pescatarian && r.diet == RecipeDiet.nonveg && r.meatType != 'fish') {
    return const FitResult(FitKind.no, FitReason.nonveg);
  }
  final meat = r.meatType;
  if (r.diet == RecipeDiet.nonveg && meat != null && _excludes(m.nonvegExclusions, meat)) {
    return FitResult(FitKind.no, FitReason.nonveg, {'item': meat});
  }
  if (m.needs.contains(Need.noMaida) && r.tags.contains(RecipeTag.maida)) {
    return const FitResult(FitKind.no, FitReason.maida);
  }
  if (m.noDairy && r.dairy) return const FitResult(FitKind.no, FitReason.dairy);
  final main = r.mainIngredient;
  String? minorDislike;
  for (final d in m.dislikes) {
    if (d.trim().isEmpty) continue;
    if (main != null && _mentions(main, d)) return FitResult(FitKind.no, FitReason.dislikeMain, {'item': d});
    if (minorDislike == null && r.ingredients.skip(1).any((i) => _mentions(i, d))) minorDislike = d;
  }
  if (date != null && m.vratDays.contains(date.weekday) && !r.vratOk) {
    return const FitResult(FitKind.no, FitReason.vrat);
  }
  final tweaks = <FitResult>[
    if (m.spice == Spice.kam && r.spice == 3) const FitResult(FitKind.tweak, FitReason.lessChilli),
    if (m.spice == Spice.teekha && r.spice == 1) const FitResult(FitKind.tweak, FitReason.extraChilli),
    if (m.needs.contains(Need.lowSugar) && !r.tags.contains(RecipeTag.lowSugar))
      const FitResult(FitKind.tweak, FitReason.lowSugar),
    if (m.needs.contains(Need.lowOil) && !r.tags.contains(RecipeTag.lowOil))
      const FitResult(FitKind.tweak, FitReason.lowOil),
    if (m.needs.contains(Need.highProtein) && !r.tags.contains(RecipeTag.protein))
      const FitResult(FitKind.tweak, FitReason.protein),
    if (m.needs.contains(Need.kidFriendly) && !r.tags.contains(RecipeTag.kid) && r.spice > 1)
      const FitResult(FitKind.tweak, FitReason.kid),
    if (minorDislike != null) FitResult(FitKind.tweak, FitReason.dislikeSkip, {'item': minorDislike}),
  ];
  if (tweaks.isNotEmpty) return tweaks.first;
  return FitResult(FitKind.fit, m.cuisines.contains(r.cuisine) ? FitReason.favCuisine : FitReason.perfect);
}

/// Household-level summary for one recipe (prototype `summarize`).
@immutable
class FitSummary {
  const FitSummary({
    required this.total,
    required this.can,
    required this.perfect,
    required this.like,
    required this.noNames,
    required this.tweaks,
    this.tweakParams = const [],
  });

  final int total;
  final int can;
  final int perfect;
  final int like;

  /// Members who can't eat it.
  final List<String> noNames;

  /// (member name, reason) for each tweak, in member order.
  final List<(String, FitReason)> tweaks;

  /// Params of each entry in [tweaks] (same order).
  final List<Map<String, String>> tweakParams;

  FitKind get kind => can == total && perfect == total
      ? FitKind.fit
      : can == total
      ? FitKind.tweak
      : FitKind.no;

  /// Prototype ranking score; replaced by the single formula in Phase 3.
  int get score => can * 10 + perfect * 3 + like * 2 - (noNames.isNotEmpty ? 15 : 0);
}

FitSummary summarize(List<Member> members, Recipe r, {DateTime? date}) {
  var can = 0, perfect = 0, like = 0;
  final nos = <String>[];
  final tweaks = <(String, FitReason)>[];
  final tweakParams = <Map<String, String>>[];
  for (final m in members) {
    final f = fitFor(m, r, date: date);
    if (f.kind != FitKind.no) {
      can++;
    } else {
      nos.add(m.name);
    }
    if (f.kind == FitKind.fit) perfect++;
    if (f.kind == FitKind.tweak) {
      tweaks.add((m.name, f.reason));
      tweakParams.add(f.params);
    }
    if (m.cuisines.contains(r.cuisine)) like++;
  }
  return FitSummary(
    total: members.length,
    can: can,
    perfect: perfect,
    like: like,
    noNames: nos,
    tweaks: tweaks,
    tweakParams: tweakParams,
  );
}

/// Recipes sorted best-first; ties go to the quicker recipe.
List<(Recipe, FitSummary)> ranked(List<Member> members, Iterable<Recipe> recipes, {DateTime? date}) {
  final list = [for (final r in recipes) (r, summarize(members, r, date: date))];
  list.sort((a, b) {
    final s = b.$2.score.compareTo(a.$2.score);
    return s != 0 ? s : a.$1.mins.compareTo(b.$1.mins);
  });
  return list;
}

/// Home grid: the best pick plus up to [count] tiles, excluding the pick and
/// allowing at most [perCategory] tiles per dish category. When the rule
/// leaves fewer than [count] tiles, the skipped ones backfill in rank order
/// (small slots, like nashta, would otherwise look empty).
({(Recipe, FitSummary) pick, List<(Recipe, FitSummary)> tiles}) homeSelection(
  List<(Recipe, FitSummary)> rankedList, {
  int count = 8,
  int perCategory = 2,
}) {
  final pick = rankedList.first;
  final rest = rankedList.skip(1).toList();
  final perCat = <String, int>{};
  final tiles = <(Recipe, FitSummary)>[];
  final skipped = <(Recipe, FitSummary)>[];
  for (final e in rest) {
    if (tiles.length == count) break;
    final c = e.$1.dishCategory;
    final n = perCat[c] ?? 0;
    if (c.isNotEmpty && n >= perCategory) {
      skipped.add(e);
      continue;
    }
    perCat[c] = n + 1;
    tiles.add(e);
  }
  for (final e in skipped) {
    if (tiles.length == count) break;
    tiles.add(e);
  }
  return (pick: pick, tiles: tiles);
}

enum ConstraintKind { jain, lowSugar, kamMirch }

/// Header constraints (prototype `constraintLine`): at most [max] items, in
/// member order, Jain → low sugar → kam mirch for kids within a member.
///
/// Privacy (F-5.3-05): health needs (low sugar, the kid's kam mirch) are
/// shown on Home / Loading / Chat only for members who opted in
/// ([Member.showOnHome]); diet constraints always are.
List<(String, ConstraintKind)> constraintItems(List<Member> members, {int max = 3}) {
  final bits = <(String, ConstraintKind)>[
    for (final m in members) ...[
      if (m.diet == Diet.jain) (m.name, ConstraintKind.jain),
      if (m.showOnHome && m.needs.contains(Need.lowSugar)) (m.name, ConstraintKind.lowSugar),
      if (m.showOnHome && m.spice == Spice.kam && m.needs.contains(Need.kidFriendly)) (m.name, ConstraintKind.kamMirch),
    ],
  ];
  return bits.take(max).toList();
}

/// A member's non-veg exclusion hits [meat]: the backend's `no_beef` /
/// `no_pork` / `halal_only` (pork or unknown meat), or a bare meat type.
bool _excludes(List<String> exclusions, String meat) =>
    exclusions.contains(meat) ||
    exclusions.contains('no_$meat') ||
    (exclusions.contains('halal_only') && (meat == 'pork' || meat == 'other'));
