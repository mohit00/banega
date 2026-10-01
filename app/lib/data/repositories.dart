// Repository interfaces for the catalogue and the engine. Two
// implementations: [DemoRepository] (in-memory seed data + the local Dart
// engine) and [ApiRepository] (Dio against the backend). Pick one through
// `lib/data/data_source.dart`.
import '../features/members/domain/member.dart';
import '../features/recipe/domain/recipe.dart';
import 'models.dart';

export '../features/members/data/members_repository.dart' show MembersRepository;

abstract interface class RecommendationsRepository {
  /// GET /v1/recommendations?slot&date. [members] feeds the local engine in
  /// demo mode; the API reads the household's members server-side.
  Future<Recommendations> recommendations({required Slot slot, required DateTime date, required List<Member> members});
}

abstract interface class RecipesRepository {
  /// GET /v1/recipes/{id}?servings=N; [servings] null → the recipe's base.
  Future<RecipeDetail> recipe(String id, {int? servings, required List<Member> members, DateTime? date});
}

/// Catalogue + engine reads a data source provides (members have their own
/// repository: features/members/data/members_repository.dart).
abstract interface class DataRepository implements RecipesRepository, RecommendationsRepository {}

/// Wire value for [Slot] (`nashta` / `lunch` / `dinner`).
extension SlotWire on Slot {
  String get wire => switch (this) {
    Slot.breakfast => 'nashta',
    Slot.lunch => 'lunch',
    Slot.dinner => 'dinner',
  };
}

/// `YYYY-MM-DD`.
String wireDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Thrown when a recipe id is unknown.
class RecipeNotFound implements Exception {
  const RecipeNotFound(this.id);
  final String id;

  @override
  String toString() => 'RecipeNotFound($id)';
}
