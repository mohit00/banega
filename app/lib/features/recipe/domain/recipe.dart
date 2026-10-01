import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../members/domain/member.dart';

/// Meal slots (prototype `SLOTS`: b / l / d).
enum Slot { breakfast, lunch, dinner }

/// Recipe diet class (prototype `r.diet`).
enum RecipeDiet { veg, egg, nonveg }

/// Recipe tags used by the fit rules (prototype `r.tags`).
enum RecipeTag { lowOil, lowSugar, protein, kid, light, special, rainy, maida, noMaidaOk }

/// Minimum recipe record the prototype uses (build-plan §1.5), plus the
/// derived flags the extended engine needs (build-plan Phase 2 schema).
///
/// The seed recipes carry no per-ingredient flags, so the derived getters
/// below read them from the ingredient text; recipes from the API override
/// them explicitly.
@immutable
class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.sub,
    required this.mins,
    required this.slots,
    required this.diet,
    required this.jain,
    required this.spice,
    required this.tags,
    required this.cuisine,
    required this.color,
    required this.ingredients,
    required this.steps,
    this.dishCategory = '',
    this.meatType,
    this.vratOk = false,
    this.baseServings = 4,
    bool? onionGarlic,
    bool? rootVeg,
    Set<String>? allergens,
    bool? dairy,
  }) : _onionGarlic = onionGarlic, // ignore: prefer_initializing_formals
       _rootVeg = rootVeg, // ignore: prefer_initializing_formals
       _allergens = allergens, // ignore: prefer_initializing_formals
       _dairy = dairy; // ignore: prefer_initializing_formals

  final String id;
  final String name;
  final String sub;
  final int mins;
  final Set<Slot> slots;
  final RecipeDiet diet;

  /// Jain-safe (editorial in the prototype; derived from ingredients later).
  final bool jain;

  /// 1–3.
  final int spice;
  final Set<RecipeTag> tags;
  final Cuisine cuisine;

  /// Placeholder / katori colour until real photos ship.
  final Color color;
  final List<String> ingredients;
  final List<String> steps;

  /// Variety bucket for Home (max 2 per category in the grid), e.g. `dal`.
  final String dishCategory;

  /// For non-veg recipes: `chicken`, `fish`, `mutton`, … (null otherwise).
  final String? meatType;

  /// Allowed on a fasting (vrat) day.
  final bool vratOk;

  /// Servings the ingredient quantities are written for.
  final int baseServings;

  final bool? _onionGarlic;
  final bool? _rootVeg;
  final Set<String>? _allergens;
  final bool? _dairy;

  /// Contains onion or garlic. The prototype's `jain` flag means "no
  /// pyaaz-lahsun", so seed recipes derive it as `!jain` — this keeps every
  /// seed-recipe verdict identical to the prototype.
  bool get onionGarlic => _onionGarlic ?? !jain;

  /// Contains root vegetables (aloo, gajar, …). Seed recipes: false, so the
  /// Jain reason stays "Pyaaz-lahsun hai" as in the prototype.
  bool get rootVeg => _rootVeg ?? false;

  /// Allergen keys, derived from ingredient text for seed recipes.
  Set<String> get allergens => _allergens ?? deriveAllergens(ingredients);

  /// Contains milk products.
  bool get dairy => _dairy ?? allergens.contains('dairy');

  /// The first ingredient is the main one (dislike → No); the rest are
  /// minor (dislike → Tweak).
  String? get mainIngredient => ingredients.isEmpty ? null : ingredients.first;
}

const _allergenWords = <String, List<String>>{
  'peanut': ['moongphali', 'peanut'],
  'tree_nut': ['kaju', 'badam', 'cashew', 'almond', 'akhrot'],
  'dairy': ['dahi', 'paneer', 'makhan', 'ghee', 'malai', 'doodh', 'milk', 'curd', 'butter', 'cheese'],
  'gluten': ['aata', 'maida', 'sooji', 'noodles', 'gehun', 'wheat'],
  'egg': ['anda', 'ande', 'egg'],
  'fish': ['machli', 'rohu', 'fish'],
  'sesame': ['til', 'sesame'],
  'soy': ['soya', 'soy'],
};

/// Allergen keys whose trigger words appear in [ingredients].
Set<String> deriveAllergens(List<String> ingredients) {
  final text = ingredients.map((i) => ' ${i.toLowerCase()} ').join('|');
  return {
    for (final e in _allergenWords.entries)
      if (e.value.any((w) => RegExp(r'\b' + RegExp.escape(w) + r'\b').hasMatch(text))) e.key,
  };
}
