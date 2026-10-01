import '../../core/engine/fit_engine.dart';
import '../../features/members/domain/member.dart';
import '../../features/recipe/domain/recipe.dart';
import '../../features/recipe/domain/scaling.dart';
import '../models.dart';
import '../repositories.dart';
import 'demo_recipes.dart';

/// The in-memory sandbox: the 22 seed recipes ranked by the local engine for
/// whatever members the app currently holds. Produces the same view models
/// (and reason/label keys) as the API.
class DemoRepository implements DataRepository {
  const DemoRepository({this.recipes = demoRecipes});

  final List<Recipe> recipes;

  Recipe? byId(String id) {
    for (final r in recipes) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<Recommendations> recommendations({
    required Slot slot,
    required DateTime date,
    required List<Member> members,
  }) async {
    final inSlot = recipes.where((r) => r.slots.contains(slot));
    final list = ranked(members, inSlot, date: date);
    final sel = homeSelection(list);
    // The header's constraint line is built from local members in demo mode.
    return Recommendations(
      pick: RecipeCard.fromRecipe(sel.pick.$1, sel.pick.$2),
      tiles: [for (final (r, s) in sel.tiles) RecipeCard.fromRecipe(r, s)],
    );
  }

  @override
  Future<RecipeDetail> recipe(String id, {int? servings, required List<Member> members, DateTime? date}) async {
    final r = byId(id);
    if (r == null) throw RecipeNotFound(id);
    final base = r.baseServings;
    final n = servings ?? base;
    return RecipeDetail(
      id: r.id,
      name: r.name,
      sub: r.sub,
      cuisine: r.cuisine.wire,
      mins: r.mins,
      diet: r.diet,
      jainSafe: r.jain,
      colour: r.color,
      baseServings: base,
      servings: n,
      batchWarning: isBatchWarning(base: base, servings: n),
      ingredients: [
        for (final i in r.ingredients)
          IngredientLine(
            displayText: i,
            qty: parseQty(i)?.value,
            unit: parseQty(i)?.unit,
            scaledText: scaleIngredientText(i, base: base, servings: n),
          ),
      ],
      steps: r.steps,
      fits: [
        for (final m in members)
          if (fitFor(m, r, date: date) case final f)
            MemberFit(
              memberId: m.id,
              name: m.name,
              colour: m.color,
              status: f.kind,
              reasonKey: f.reason.key,
              reasonParams: f.params,
            ),
      ],
      summary: CardSummary.fromEngine(summarize(members, r, date: date)),
    );
  }
}
