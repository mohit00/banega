// View models shared by the demo and API data sources. Their shape follows
// the backend's OpenAPI (GET /v1/recommendations, GET /v1/recipes/{id},
// GET /v1/members); `fromJson` parses the wire format, and the demo
// repository builds the same objects from the local engine.
import 'package:flutter/widgets.dart';

import '../core/engine/fit_engine.dart';
import '../features/members/domain/member.dart';
import '../features/recipe/domain/recipe.dart';

typedef Json = Map<String, dynamic>;
typedef Params = Map<String, Object?>;

/// Label keys for the household badge (`summary.label_key`).
abstract final class LabelKeys {
  static const allPerfect = 'all_perfect';
  static const allWithTweaks = 'all_with_tweaks';
  static const some = 'some';
}

/// Note keys for the household note (`summary.note_key`); a tweak note uses
/// the tweak's reason key with `{name, ...}` params instead.
abstract final class NoteKeys {
  static const nobodyFor = 'nobody_for';
  static const everyoneHappy = 'everyone_happy';
}

/// Household-level badge + note for one recipe (`summary`).
@immutable
class CardSummary {
  const CardSummary({
    required this.badge,
    required this.labelKey,
    this.labelParams = const {},
    required this.noteKey,
    this.noteParams = const {},
  });

  final FitKind badge;
  final String labelKey;
  final Params labelParams;
  final String noteKey;
  final Params noteParams;

  factory CardSummary.fromJson(Json j) => CardSummary(
    badge: FitKind.fromWire(j['badge'] as String?),
    labelKey: j['label_key'] as String? ?? '',
    labelParams: _params(j['label_params']),
    noteKey: j['note_key'] as String? ?? '',
    noteParams: _params(j['note_params']),
  );

  /// Same keys the backend emits, built from the local engine's summary.
  factory CardSummary.fromEngine(FitSummary s) {
    final (labelKey, labelParams) = switch (s.kind) {
      FitKind.fit => (LabelKeys.allPerfect, const <String, Object?>{}),
      FitKind.tweak => (LabelKeys.allWithTweaks, <String, Object?>{'count': s.tweaks.length}),
      FitKind.no => (LabelKeys.some, <String, Object?>{'can': s.can, 'total': s.total}),
    };
    final String noteKey;
    final Params noteParams;
    if (s.noNames.isNotEmpty) {
      noteKey = NoteKeys.nobodyFor;
      noteParams = {'names': s.noNames};
    } else if (s.tweaks.isNotEmpty) {
      final (name, reason) = s.tweaks.first;
      noteKey = reason.key;
      noteParams = {'name': name, if (s.tweakParams.isNotEmpty) ...s.tweakParams.first};
    } else {
      noteKey = NoteKeys.everyoneHappy;
      noteParams = const {};
    }
    return CardSummary(
      badge: s.kind,
      labelKey: labelKey,
      labelParams: labelParams,
      noteKey: noteKey,
      noteParams: noteParams,
    );
  }

  Json toJson() => {
    'badge': badge.wire,
    'label_key': labelKey,
    'label_params': labelParams,
    'note_key': noteKey,
    'note_params': noteParams,
  };
}

/// A recipe as a Home tile / hero / chat card (`RecipeCard`).
@immutable
class RecipeCard {
  const RecipeCard({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.mins,
    required this.colour,
    this.imageUrl,
    required this.diet,
    required this.summary,
  });

  final String id;
  final String name;

  /// Cuisine wire key (`north_indian`) or display name; see `cuisineLabel`.
  final String cuisine;
  final int mins;
  final Color colour;
  final String? imageUrl;
  final RecipeDiet diet;
  final CardSummary summary;

  /// Accepts a flat card, or the `{recipe: {...}, summary: {...}}` wrapper
  /// that GET /v1/recommendations uses for `pick` and `tiles`.
  factory RecipeCard.fromJson(Json raw) {
    final inner = raw['recipe'];
    final j = inner is Map
        ? <String, dynamic>{...inner.cast<String, dynamic>(), if (raw['summary'] != null) 'summary': raw['summary']}
        : raw;
    return RecipeCard._fromFlat(j);
  }

  factory RecipeCard._fromFlat(Json j) => RecipeCard(
    id: '${j['id']}',
    name: j['name'] as String? ?? '',
    cuisine: j['cuisine'] as String? ?? '',
    mins: (j['mins'] as num?)?.toInt() ?? 0,
    colour: parseColour(j['colour'] as String?),
    imageUrl: _nonEmpty(j['image_url']),
    diet: recipeDietFromWire((j['diet'] ?? j['mark']) as String?),
    summary: CardSummary.fromJson((j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'cuisine': cuisine,
    'mins': mins,
    'colour': '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    'image_url': imageUrl,
    'diet': switch (diet) {
      RecipeDiet.veg => 'veg',
      RecipeDiet.egg => 'egg',
      RecipeDiet.nonveg => 'non_veg',
    },
    'summary': summary.toJson(),
  };

  factory RecipeCard.fromRecipe(Recipe r, FitSummary s) => RecipeCard(
    id: r.id,
    name: r.name,
    cuisine: r.cuisine.wire,
    mins: r.mins,
    colour: r.color,
    diet: r.diet,
    summary: CardSummary.fromEngine(s),
  );
}

/// GET /v1/recommendations.
@immutable
class Recommendations {
  const Recommendations({
    required this.pick,
    required this.tiles,
    this.constraintKey,
    this.constraintParams = const {},
  });

  final RecipeCard pick;
  final List<RecipeCard> tiles;
  final String? constraintKey;
  final Params constraintParams;

  factory Recommendations.fromJson(Json j) {
    final c = (j['constraint_line'] as Map?)?.cast<String, dynamic>();
    return Recommendations(
      pick: RecipeCard.fromJson((j['pick'] as Map).cast<String, dynamic>()),
      tiles: [
        for (final t in (j['tiles'] as List? ?? const [])) RecipeCard.fromJson((t as Map).cast<String, dynamic>()),
      ],
      constraintKey: c?['key'] as String?,
      constraintParams: _params(c?['params']),
    );
  }
}

/// One "Saaman" line (`ingredients[]`).
@immutable
class IngredientLine {
  const IngredientLine({required this.displayText, this.qty, this.unit, required this.scaledText});

  final String displayText;
  final double? qty;
  final String? unit;

  /// [displayText] with the quantity scaled to the requested servings.
  final String scaledText;

  factory IngredientLine.fromJson(Json j) {
    final display = j['display_text'] as String? ?? '';
    final qty = wireDouble(j['qty']);
    final scaled = wireDouble(j['scaled_qty']);
    return IngredientLine(
      displayText: display,
      qty: qty,
      unit: _nonEmpty(j['unit']),
      scaledText: _nonEmpty(j['scaled_text']) ?? _withScaledQty(display, qty, scaled),
    );
  }

  /// "Tel 1 tbsp" with qty 1 scaled to 1.25 → "Tel 1¼ tbsp". Leaves the text
  /// alone when there is nothing to scale or the number isn't found.
  static String _withScaledQty(String display, double? qty, double? scaled) {
    if (qty == null || scaled == null || (qty - scaled).abs() < 1e-9) return display;
    final m = RegExp(r'\d+(?:\.\d+)?(?:/\d+)?').firstMatch(display);
    if (m == null) return display;
    return display.replaceRange(m.start, m.end, formatQty(scaled));
  }
}

/// One "Kaun khayega" row (`fits[]`).
@immutable
class MemberFit {
  const MemberFit({
    required this.memberId,
    required this.name,
    required this.colour,
    required this.status,
    required this.reasonKey,
    this.reasonParams = const {},
  });

  final String memberId;
  final String name;
  final Color colour;
  final FitKind status;
  final String reasonKey;
  final Params reasonParams;

  String get initial => name.isEmpty ? '?' : name.characters.first.toUpperCase();

  factory MemberFit.fromJson(Json j) => MemberFit(
    memberId: '${j['member_id'] ?? j['eater_id']}',
    name: j['name'] as String? ?? '',
    colour: parseColour(j['colour'] as String?),
    status: FitKind.fromWire(j['status'] as String?),
    reasonKey: j['reason_key'] as String? ?? '',
    reasonParams: _params(j['reason_params']),
  );
}

/// GET /v1/recipes/{id}?servings=N.
@immutable
class RecipeDetail {
  const RecipeDetail({
    required this.id,
    required this.name,
    required this.sub,
    required this.cuisine,
    required this.mins,
    required this.diet,
    required this.jainSafe,
    required this.colour,
    this.imageUrl,
    this.videoUrl,
    required this.baseServings,
    required this.servings,
    required this.batchWarning,
    required this.ingredients,
    required this.steps,
    required this.fits,
    required this.summary,
  });

  final String id;
  final String name;
  final String sub;
  final String cuisine;
  final int mins;
  final RecipeDiet diet;
  final bool jainSafe;
  final Color colour;
  final String? imageUrl;
  final String? videoUrl;
  final int baseServings;
  final int servings;
  final bool batchWarning;
  final List<IngredientLine> ingredients;
  final List<String> steps;
  final List<MemberFit> fits;
  final CardSummary summary;

  /// Fills each fit's avatar colour (and a missing name) from the household's
  /// members; the server's `fits[]` carry only ids and names.
  RecipeDetail withMembers(List<Member> members) {
    if (fits.isEmpty || members.isEmpty) return this;
    final byId = {for (final m in members) m.id: m};
    return RecipeDetail(
      id: id,
      name: name,
      sub: sub,
      cuisine: cuisine,
      mins: mins,
      diet: diet,
      jainSafe: jainSafe,
      colour: colour,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      baseServings: baseServings,
      servings: servings,
      batchWarning: batchWarning,
      ingredients: ingredients,
      steps: steps,
      fits: [
        for (final f in fits)
          byId[f.memberId] == null
              ? f
              : MemberFit(
                  memberId: f.memberId,
                  name: f.name.isEmpty ? byId[f.memberId]!.name : f.name,
                  colour: byId[f.memberId]!.color,
                  status: f.status,
                  reasonKey: f.reasonKey,
                  reasonParams: f.reasonParams,
                ),
      ],
      summary: summary,
    );
  }

  factory RecipeDetail.fromJson(Json j) => RecipeDetail(
    id: '${j['id']}',
    name: j['name'] as String? ?? '',
    sub: j['sub'] as String? ?? '',
    cuisine: j['cuisine'] as String? ?? '',
    mins: (j['mins'] as num?)?.toInt() ?? 0,
    diet: recipeDietFromWire((j['diet'] ?? j['mark']) as String?),
    jainSafe: j['jain_safe'] as bool? ?? (j['flags'] as Map?)?['jain_safe'] as bool? ?? false,
    colour: parseColour(j['colour'] as String?),
    imageUrl: _nonEmpty(j['image_url']),
    videoUrl: _nonEmpty(j['video_url']),
    baseServings: (j['base_servings'] as num?)?.toInt() ?? 4,
    servings: (j['servings'] as num?)?.toInt() ?? (j['base_servings'] as num?)?.toInt() ?? 4,
    batchWarning: j['batch_warning'] as bool? ?? j['batch_suggested'] as bool? ?? false,
    ingredients: _ingredientLines(j['ingredients']),
    steps: [for (final s in (j['steps'] as List? ?? j['steps_en'] as List? ?? const [])) '$s'],
    fits: [for (final f in (j['fits'] as List? ?? const [])) MemberFit.fromJson((f as Map).cast<String, dynamic>())],
    summary: CardSummary.fromJson((j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
  );
}

/// One row per recipe line: the server sends one ingredient row per matched
/// ingredient, so "Chawal aata 2 cup" (rice + flour) arrives twice with the
/// same `display_text` and `sort_order`.
List<IngredientLine> _ingredientLines(Object? raw) {
  final seen = <String>{};
  final out = <IngredientLine>[];
  for (final i in (raw as List? ?? const [])) {
    final j = (i as Map).cast<String, dynamic>();
    final key = '${j['sort_order'] ?? ''}|${j['display_text'] ?? ''}';
    if (!seen.add(key)) continue;
    out.add(IngredientLine.fromJson(j));
  }
  return out;
}

/// A number the server may send as JSON number or as a decimal string
/// ("1.500": Python Decimal fields serialise as strings).
double? wireDouble(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s.trim()),
  _ => null,
};

/// 1.25 → "1¼", 0.5 → "½", 2.0 → "2", 1.3 → "1.3".
String formatQty(double v) {
  final whole = v.floor();
  final hundredths = ((v - whole) * 100).round();
  if (hundredths == 0) return '$whole';
  final glyph = switch (hundredths) {
    25 => '¼',
    50 => '½',
    75 => '¾',
    _ => null,
  };
  if (glyph != null) return whole == 0 ? glyph : '$whole$glyph';
  return v.toStringAsFixed(v < 10 ? 1 : 0);
}

// ------------------------------------------------------------------ wire enums

Params _params(Object? v) => v is Map ? v.cast<String, Object?>() : const {};

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

/// `#RRGGBB` / `#AARRGGBB` → [Color]; cream placeholder when missing.
Color parseColour(String? hex) {
  if (hex == null) return const Color(0xFFE8B73A);
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFFE8B73A) : Color(v);
}

RecipeDiet recipeDietFromWire(String? v) => switch (v) {
  'egg' || 'eggetarian' => RecipeDiet.egg,
  'non_veg' || 'nonveg' || 'non-veg' => RecipeDiet.nonveg,
  _ => RecipeDiet.veg,
};

String _snake(String camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String _norm(String v) => v.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

extension CuisineWire on Cuisine {
  /// `north_indian`, `indo_chinese`, …
  String get wire => _snake(name);

  /// Accepts the wire key or the English display name ("North Indian").
  static Cuisine? parse(String v) {
    final n = _norm(v);
    for (final c in Cuisine.values) {
      if (c.wire == n) return c;
    }
    return null;
  }
}

extension DietWire on Diet {
  String get wire => switch (this) {
    Diet.veg => 'veg',
    Diet.jain => 'jain',
    Diet.egg => 'eggetarian',
    Diet.nonveg => 'non_veg',
    Diet.noOnionGarlic => 'no_onion_garlic',
    Diet.pescatarian => 'pescatarian',
  };

  static Diet parse(String? v) => switch (v == null ? null : _norm(v)) {
    'jain' => Diet.jain,
    'egg' || 'eggetarian' => Diet.egg,
    'non_veg' || 'nonveg' => Diet.nonveg,
    'no_onion_garlic' => Diet.noOnionGarlic,
    'pescatarian' => Diet.pescatarian,
    _ => Diet.veg,
  };
}

Spice spiceFromWire(String? v) => switch (v == null ? null : _norm(v)) {
  'kam' || 'low' || 'mild' => Spice.kam,
  'teekha' || 'high' || 'hot' => Spice.teekha,
  _ => Spice.medium,
};

Need? needFromWire(String v) => switch (_norm(v)) {
  'low_oil' => Need.lowOil,
  'low_sugar' || 'diabetic' => Need.lowSugar,
  'high_protein' || 'protein' => Need.highProtein,
  'no_maida' => Need.noMaida,
  'kid_friendly' || 'kid' => Need.kidFriendly,
  _ => null,
};

/// [Member] → `MemberIn` / `MemberPatch` (POST / PATCH /v1/members). Vrat
/// days and [Member.showOnHome] have no server field yet and stay on the
/// device (see MembersController).
Json memberToJson(Member m) => {
  'name': m.name,
  'colour': '#${(m.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
  'is_kid': m.isKid,
  'diet': m.diet.wire,
  'nonveg_exclusions': m.nonvegExclusions,
  'no_dairy': m.noDairy,
  'spice': m.spice.name,
  'needs': [for (final n in m.needs) _snake(n.name)],
  'cuisines': [for (final c in m.cuisines) c.wire],
  'allergens': m.allergens,
  'dislikes': m.dislikes,
  // Server weekdays are 0 = Monday; Dart's DateTime.weekday is 1 = Monday.
  'vrat_days': [for (final d in (m.vratDays.toList()..sort())) d - 1],
  'show_on_home': m.showOnHome,
};

/// GET /v1/members item → [Member]. Unknown needs/cuisines are dropped.
Member memberFromJson(Json j) {
  List<String> strings(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
  final needs = <Need>[];
  for (final n in strings(j['needs'])) {
    final need = needFromWire(n);
    if (need != null && !needs.contains(need)) needs.add(need);
  }
  return Member(
    id: '${j['id']}',
    name: j['name'] as String? ?? '',
    color: parseColour(j['colour'] as String?),
    diet: DietWire.parse(j['diet'] as String?),
    spice: spiceFromWire(j['spice'] as String?),
    needs: needs,
    cuisines: [for (final c in strings(j['cuisines'])) ?CuisineWire.parse(c)],
    isKid: j['is_kid'] as bool? ?? false,
    allergens: strings(j['allergens']),
    dislikes: strings(j['dislikes']),
    nonvegExclusions: strings(j['nonveg_exclusions']),
    noDairy: j['no_dairy'] as bool? ?? false,
    vratDays: {for (final d in (j['vrat_days'] as List? ?? const [])) (d as num).toInt() + 1},
    showOnHome: j['show_on_home'] as bool? ?? false,
  );
}
