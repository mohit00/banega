import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What a member eats. The first four are the prototype's `DIETS` (the Prefs
/// screen shows only those); [noOnionGarlic] and [pescatarian] come from the
/// FRD review (F-5.2-01b) and the backend's diet enum.
enum Diet { veg, jain, egg, nonveg, noOnionGarlic, pescatarian }

/// Chilli tolerance (prototype `SPICES`). [level] is 1–3, like recipe spice.
enum Spice {
  kam(1),
  medium(2),
  teekha(3);

  const Spice(this.level);
  final int level;
}

/// Health needs / restrictions (prototype `NEEDS`).
enum Need { lowOil, lowSugar, highProtein, noMaida, kidFriendly }

/// Cuisines (prototype `CUISINES`).
enum Cuisine { northIndian, southIndian, gujarati, rajasthani, bengali, maharashtrian, indoChinese }

/// A household member and their food preferences.
@immutable
class Member {
  const Member({
    required this.id,
    required this.name,
    required this.color,
    this.diet = Diet.veg,
    this.spice = Spice.medium,
    this.needs = const [],
    this.cuisines = const [],
    this.isKid = false,
    this.allergens = const [],
    this.dislikes = const [],
    this.nonvegExclusions = const [],
    this.noDairy = false,
    this.vratDays = const {},
    this.showOnHome = false,
  });

  final String id;
  final String name;
  final Color color;
  final Diet diet;
  final Spice spice;

  /// Ordered by when the user picked them (matches the prototype's summary).
  final List<Need> needs;
  final List<Cuisine> cuisines;

  /// Counts as half a serving when scaling recipes.
  final bool isKid;

  /// Allergen keys (e.g. `peanut`, `tree_nut`, `gluten`, `dairy`): hard No.
  final List<String> allergens;

  /// Disliked ingredients (free text, matched against ingredient names).
  final List<String> dislikes;

  /// Meat types a non-veg member skips (e.g. `beef`, `pork`, `chicken`).
  final List<String> nonvegExclusions;
  final bool noDairy;

  /// Weekdays ([DateTime.monday]..[DateTime.sunday]) this member fasts on.
  final Set<int> vratDays;

  /// Privacy (F-5.3-05): health needs appear in the Home header / loading /
  /// chat constraint line only when the member opts in; diet always shows.
  final bool showOnHome;

  String get initial => name.isEmpty ? '?' : name.characters.first.toUpperCase();

  Member copyWith({
    String? name,
    Color? color,
    Diet? diet,
    Spice? spice,
    List<Need>? needs,
    List<Cuisine>? cuisines,
    bool? isKid,
    List<String>? allergens,
    List<String>? dislikes,
    List<String>? nonvegExclusions,
    bool? noDairy,
    Set<int>? vratDays,
    bool? showOnHome,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      diet: diet ?? this.diet,
      spice: spice ?? this.spice,
      needs: needs ?? this.needs,
      cuisines: cuisines ?? this.cuisines,
      isKid: isKid ?? this.isKid,
      allergens: allergens ?? this.allergens,
      dislikes: dislikes ?? this.dislikes,
      nonvegExclusions: nonvegExclusions ?? this.nonvegExclusions,
      noDairy: noDairy ?? this.noDairy,
      vratDays: vratDays ?? this.vratDays,
      showOnHome: showOnHome ?? this.showOnHome,
    );
  }

  /// Returns a copy with [need] toggled (appended at the end when added).
  Member toggleNeed(Need need) =>
      copyWith(needs: needs.contains(need) ? (List.of(needs)..remove(need)) : [...needs, need]);

  /// Returns a copy with [cuisine] toggled (appended at the end when added).
  Member toggleCuisine(Cuisine cuisine) =>
      copyWith(cuisines: cuisines.contains(cuisine) ? (List.of(cuisines)..remove(cuisine)) : [...cuisines, cuisine]);

  @override
  bool operator ==(Object other) =>
      other is Member &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.diet == diet &&
      other.spice == spice &&
      listEquals(other.needs, needs) &&
      listEquals(other.cuisines, cuisines) &&
      other.isKid == isKid &&
      listEquals(other.allergens, allergens) &&
      listEquals(other.dislikes, dislikes) &&
      listEquals(other.nonvegExclusions, nonvegExclusions) &&
      other.noDairy == noDairy &&
      setEquals(other.vratDays, vratDays) &&
      other.showOnHome == showOnHome;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    color,
    diet,
    spice,
    Object.hashAll(needs),
    Object.hashAll(cuisines),
    isKid,
    Object.hashAll(allergens),
    Object.hashAll(dislikes),
    Object.hashAll(nonvegExclusions),
    noDairy,
    Object.hashAllUnordered(vratDays),
    showOnHome,
  );
}

/// Fixed allergen picklist (F-5.2-03; backend `Allergen`).
const kAllergens = ['peanut', 'tree_nut', 'milk', 'gluten', 'sesame', 'soy', 'egg', 'fish', 'shellfish', 'mustard'];

/// Non-veg exclusions (backend `NonVegExclusion`).
const kNonvegExclusions = ['no_beef', 'no_pork', 'halal_only'];

/// Template for "Member jodo" (prototype `POOL`).
@immutable
class MemberTemplate {
  const MemberTemplate(this.name, this.color);
  final String name;
  final Color color;
}
