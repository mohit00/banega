import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/repositories.dart' show wireDate;
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:banega/features/menu/application/plan_controller.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('day-menu drafts keyed by (date, slot)', () {
    test('toggle writes to Home\'s key; other keys are untouched', () {
      final c = containerAt(testNoon);
      final menu = c.read(dayMenuProvider.notifier);
      menu.toggle('poha', 'Kanda Poha');
      final dinner = menuKey(testNoon, Slot.dinner);
      menu.toggle('daltadka', 'Dal Tadka', key: dinner);

      expect(c.read(activeMenuProvider).map((e) => e.id), ['poha']);
      expect(menu.entries(dinner).map((e) => e.id), ['daltadka']);
      expect(menu.entries(menuKey(testNoon, Slot.lunch)).map((e) => e.id), ['poha']);

      menu.toggle('poha', 'Kanda Poha');
      expect(c.read(activeMenuProvider), isEmpty);
      expect(menu.entries(dinner), hasLength(1));
    });

    testWidgets('Plan setSlot / setDate do not carry Lunch dishes to other menus', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final drafts = c.read(dayMenuProvider.notifier);
      drafts.toggle('daltadka', 'Dal Tadka');
      drafts.toggle('lauki', 'Lauki');
      c.read(routerProvider).push(Routes.plan);
      await settle(tester);

      final plan = c.read(planControllerProvider.notifier);
      expect(c.read(planControllerProvider).menu?.dishes.map((d) => d.recipeId), ['daltadka', 'lauki']);

      await plan.setSlot(Slot.dinner);
      await tester.pump();
      expect(c.read(planControllerProvider).menu?.dishes ?? const [], isEmpty, reason: 'dinner has its own menu');
      final repo = c.read(menusRepositoryProvider);
      expect((await repo.menu(wireDate(testNoon), 'dinner'))?.dishes ?? const [], isEmpty);
      expect((await repo.menu(wireDate(testNoon), 'lunch'))!.dishes.map((d) => d.recipeId), ['daltadka', 'lauki']);

      final tomorrow = testNoon.add(const Duration(days: 1));
      await plan.setDate(tomorrow);
      await tester.pump();
      expect(c.read(planControllerProvider).menu?.dishes ?? const [], isEmpty);
      expect((await repo.menu(wireDate(tomorrow), 'dinner'))?.dishes ?? const [], isEmpty);

      // Back to today's lunch: the draft is still there, nothing leaked.
      await plan.setDate(testNoon);
      await plan.setSlot(Slot.lunch);
      await tester.pump();
      expect(c.read(planControllerProvider).menu?.dishes.map((d) => d.recipeId), ['daltadka', 'lauki']);
      expect(drafts.entries(menuKey(testNoon, Slot.lunch)).map((e) => e.id), ['daltadka', 'lauki']);
      expect(drafts.entries(menuKey(testNoon, Slot.dinner)), isEmpty);
    });

    testWidgets('an ADD after Plan loaded a menu extends it instead of replacing it', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final k = c.read(demoKitchenProvider);
      await k.putDishes(wireDate(testNoon), 'lunch', ['daltadka']);
      // Fresh session: Home knows nothing about the server menu yet.
      c.read(dayMenuProvider.notifier).toggle('lauki', 'Lauki');
      c.read(routerProvider).push(Routes.plan);
      await settle(tester);
      expect(c.read(planControllerProvider).menu?.dishes.map((d) => d.recipeId), ['daltadka', 'lauki']);
      expect(c.read(activeMenuProvider).map((e) => e.id), ['daltadka', 'lauki']);
    });
  });
}
