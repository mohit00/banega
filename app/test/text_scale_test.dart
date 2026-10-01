import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/ui/ui.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('family screens at 200% text: no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await pumpBanega(tester, Routes.splash);
    expect(tester.takeException(), isNull, reason: Routes.splash);
    c.read(dayMenuProvider.notifier).toggle('daltadka', 'Dal Tadka');
    for (final route in [
      Routes.family,
      Routes.prefs('m1'),
      Routes.home,
      Routes.chat,
      Routes.recipe('daltadka'),
      Routes.plan,
      Routes.settings,
      Routes.inbox,
      Routes.consent,
      Routes.phone,
      Routes.createHousehold,
    ]) {
      c.read(routerProvider).go(route);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: route);
    }
  });

  testWidgets('BCta grows to two lines instead of clipping', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpComponent(
      tester,
      BCta(label: 'Menu + saaman list cook ko WhatsApp par bhejo', onPressed: () {}),
      width: 300,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BCta)).height, greaterThan(52));
  });
}
