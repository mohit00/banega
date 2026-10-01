import 'package:banega/core/config.dart';
import 'package:banega/core/motion/motion.dart';
import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/account/domain/account_models.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:banega/features/recipe/application/recipe_providers.dart';
import 'package:banega/ui/thali_hero.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show RouteAdapter;
import 'helpers.dart';

void main() {
  test('off duty: the backup takes a ticket when it is back by the due time', () async {
    final c = containerAt(testNoon);
    final k = c.read(demoKitchenProvider);
    var m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
    m = await k.patchMenu(m.id, MenuPatch(assigneeCookId: 'c1', assigneeSet: true));
    final t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'k')).ticket; // due 13:30
    await k.patchCook('c2', CookPatch(onDuty: false, offDutyUntil: DateTime(2026, 9, 26, 13)));
    await k.patchCook('c1', CookPatch(onDuty: false, offDutyUntil: DateTime(2026, 9, 27, 12)));
    final after = await k.ticket(t.id);
    expect(after.assignee?.cookId, 'c2', reason: 'back from leave at 13:00, ticket due 13:30');
  });

  testWidgets('a Ready ticket can still get a note (notes-only edit)', (tester) async {
    final c = await pumpBanega(tester, Routes.home);
    final k = c.read(demoKitchenProvider);
    late String id;
    await tester.runAsync(() async {
      var m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
      m = await k.patchMenu(m.id, MenuPatch(assigneeCookId: 'c2', assigneeSet: true)); // family cook → accepted
      var t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'r')).ticket;
      k.meCookId = 'c2';
      t = await k.asCook.transition(t.id, TicketStatus.cooking, version: t.version, idempotencyKey: 'r1');
      t = await k.asCook.transition(t.id, TicketStatus.ready, version: t.version, idempotencyKey: 'r2');
      id = t.id;
    });
    c.read(kitchenRevisionProvider.notifier).bump();
    c.read(routerProvider).go(Routes.ticket(id));
    await settle(tester);
    expect(find.byKey(const ValueKey('ticket-edit')), findsOneWidget);
  });

  test('subscription read failure → unknown (not fail-open, not locked)', () async {
    final c = containerAt(
      testNoon,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
        keyValueStoreProvider.overrideWithValue(MemoryStore()),
        httpClientAdapterProvider.overrideWithValue(RouteAdapter({'GET /v1/subscription': (_) => (500, null)})),
      ],
    );
    c.listen(subscriptionProvider, (_, _) {});
    final s = await c.read(subscriptionProvider.future);
    expect(s?.status, SubscriptionStatus.unknown);
    expect(c.read(readOnlyProvider), isFalse, reason: 'the server enforces');
  });

  test('video link: https only, anything else falls back to a search; launcher failures are handled', () async {
    expect(videoUriFor('Poha', 'https://youtu.be/abc').host, 'youtu.be');
    for (final bad in ['javascript:alert(1)', 'intent://x#Intent;end', 'http://insecure.example', 'file:///etc', '']) {
      expect(videoUriFor('Poha', bad).host, 'www.youtube.com', reason: bad);
    }
    expect(await openExternal((_) async => false, Uri.parse('https://x.test')), isFalse);
    expect(await openExternal((_) async => throw Exception('no app'), Uri.parse('https://x.test')), isFalse);
  });

  testWidgets('low-end: the thali is painted still (no running ticker)', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LowEndScope(lowEnd: true, child: ThaliHero()),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: LowEndScope(lowEnd: false, child: ThaliHero()),
      ),
    );
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cook mode language switch: Hindi → Hinglish → English', (tester) async {
    final c = await pumpBanega(
      tester,
      Routes.cook,
      overrides: [keyValueStoreProvider.overrideWithValue(MemoryStore())],
    );
    expect(c.read(cookLocaleProvider), CookLocale.hindi);
    await tester.tap(find.byKey(const ValueKey('cook-language')));
    await settle(tester);
    expect(c.read(cookLocaleProvider), CookLocale.hinglish);
    await tester.tap(find.byKey(const ValueKey('cook-language')));
    await settle(tester);
    expect(c.read(cookLocaleProvider), CookLocale.english);
    expect(find.text('English'), findsOneWidget);
  });
}
