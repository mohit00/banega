import '../../../core/engine/fit_engine.dart';
import '../../../data/demo/demo_recipes.dart';
import '../../../data/models.dart';
import '../../members/domain/member.dart';
import '../../recipe/domain/recipe.dart';
import '../domain/chat_models.dart';
import 'chat_repository.dart';

/// Result of [demoReply]: what the prototype's reply(q) returns.
typedef DemoReply = ({Slot slot, List<(Recipe, FitSummary)> top, ReplyText text, ChipSet chips});

/// Prototype `cmap`: query fragment → cuisine, in the prototype's order.
const _cuisineWords = <(String, Cuisine)>[
  ('south', Cuisine.southIndian),
  ('gujarat', Cuisine.gujarati),
  ('punjab', Cuisine.northIndian),
  ('rajasthan', Cuisine.rajasthani),
  ('bengal', Cuisine.bengali),
  ('chinese', Cuisine.indoChinese),
  ('maharash', Cuisine.maharashtrian),
];

/// Port of the prototype's `reply(q)` (design/prototype_logic.js): a regex
/// intent parser (slot words, halka, protein, mehmaan, baarish, tiffin/kid,
/// jaldi ≤ 20 min, paneer, cuisines, member names) that filters [recipes],
/// keeps the slot's recipes when the slot was named or at least two match,
/// and returns the engine's top 4 with the prototype's text and follow-ups.
/// This is also the rule-based fallback parser of build-plan Phase 4.
DemoReply demoReply(
  String q, {
  required Slot slot,
  required List<Member> members,
  List<Recipe> recipes = demoRecipes,
  DateTime? date,
}) {
  final s = q.toLowerCase();
  var explicitSlot = false;
  final fs = <bool Function(Recipe)>[];
  final why = <WhyTag>[];
  bool has(String pattern) => RegExp(pattern).hasMatch(s);

  if (has('nashta|breakfast|subah')) {
    slot = Slot.breakfast;
    explicitSlot = true;
  } else if (has('lunch|dopahar')) {
    slot = Slot.lunch;
    explicitSlot = true;
  } else if (has('dinner|raat')) {
    slot = Slot.dinner;
    explicitSlot = true;
  }
  void tag(RecipeTag t, WhyKind w) {
    fs.add((r) => r.tags.contains(t));
    why.add(WhyTag(w));
  }

  if (has('halka|light|bimaar|simple|hal?ka')) tag(RecipeTag.light, WhyKind.halka);
  if (has('protein|gym')) tag(RecipeTag.protein, WhyKind.protein);
  if (has('guest|mehmaan|mehman|party|special')) tag(RecipeTag.special, WhyKind.mehmaan);
  if (has('baarish|barish|rain')) tag(RecipeTag.rainy, WhyKind.baarish);
  if (has('tiffin|bachch|kid|beti|daughter')) tag(RecipeTag.kid, WhyKind.kid);
  if (has('jaldi|quick|fast|15|10 min|20 min')) {
    fs.add((r) => r.mins <= 20);
    why.add(const WhyTag(WhyKind.quick));
  }
  if (has('paneer')) {
    fs.add((r) => r.name.contains('Paneer') || r.id == 'cheela');
    why.add(const WhyTag(WhyKind.paneer));
  }
  for (final (word, cuisine) in _cuisineWords) {
    if (s.contains(word)) {
      fs.add((r) => r.cuisine == cuisine);
      why.add(WhyTag(WhyKind.cuisine, cuisine: cuisine));
    }
  }
  // The last member named in the query wins, as in the prototype.
  Member? who;
  for (final m in members) {
    if (s.contains(m.name.toLowerCase())) who = m;
  }
  if (who != null) {
    final w = who;
    fs.add((r) => fitFor(w, r, date: date).kind != FitKind.no);
    why.add(WhyTag(WhyKind.member, name: w.name));
  }

  var list = recipes.where((r) => fs.every((f) => f(r))).toList();
  final inSlot = list.where((r) => r.slots.contains(slot)).toList();
  if (explicitSlot || inSlot.length >= 2) list = inSlot;
  var top = ranked(members, list, date: date).take(4).toList();
  final ReplyText text;
  if (top.isEmpty) {
    top = ranked(members, recipes.where((r) => r.slots.contains(slot)), date: date).take(4).toList();
    text = NoMatchText(slot);
  } else {
    final allOk = top.where((t) => t.$2.can == members.length).length;
    text = OptionsText(slot: slot, count: top.length, why: why, allOk: allOk, members: List.of(members));
  }
  return (slot: slot, top: top, text: text, chips: followUpsFor(slot));
}

/// The demo sandbox's Maharaj: [demoReply] after the prototype's 1.3 s of
/// "rotiyaan sek raha hoon…".
class DemoChatRepository implements ChatRepository {
  const DemoChatRepository({this.recipes = demoRecipes, this.thinkTime = const Duration(milliseconds: 1300)});

  final List<Recipe> recipes;
  final Duration thinkTime;

  @override
  Stream<ChatReply> ask(String text, {required Slot slot, required List<Member> members, DateTime? date}) async* {
    await Future<void>.delayed(thinkTime);
    final r = demoReply(text, slot: slot, members: members, recipes: recipes, date: date);
    yield ChatReply(
      slot: r.slot,
      cards: [for (final (recipe, summary) in r.top) RecipeCard.fromRecipe(recipe, summary)],
      chipSet: r.chips,
      text: r.text,
    );
  }
}
