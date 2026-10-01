import 'package:banega/data/demo/demo_members.dart';
import 'package:banega/features/recipe/domain/scaling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String scale(String t, int to, {int base = 4}) => scaleIngredientText(t, base: base, servings: to);

  test('rules: seeti fixed, salt/spices/oil/ghee sublinear, rest linear', () {
    expect(scalingRuleFor('Dal 3 seeti'), ScalingRule.fixed);
    expect(scalingRuleFor('Namak 1 tsp'), ScalingRule.sublinear);
    expect(scalingRuleFor('Laal mirch 1 tsp'), ScalingRule.sublinear);
    expect(scalingRuleFor('Ghee 1 tsp'), ScalingRule.sublinear);
    expect(scalingRuleFor('Sarson tel 2 tbsp'), ScalingRule.sublinear);
    expect(scalingRuleFor('Garam masala 1 tsp'), ScalingRule.sublinear);
    expect(scalingRuleFor('Patta gobhi, shimla mirch, gajar'), ScalingRule.linear);
    expect(scalingRuleFor('Toor dal 1 cup'), ScalingRule.linear);
  });

  test('build-plan gate: base-4 dal to 8 gives 1.5x salt and the same whistles', () {
    expect(scale('Toor dal 1 cup', 8), 'Toor dal 2 cup');
    expect(scale('Namak 1 tsp', 8), 'Namak 1½ tsp');
    expect(scale('Dal 3 seeti', 8), 'Dal 3 seeti');
    expect(ruleFactor(ScalingRule.sublinear, 2), closeTo(1.5, 1e-9));
    expect(ruleFactor(ScalingRule.sublinear, 4), closeTo(2.25, 1e-9));
  });

  test('parses fractions, grams and counts', () {
    expect(scale('Chana dal 1/2 cup', 8), 'Chana dal 1 cup');
    expect(scale('Chana dal 1/2 cup', 5), 'Chana dal ¾ cup');
    expect(scale('Lauki 300g', 6), 'Lauki 450g');
    expect(scale('Chicken 750g', 6), 'Chicken 1130g');
    expect(scale('Ande 6 (uble)', 2), 'Ande 3 (uble)');
    expect(scale('Pyaaz 1', 5), 'Pyaaz 1½');
    expect(scale('Moongphali', 8), 'Moongphali');
    expect(scale('Rajma 1 cup (raat bhar bhiga)', 4), 'Rajma 1 cup (raat bhar bhiga)');
  });

  test('never scales to zero', () {
    expect(scale('Ghee 1 tsp', 1), 'Ghee ½ tsp');
    expect(scale('Pyaaz 1', 1), 'Pyaaz ½');
  });

  test('default servings: adults 1, kids 0.5, rounded up', () {
    expect(defaultServings(demoMembers), 5);
    expect(defaultServings([demoMembers.first]), 1);
    expect(defaultServings(const []), 1);
    expect(isBatchWarning(base: 4, servings: 8), isFalse);
    expect(isBatchWarning(base: 4, servings: 9), isTrue);
  });
}
