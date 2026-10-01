import 'package:banega/core/router/routes.dart';
import 'package:banega/data/models.dart';
import 'package:banega/features/home/home_providers.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:banega/features/recipe/presentation/recipe_detail_screen.dart';
import 'package:banega/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('slotForTime', () {
    test('nashta before 11, lunch until 15:59, dinner after', () {
      expect(slotForTime(DateTime(2026, 1, 1, 6)), Slot.breakfast);
      expect(slotForTime(DateTime(2026, 1, 1, 10, 59)), Slot.breakfast);
      expect(slotForTime(DateTime(2026, 1, 1, 11)), Slot.lunch);
      expect(slotForTime(DateTime(2026, 1, 1, 15, 59)), Slot.lunch);
      expect(slotForTime(DateTime(2026, 1, 1, 16)), Slot.dinner);
      expect(slotForTime(DateTime(2026, 1, 1, 23)), Slot.dinner);
    });
  });

  group('Home', () {
    testWidgets('renders the pick and 8 tiles without duplicating the pick', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final recs = await c.read(recommendationsProvider(Slot.lunch).future);
      await settle(tester);

      expect(find.text('MAHARAJ KA PICK'), findsOneWidget);
      expect(find.byType(HeroPickCard), findsOneWidget);
      expect(find.byType(RecipeTile), findsNWidgets(8));
      expect(recs.tiles, hasLength(8));
      expect(recs.tiles.map((t) => t.id), isNot(contains(recs.pick.id)));
      // The pick's name appears once: in the hero only.
      expect(find.text(recs.pick.name), findsOneWidget);
      expect(find.text('Recipe dekho'), findsOneWidget);
      expect(find.text('Lunch ke options'), findsOneWidget);
      expect(find.text('sabke hisaab se'), findsOneWidget);
      expect(find.text('15 min mein kuch'), findsOneWidget);
      expect(find.text('Demo data'), findsOneWidget);
      // Hero meta: "{fitLabel} · {mins} min".
      expect(find.textContaining(' · ${recs.pick.mins} min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ADD toggles the sticky menu bar', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final recs = await c.read(recommendationsProvider(Slot.lunch).future);
      expect(find.textContaining('Aaj ka menu'), findsNothing);

      await tester.tap(find.text('ADD').first);
      await settle(tester);
      expect(find.byType(PlanBar), findsOneWidget);
      expect(find.text('1 dish · Aaj ka menu'), findsOneWidget);
      expect(find.text('Cook ko bhejo'), findsOneWidget);
      expect(find.text(recs.tiles.first.name), findsNWidgets(2)); // tile + bar names
      expect(find.text('ADDED'), findsOneWidget);

      await tester.tap(find.text('ADD').first);
      await settle(tester);
      expect(find.text('2 dish · Aaj ka menu'), findsOneWidget);
      expect(find.text('${recs.tiles[0].name}, ${recs.tiles[1].name}'), findsOneWidget);
      expect(c.read(activeMenuProvider).map((e) => e.id), [recs.tiles[0].id, recs.tiles[1].id]);

      await tester.tap(find.text('ADDED').first);
      await tester.pump();
      await tester.tap(find.text('ADDED').first);
      await settle(tester);
      expect(find.byType(PlanBar), findsNothing);
    });

    testWidgets('sticky bar opens the Plan stub', (tester) async {
      await pumpBanega(tester, Routes.home, tall: true);
      await tester.tap(find.text('ADD').first);
      await settle(tester);
      await tester.tap(find.text('Cook ko bhejo'));
      await settle(tester);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Aaj ka Lunch menu'), findsOneWidget);
    });

    testWidgets('slot switch changes the eyebrow and the options', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      expect(find.text('DOPAHAR KA KHAANA'), findsOneWidget);
      final lunch = await c.read(recommendationsProvider(Slot.lunch).future);

      await tester.tap(find.text('Dinner'));
      await settle(tester);
      expect(find.text('RAAT KA KHAANA'), findsOneWidget);
      expect(find.text('Dinner ke options'), findsOneWidget);
      final dinner = await c.read(recommendationsProvider(Slot.dinner).future);
      expect(dinner.pick.id, isNot(lunch.pick.id));

      await tester.tap(find.text('Nashta'));
      await settle(tester);
      expect(find.text('SUBAH KA NASHTA'), findsOneWidget);
      expect(find.text('Nashta ke options'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('default slot follows the device clock', (tester) async {
      await pumpBanega(tester, Routes.home, now: DateTime(2026, 9, 26, 8, 30));
      expect(find.text('SUBAH KA NASHTA'), findsOneWidget);
    });

    testWidgets('evening opens on dinner', (tester) async {
      await pumpBanega(tester, Routes.home, now: DateTime(2026, 9, 26, 19));
      expect(find.text('RAAT KA KHAANA'), findsOneWidget);
    });

    testWidgets('Recipe dekho opens the pick and back returns Home', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      final recs = await c.read(recommendationsProvider(Slot.lunch).future);
      await tester.tap(find.text('Recipe dekho'));
      await settle(tester);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      expect(find.text(recs.pick.name), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is BIconButton && w.semanticLabel == 'Back'));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(RecipeDetailScreen), findsNothing);
    });

    testWidgets('tile summary uses the engine badges', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final recs = await c.read(recommendationsProvider(Slot.lunch).future);
      // Every lunch option shown carries one of the three badge kinds and a
      // label resolved from its key.
      for (final t in recs.tiles) {
        expect([LabelKeys.allPerfect, LabelKeys.allWithTweaks, LabelKeys.some], contains(t.summary.labelKey));
      }
      expect(find.byType(FitBadge), findsNWidgets(8));
    });
  });
}
