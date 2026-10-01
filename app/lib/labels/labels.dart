// Maps domain enums and engine keys to locale strings.
import '../core/engine/fit_engine.dart';
import '../core/l10n/gen/app_localizations.dart';
import '../data/models.dart';
import '../features/members/domain/member.dart';
import '../features/recipe/domain/recipe.dart';

extension BLabels on AppLocalizations {
  String diet(Diet d) => switch (d) {
    Diet.veg => dietVeg,
    Diet.jain => dietJain,
    Diet.egg => dietEgg,
    Diet.nonveg => dietNonveg,
    Diet.noOnionGarlic => dietNoOnionGarlic,
    Diet.pescatarian => dietPescatarian,
  };

  String dietHint(Diet d) => switch (d) {
    Diet.veg => dietVegHint,
    Diet.jain => dietJainHint,
    Diet.egg => dietEggHint,
    Diet.nonveg => dietNonvegHint,
    Diet.noOnionGarlic => dietNoOnionGarlicHint,
    Diet.pescatarian => dietPescatarianHint,
  };

  String recipeDiet(Recipe r) => recipeDietLabel(r.diet, jainSafe: r.jain);

  /// Detail meta: "Jain-friendly" / "Veg" / "Egg" / "Non-veg".
  String recipeDietLabel(RecipeDiet d, {bool jainSafe = false}) => jainSafe
      ? dietJainFriendly
      : switch (d) {
          RecipeDiet.veg => dietVeg,
          RecipeDiet.egg => dietEgg,
          RecipeDiet.nonveg => dietNonveg,
        };

  /// Allergen picklist key → label ([kAllergens]).
  String allergen(String key) => switch (key) {
    'peanut' => allergenPeanut,
    'tree_nut' => allergenTreeNut,
    'milk' || 'dairy' => allergenMilk,
    'gluten' => allergenGluten,
    'sesame' => allergenSesame,
    'soy' => allergenSoy,
    'egg' => allergenEgg,
    'fish' => allergenFish,
    'shellfish' => allergenShellfish,
    'mustard' => allergenMustard,
    _ => key,
  };

  /// Non-veg exclusion key → label ([kNonvegExclusions]).
  String nonvegExclusion(String key) => switch (key) {
    'no_beef' || 'beef' => nonvegNoBeef,
    'no_pork' || 'pork' => nonvegNoPork,
    'halal_only' => nonvegHalalOnly,
    _ => key,
  };

  /// [DateTime.monday]..[DateTime.sunday] → short name.
  String weekdayShort(int weekday) => switch (weekday) {
    DateTime.monday => weekdayMon,
    DateTime.tuesday => weekdayTue,
    DateTime.wednesday => weekdayWed,
    DateTime.thursday => weekdayThu,
    DateTime.friday => weekdayFri,
    DateTime.saturday => weekdaySat,
    _ => weekdaySun,
  };

  String spice(Spice s) => switch (s) {
    Spice.kam => spiceKam,
    Spice.medium => spiceMedium,
    Spice.teekha => spiceTeekha,
  };

  String need(Need n) => switch (n) {
    Need.lowOil => needLowOil,
    Need.lowSugar => needLowSugar,
    Need.highProtein => needHighProtein,
    Need.noMaida => needNoMaida,
    Need.kidFriendly => needKidFriendly,
  };

  String cuisine(Cuisine c) => switch (c) {
    Cuisine.northIndian => cuisineNorthIndian,
    Cuisine.southIndian => cuisineSouthIndian,
    Cuisine.gujarati => cuisineGujarati,
    Cuisine.rajasthani => cuisineRajasthani,
    Cuisine.bengali => cuisineBengali,
    Cuisine.maharashtrian => cuisineMaharashtrian,
    Cuisine.indoChinese => cuisineIndoChinese,
  };

  String slot(Slot s) => switch (s) {
    Slot.breakfast => slotBreakfast,
    Slot.lunch => slotLunch,
    Slot.dinner => slotDinner,
  };

  String slotEyebrow(Slot s) => switch (s) {
    Slot.breakfast => eyebrowBreakfast,
    Slot.lunch => eyebrowLunch,
    Slot.dinner => eyebrowDinner,
  };

  /// Cuisine wire key or display name → localized name (raw when unknown).
  String cuisineLabel(String raw) {
    final c = CuisineWire.parse(raw);
    return c == null ? raw : cuisine(c);
  }

  /// Allergen key → localized name (raw when unknown).
  String allergenLabel(String key) => switch (key) {
    'peanut' => allergenPeanut,
    'tree_nut' => allergenTreeNut,
    'dairy' => allergenDairy,
    'gluten' => allergenGluten,
    'egg' => allergenEgg,
    'fish' => allergenFish,
    'sesame' => allergenSesame,
    'soy' => allergenSoy,
    _ => key,
  };

  /// Engine reason → sentence, with its params ("Moongphali se allergy").
  String reason(FitReason r, [Params params = const {}]) {
    final item = _str(params['item']);
    return switch (r) {
      FitReason.allergen => reasonAllergen(allergenLabel(item)),
      FitReason.onionGarlic => reasonOnionGarlic,
      FitReason.rootVeg => reasonRootVeg,
      FitReason.egg => reasonEgg,
      FitReason.nonveg => item.isEmpty ? reasonNonveg : reasonNonvegItem(item),
      FitReason.maida => reasonMaida,
      FitReason.dairy => reasonDairy,
      FitReason.dislikeMain => reasonDislikeMain(item),
      FitReason.vrat => reasonVrat,
      FitReason.dislikeSkip => reasonDislikeSkip(item),
      FitReason.lessChilli => reasonLessChilli,
      FitReason.extraChilli => reasonExtraChilli,
      FitReason.lowSugar => reasonLowSugar,
      FitReason.lowOil => reasonLowOil,
      FitReason.protein => reasonProtein,
      FitReason.kid => reasonKid,
      FitReason.favCuisine => reasonFavCuisine,
      FitReason.perfect => reasonPerfect,
    };
  }

  /// A reason from the wire (`reason_key` + `reason_params`). Unknown keys
  /// from a newer backend are shown as-is rather than crashing.
  String reasonText(String key, [Params params = const {}]) {
    final r = FitReason.fromKey(key);
    return r == null ? key : reason(r, params);
  }

  String verdict(FitKind k) => switch (k) {
    FitKind.fit => verdictPerfect,
    FitKind.tweak => verdictTweak,
    FitKind.no => verdictNo,
  };

  /// Long badge label ("Sabke liye perfect", "Sabke liye · 2 tweak", "3/5 ke liye").
  String fitLabel(FitSummary s) => switch (s.kind) {
    FitKind.fit => fitAllPerfect,
    FitKind.tweak => fitAllTweak(s.tweaks.length),
    FitKind.no => fitPartial(s.can, s.total),
  };

  /// Short badge label used on tiles.
  String fitShort(FitSummary s) => switch (s.kind) {
    FitKind.fit => fitAllPerfectShort,
    FitKind.tweak => fitAllTweakShort(s.tweaks.length),
    FitKind.no => fitPartial(s.can, s.total),
  };

  /// One-line note under chat cards / plan rows.
  String fitNote(FitSummary s) => summaryNote(CardSummary.fromEngine(s));

  /// Long badge label from wire keys ("Sabke liye · 2 tweak").
  String summaryLabel(CardSummary s) => switch (s.labelKey) {
    LabelKeys.allPerfect => fitAllPerfect,
    LabelKeys.allWithTweaks => fitAllTweak(_int(s.labelParams['count'] ?? s.labelParams['n'])),
    LabelKeys.some => fitPartial(_int(s.labelParams['can']), _int(s.labelParams['total'] ?? s.labelParams['n'])),
    _ => verdict(s.badge),
  };

  /// Short badge label for tiles ("Sab · 2 tweak").
  String summaryShort(CardSummary s) => switch (s.labelKey) {
    LabelKeys.allPerfect => fitAllPerfectShort,
    LabelKeys.allWithTweaks => fitAllTweakShort(_int(s.labelParams['count'] ?? s.labelParams['n'])),
    _ => summaryLabel(s),
  };

  /// Household note ("Dadi ke liye nahi", "Papa: kam tel mein banao").
  String summaryNote(CardSummary s) => switch (s.noteKey) {
    // The server engine names these `not_for`, `all_happy` and `tweak_for`
    // (reason nested in the params); the local engine uses the other names.
    NoteKeys.nobodyFor || 'not_for' => fitNotFor(_str(s.noteParams['names'])),
    NoteKeys.everyoneHappy || 'all_happy' => fitAllHappy,
    'tweak_for' => fitTweakNote(
      _str(s.noteParams['name']),
      reasonText(
        _str(s.noteParams['reason_key']),
        (s.noteParams['reason_params'] as Map?)?.cast<String, Object?>() ?? const {},
      ).toLowerCase(),
    ),
    final key => fitTweakNote(_str(s.noteParams['name']), reasonText(key, s.noteParams).toLowerCase()),
  };

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// Strings, or lists of strings joined with ", ".
  static String _str(Object? v) => switch (v) {
    null => '',
    final List<Object?> l => l.join(', '),
    _ => '$v',
  };

  String _constraint((String, ConstraintKind) c) => switch (c.$2) {
    ConstraintKind.jain => constraintJain(c.$1),
    ConstraintKind.lowSugar => constraintLowSugar(c.$1),
    ConstraintKind.kamMirch => constraintKamMirch(c.$1),
  };

  /// "Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch)", or null.
  String? constraintItemsText(List<Member> members) {
    final items = constraintItems(members);
    return items.isEmpty ? null : items.map(_constraint).join(' · ');
  }

  /// Prototype `constraintLine()`.
  String constraintLineFor(List<Member> members) {
    final items = constraintItemsText(members);
    return items == null ? constraintNone : constraintLine(items);
  }

  /// Home header: "5 log · Papa (low sugar) · …".
  String familyLineFor(List<Member> members) =>
      familyLine(members.length, constraintItemsText(members) ?? constraintNone);

  /// Member tile summary: "Medium mirch · Low sugar, Low oil · North Indian, Rajasthani".
  String memberSummary(Member m) {
    final parts = [
      spiceSummary(spice(m.spice)),
      if (m.needs.isNotEmpty) m.needs.map(need).join(', '),
      if (m.cuisines.isNotEmpty) m.cuisines.map(cuisine).join(', '),
    ];
    return parts.join(' · ');
  }
}
