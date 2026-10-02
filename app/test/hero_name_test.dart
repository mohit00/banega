import 'package:banega/data/models.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final _card = RecipeCard.fromJson({
  'id': 'r1',
  'name': 'Kondakadalai Sundal',
  'cuisine': 'south_indian',
  'mins': 25,
  'colour': '#C9A227',
  'mark': 'veg',
  'summary': {'badge': 'all', 'label_key': 'all_happy', 'label_params': <String, Object>{}},
});

RenderParagraph _name(WidgetTester tester) => tester.renderObject<RenderParagraph>(
  find.descendant(of: find.byKey(const ValueKey('hero-name')), matching: find.byType(RichText)),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('a long pick name wraps to two lines, not clipped (390 wide, ${scale}x text)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpComponent(tester, HeroPickCard(card: _card));
      expect(tester.takeException(), isNull);
      final p = _name(tester);
      final lineHeight = p.getFullHeightForCaret(const TextPosition(offset: 0));
      // The second line ("Sundal") is laid out inside the card.
      expect(p.size.height, greaterThan(lineHeight * 1.5));
      final card = tester.getRect(find.byType(HeroPickCard));
      final text = tester.getRect(find.byKey(const ValueKey('hero-name')));
      expect(text.bottom, lessThanOrEqualTo(card.bottom));
      expect(card.height, greaterThanOrEqualTo(176));
    });
  }
}
