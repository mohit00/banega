import 'package:banega/core/engine/fit_engine.dart';
import 'package:banega/data/models.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:banega/core/l10n/gen/app_localizations_hi.dart';
import 'package:banega/labels/labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shapes observed on the live server (docs/contracts/integration-notes.md).
void main() {
  Map<String, dynamic> recipe(String name, int mins) => {
    'id': 'r-$name',
    'slug': name.toLowerCase(),
    'name': name,
    'cuisine': 'Gujarati',
    'mins': mins,
    'colour': '#E9C75A',
    'image_url': null,
    'mark': 'veg',
  };
  const summary = {
    'badge': 'tweak',
    'label_key': 'all_with_tweaks',
    'label_params': {'n': 1},
    'note_key': 'less_oil',
    'note_params': {},
  };

  test('recommendations accept the {recipe, summary} wrapper', () {
    final r = Recommendations.fromJson({
      'slot': 'lunch',
      'pick': {'recipe': recipe('Moong Dal Khichdi', 25), 'summary': summary},
      'tiles': [
        {'recipe': recipe('Dal Tadka', 30), 'summary': summary},
      ],
    });
    expect(r.pick.name, 'Moong Dal Khichdi');
    expect(r.pick.mins, 25);
    expect(r.pick.diet, RecipeDiet.veg);
    expect(r.pick.summary.badge, FitKind.tweak);
    expect(r.tiles.single.name, 'Dal Tadka');
  });

  test('flat cards still parse, with diet from mark', () {
    final c = RecipeCard.fromJson({...recipe('Upma', 20), 'mark': 'egg', 'summary': summary});
    expect(c.name, 'Upma');
    expect(c.diet, RecipeDiet.egg);
  });

  test('server label and note keys render', () {
    final l = AppLocalizationsHiLatn();
    final tweak = CardSummary.fromJson({
      'badge': 'tweak',
      'label_key': 'all_with_tweaks',
      'label_params': {'n': 2},
      'note_key': 'tweak_for',
      'note_params': {'name': 'Papa', 'reason_key': 'less_oil', 'reason_params': <String, Object?>{}},
    });
    expect(l.summaryLabel(tweak), contains('2'));
    expect(l.summaryNote(tweak), startsWith('Papa'));
    final some = CardSummary.fromJson({
      'badge': 'no',
      'label_key': 'some',
      'label_params': {'can': 4, 'n': 5},
      'note_key': 'not_for',
      'note_params': {
        'names': ['Dadi'],
      },
    });
    expect(l.summaryLabel(some), contains('4/5'));
    expect(l.summaryNote(some), contains('Dadi'));
  });

  test('recipe detail as the live server sends it (decimal strings, eater ids, steps_en)', () {
    final d = RecipeDetail.fromJson({
      'id': 'r1',
      'name': 'Angakar Roti',
      'sub': 'Chawal ke aate ki moti roti',
      'cuisine': 'Chhattisgarhi',
      'mins': 35,
      'mark': 'veg',
      'flags': {'jain_safe': true},
      'colour': '#E2CFA3',
      'image_url': null,
      'video_url': 'https://www.youtube.com/watch?v=x',
      'base_servings': 4,
      'servings': 5,
      'batch_suggested': false,
      'steps_en': ['Boil water.', 'Knead the dough.'],
      'steps_hi': ['पानी उबालें।', 'आटा गूंथें।'],
      'ingredients': [
        {'display_text': 'Chawal aata 2 cup', 'qty': null, 'unit': null, 'scaled_qty': null, 'sort_order': 0},
        {'display_text': 'Chawal aata 2 cup', 'qty': null, 'unit': null, 'scaled_qty': null, 'sort_order': 0},
        {'display_text': 'Tel 1 tbsp', 'qty': '1.000', 'unit': 'tbsp', 'scaled_qty': '1.25', 'sort_order': 1},
        {'display_text': 'Namak 3/4 tsp', 'qty': '0.750', 'unit': 'tsp', 'scaled_qty': '0.75', 'sort_order': 2},
      ],
      'fits': [
        {'eater_id': 'm1', 'name': 'Papa', 'status': 'tweak', 'reason_key': 'small_portion_salad', 'reason_params': {}},
      ],
      'summary': summary,
    });
    expect(d.diet, RecipeDiet.veg);
    expect(d.jainSafe, isTrue);
    expect(d.steps, ['Boil water.', 'Knead the dough.']);
    expect(d.ingredients.map((i) => i.displayText), ['Chawal aata 2 cup', 'Tel 1 tbsp', 'Namak 3/4 tsp']);
    expect(d.ingredients[1].qty, 1.0);
    expect(d.ingredients[1].scaledText, 'Tel 1¼ tbsp');
    expect(d.ingredients[2].scaledText, 'Namak 3/4 tsp');
    expect(d.fits.single.memberId, 'm1');
  });
}
