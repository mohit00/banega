import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/repositories.dart' show wireDate;
import 'package:banega/features/cook_mode/cook_tickets_screen.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/demo_kitchen.dart';
import 'package:banega/features/kitchen/data/kitchen_api.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:banega/features/menu/presentation/plan_screen.dart';
import 'package:banega/features/recipe/domain/recipe.dart';
import 'package:banega/features/tickets/presentation/ticket_detail_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Every request fails with a connection error (airplane mode).
class _OfflineAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    throw DioException(requestOptions: o, type: DioExceptionType.connectionError, message: 'offline');
  }

  @override
  void close({bool force = false}) {}
}

/// A ticket confirmed through the demo kitchen for today's [slot].
Future<Ticket> _confirmed(ProviderContainer c, {String slot = 'lunch', String? cookId = 'c1'}) async {
  final k = c.read(demoKitchenProvider);
  var m = await k.putDishes(wireDate(testNoon), slot, ['daltadka', 'lauki']);
  m = await k.patchMenu(m.id, MenuPatch(assigneeCookId: cookId, assigneeSet: true));
  final r = await k.confirm(m.id, version: m.version, idempotencyKey: 'test-$slot');
  c.read(kitchenRevisionProvider.notifier).bump();
  return r.ticket;
}

Future<void> _openPlan(WidgetTester tester, ProviderContainer c, List<(String, String)> dishes) async {
  for (final (id, name) in dishes) {
    c.read(dayMenuProvider.notifier).toggle(id, name);
  }
  c.read(routerProvider).push(Routes.plan);
  await settle(tester);
}

void main() {
  group('Plan', () {
    testWidgets('renders, confirm creates a ticket and Home shows its status card', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      expect(find.byKey(const ValueKey('home-ticket-card')), findsNothing);

      await tester.tap(find.text('ADD').first);
      await settle(tester);
      await tester.tap(find.text('Cook ko bhejo'));
      await settle(tester);

      expect(find.byType(PlanScreen), findsOneWidget);
      expect(find.text('Aaj ka Lunch menu'), findsOneWidget);
      expect(find.text('Aaj'), findsOneWidget);
      expect(find.text('Kal'), findsOneWidget);
      expect(find.text('Kaun kha raha hai?'), findsOneWidget);
      expect(find.text('Kitne log'), findsOneWidget);
      expect(find.text('Kab tak'), findsOneWidget);
      expect(find.text('Kaun banayega'), findsOneWidget);
      expect(find.text('Ramesh ji (hired)'), findsOneWidget);
      expect(find.text('Mummy (family)'), findsOneWidget);
      expect(find.text('Koi nahi'), findsOneWidget);
      expect(find.text('Saaman ki list'), findsOneWidget);
      expect(find.text('Missing saaman order karo'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('plan-send')));
      await settle(tester);
      expect(find.text('Menu + saaman list cook ko WhatsApp par bhej di'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-view-ticket')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-share')), findsOneWidget);
      expect(c.read(activeMenuProvider), isEmpty, reason: 'the draft is cleared once sent');

      final tickets = await c.read(ticketsRepositoryProvider).tickets(date: wireDate(testNoon));
      expect(tickets, hasLength(1));
      expect(tickets.single.status, TicketStatus.fresh); // hired cook → new
      expect(tickets.single.assignee?.name, 'Ramesh ji');

      c.read(routerProvider).pop();
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('home-ticket-card')), findsOneWidget);
      expect(find.text('Lunch ka ticket'), findsOneWidget);
      expect(find.text('Naya'), findsOneWidget);
      expect(find.textContaining('Kab tak 1:30'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-ticket-card')));
      await settle(tester);
      expect(find.byType(TicketDetailScreen), findsOneWidget);
      expect(find.text('Kya kya badla'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('share sends the WhatsApp text through the share sheet', (tester) async {
      final shared = <String>[];
      final c = await pumpBanega(
        tester,
        Routes.home,
        tall: true,
        overrides: [shareTextProvider.overrideWithValue((t) async => shared.add(t))],
      );
      await _openPlan(tester, c, [('daltadka', 'Dal Tadka')]);
      await tester.tap(find.byKey(const ValueKey('plan-send')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('plan-share')));
      await settle(tester);
      expect(shared, hasLength(1));
      expect(shared.single, contains('Dal Tadka'));
      expect(shared.single, contains('Saaman ki list'));
    });

    testWidgets('eaters and guests change coverage and servings', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      // Rajma is not Jain: Dadi has nothing to eat.
      await _openPlan(tester, c, [('rajma', 'Rajma Chawal')]);

      // 4 adults + 1 kid = 4.5 servings.
      expect(find.text('4.5 servings'), findsOneWidget);
      expect(find.textContaining('5 logon ke liye · Dadi ke liye aur dish chahiye'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('eater-m3'))); // Dadi not eating
      await settle(tester);
      expect(find.text('3.5 servings'), findsOneWidget);
      expect(find.text('4 logon ke liye · har member ke liye kuch na kuch hai'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Zyada log').first); // +1 adult guest
      await settle(tester);
      expect(find.text('4.5 servings'), findsOneWidget);
      expect(find.textContaining('5 logon ke liye'), findsOneWidget);

      // A Jain guest is not covered by Rajma.
      await tester.tap(find.byKey(const ValueKey('guest-diet-jain')));
      await settle(tester);
      expect(find.textContaining('Mehmaan ke liye aur dish chahiye'), findsOneWidget);

      // Eaters are remembered per (slot, weekday).
      final menu = await c.read(menusRepositoryProvider).menu(wireDate(testNoon), 'lunch');
      expect(menu!.eaters.map((e) => e.memberId), isNot(contains('m3')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('due time defaults per slot', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      // Each slot has its own draft (a Lunch dish never moves to Dinner).
      final drafts = c.read(dayMenuProvider.notifier);
      drafts.toggle('khichdi', 'Khichdi', key: menuKey(testNoon, Slot.dinner));
      drafts.toggle('poha', 'Kanda Poha', key: menuKey(testNoon, Slot.breakfast));
      await _openPlan(tester, c, [('khichdi', 'Khichdi')]);
      Finder due() => find.descendant(of: find.byKey(const ValueKey('plan-due')), matching: find.byType(Text));

      expect(tester.widget<Text>(due()).data, '1:30 PM');
      await tester.tap(find.text('Dinner'));
      await settle(tester);
      expect(find.text('Aaj ka Dinner menu'), findsOneWidget);
      expect(tester.widget<Text>(due()).data, '8:30 PM');
      await tester.tap(find.text('Nashta'));
      await settle(tester);
      expect(tester.widget<Text>(due()).data, '8:30 AM');
    });

    testWidgets('new family screens render at 390x844 without overflow', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      final t = await _confirmed(c);
      for (final route in [Routes.inbox, Routes.settings, Routes.ticket(t.id), Routes.ticketThread(t.id)]) {
        c.read(routerProvider).go(route);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: route);
      }
      c.read(routerProvider).go(Routes.home);
      await settle(tester);
      expect(find.byKey(const ValueKey('home-bell')), findsOneWidget);
      await _openPlan(tester, c, [('rajma', 'Rajma Chawal'), ('lauki', 'Lauki Chana Dal')]);
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inbox lists demo events and marks them read', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      await settle(tester);
      final unread = c.read(unreadInboxProvider);
      expect(unread, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('home-bell')));
      await settle(tester);
      expect(find.text('Kal ke liye 2 meal plan karne baaki hain'), findsOneWidget);
      await tester.tap(find.text('Kal ke liye 2 meal plan karne baaki hain'));
      await settle(tester);
      expect(c.read(unreadInboxProvider), unread - 1);
    });

    test('defaultDueFor matches F-5.7-01', () {
      expect(defaultDueFor('nashta'), (8, 30));
      expect(defaultDueFor('lunch'), (13, 30));
      expect(defaultDueFor('dinner'), (20, 30));
    });
  });

  group('cook mode', () {
    testWidgets('Rasoi tab appears only with a cook role and switches modes', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      expect(find.byKey(const ValueKey('nav-rasoi')), findsNothing);

      c.read(demoCookRoleProvider.notifier).set('c2'); // Mummy, family cook
      await settle(tester);
      expect(find.byKey(const ValueKey('nav-rasoi')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-rasoi')));
      await settle(tester);
      expect(find.byType(CookTicketsScreen), findsOneWidget);
      expect(find.text('आज के टिकट'), findsOneWidget); // Hindi-first
      expect(find.text('ड्यूटी पर'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cook-family-mode')));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);

      c.read(demoCookRoleProvider.notifier).set(null);
      await settle(tester);
      expect(find.byKey(const ValueKey('nav-rasoi')), findsNothing);
    });

    testWidgets('happy path new → accepted → cooking → completed', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final t = await _confirmed(c);
      expect(t.status, TicketStatus.fresh);
      c.read(demoCookRoleProvider.notifier).set('c1'); // Ramesh ji
      c.read(routerProvider).go(Routes.cook);
      await settle(tester);

      expect(find.byKey(ValueKey('cook-ticket-${t.id}')), findsOneWidget);
      expect(find.text('नया'), findsOneWidget);
      expect(find.text('कब तक 1:30'), findsOneWidget);

      for (final (to, label) in [
        (TicketStatus.accepted, 'स्वीकार हुआ'),
        (TicketStatus.cooking, 'बन रहा है'),
        (TicketStatus.completed, 'हो गया'),
      ]) {
        await tester.tap(find.byKey(ValueKey('cook-action-${t.id}-${to.wire}')));
        await settle(tester);
        expect(find.text(label), findsOneWidget);
        expect((await c.read(ticketsRepositoryProvider).ticket(t.id)).status, to);
      }
      final done = await c.read(ticketsRepositoryProvider).ticket(t.id);
      expect(done.changeLog.map((e) => e.action), ['created', 'accepted', 'cooking', 'completed']);
      expect(done.completedBy, 'Ramesh ji');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an illegal transition shows a toast and refreshes', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final t = await _confirmed(c);
      c.read(demoCookRoleProvider.notifier).set('c1');
      c.read(routerProvider).go(Routes.cook);
      await settle(tester);
      expect(find.byKey(ValueKey('cook-action-${t.id}-accepted')), findsOneWidget);

      // The family cancels behind the cook's back (no refresh on screen).
      await c
          .read(demoKitchenProvider)
          .transition(t.id, TicketStatus.cancelled, version: t.version, idempotencyKey: 'x');

      await tester.tap(find.byKey(ValueKey('cook-action-${t.id}-accepted')));
      await settle(tester);
      expect(find.text('टिकट बदल गया — नया हाल दिखा रहे हैं'), findsOneWidget);
      expect(find.byKey(const ValueKey('status-cancelled')), findsOneWidget);
      expect(find.byKey(ValueKey('cook-action-${t.id}-accepted')), findsNothing);
      await tester.pump(const Duration(seconds: 3)); // let the toast expire
    });

    testWidgets('K2 marks an item out and the family can answer "Khaana bana?"', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final t = await _confirmed(c, cookId: 'c2'); // family cook → accepted
      expect(t.status, TicketStatus.accepted);
      c.read(demoCookRoleProvider.notifier).set('c2');
      c.read(routerProvider).go(Routes.cookTicket(t.id));
      await settle(tester);

      final item = t.requiredItems.firstWhere((i) => i.status != ItemStatus.out);
      await tester.tap(find.byKey(ValueKey('cook-out-${item.ingredientId}')));
      await settle(tester);
      final after = await c.read(ticketsRepositoryProvider).ticket(t.id);
      expect(after.stockIssueOpen, isTrue);
      expect(after.requiredItems.firstWhere((i) => i.ingredientId == item.ingredientId).status, ItemStatus.out);
      expect(after.changeLog.last.action, 'item_out');
    });

    testWidgets('family answers "Khaana bana?" on a not-confirmed ticket', (tester) async {
      // 17:00: lunch was due 13:30, so the ticket is past due + 3 h.
      final c = await pumpBanega(tester, Routes.home, tall: true, now: DateTime(2026, 9, 26, 17));
      final k = c.read(demoKitchenProvider);
      var m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
      m = await k.patchMenu(m.id, const MenuPatch(assigneeCookId: 'c2', assigneeSet: true));
      final t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'kb')).ticket;
      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      expect(find.byKey(const ValueKey('khana-bana')), findsOneWidget);
      expect(find.text('Confirm nahi hua'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('khana-yes')));
      await settle(tester);
      expect(find.byKey(const ValueKey('khana-bana')), findsNothing);
      expect((await k.ticket(t.id)).status, TicketStatus.completed);
    });

    testWidgets('K1 honours 200% font scale without overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Cook screens only: the family Home is not part of F-4-04.
      final c = await pumpBanega(tester, Routes.cook);
      final t = await _confirmed(c);
      c.read(demoCookRoleProvider.notifier).set('c1');
      await settle(tester);
      expect(find.byKey(ValueKey('cook-ticket-${t.id}')), findsOneWidget);
      expect(tester.takeException(), isNull);
      c.read(routerProvider).go(Routes.cookTicket(t.id));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    test('demo timers: not_confirmed after due + 3 h, then Khaana bana → completed', () async {
      var now = DateTime(2026, 9, 26, 12);
      final k = DemoKitchen(members: () => const [], now: () => now);
      var m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
      m = await k.patchMenu(m.id, const MenuPatch(assigneeCookId: 'c2', assigneeSet: true));
      final t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'a')).ticket;
      expect(t.status, TicketStatus.accepted);
      now = DateTime(2026, 9, 26, 16, 31);
      final nc = await k.ticket(t.id);
      expect(nc.status, TicketStatus.notConfirmed);
      final done = await k.transition(t.id, TicketStatus.completed, version: nc.version, idempotencyKey: 'b');
      expect(done.status, TicketStatus.completed);
    });

    test('demo state machine rejects illegal moves with 409 + allowed', () async {
      final k = DemoKitchen(members: () => const [], now: () => DateTime(2026, 9, 26, 9));
      final m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
      final t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'a')).ticket;
      expect(t.status, TicketStatus.fresh);
      await expectLater(
        k.transition(t.id, TicketStatus.cooking, version: t.version, idempotencyKey: 'b'),
        throwsA(
          isA<KitchenError>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.code, 'code', 'invalid_transition')
              .having((e) => e.allowed, 'allowed', [TicketStatus.accepted, TicketStatus.cancelled]),
        ),
      );
      // Same Idempotency-Key replays the first answer.
      final a1 = await k.transition(t.id, TicketStatus.accepted, version: t.version, idempotencyKey: 'c');
      final a2 = await k.transition(t.id, TicketStatus.accepted, version: t.version, idempotencyKey: 'c');
      expect(a2.version, a1.version);
      final cooking = await k.transition(t.id, TicketStatus.cooking, version: a1.version, idempotencyKey: 'd');
      // Cancelling while cooking needs a reason.
      await expectLater(
        k.transition(t.id, TicketStatus.cancelled, version: cooking.version, idempotencyKey: 'e'),
        throwsA(isA<KitchenError>().having((e) => e.code, 'code', 'reason_required')),
      );
      // Stale If-Match.
      await expectLater(
        k.transition(t.id, TicketStatus.ready, version: 1, idempotencyKey: 'f'),
        throwsA(isA<KitchenError>().having((e) => e.code, 'code', 'version_mismatch')),
      );
    });

    test('off duty moves new/accepted tickets to the backup (F-5.7-06)', () async {
      final k = DemoKitchen(members: () => const [], now: () => DateTime(2026, 9, 26, 9));
      final m = await k.putDishes('2026-09-26', 'dinner', ['daltadka']);
      final t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'a')).ticket;
      expect(t.assignee?.cookId, 'c1');
      await k.patchCook('c1', const CookPatch(onDuty: false));
      final moved = await k.ticket(t.id);
      expect(moved.assignee?.cookId, 'c2');
      expect(moved.status, TicketStatus.accepted);
    });
  });

  group('offline', () {
    Ticket sample(String id) => Ticket.fromJson({
      'id': id,
      'menu_id': 'm1',
      'date': '2026-09-26',
      'slot': 'lunch',
      'due_at': '2026-09-26T13:30:00+05:30',
      'status': 'new',
      'assignee': {'cook_id': 'c1', 'name': 'Ramesh ji', 'kind': 'hired'},
      'dishes': [
        {'recipe_id': 'daltadka', 'name': 'Dal Tadka', 'colour': '#E8B73A', 'mins': 30, 'summary': 'Sabke liye'},
      ],
      'eaters': [],
      'guests': {'adults': 0, 'kids': 0, 'diet': null},
      'servings': 4,
      'notes': '',
      'stock_issue_open': false,
      'change_log': [],
      'version': 3,
    });

    test('tickets come from the cache on a connection error', () async {
      final store = MemoryStore();
      final cache = TicketCache(store);
      final key = TicketCache.listKey(date: '2026-09-26', mine: true);
      await cache.saveList(key, [sample('t1')]);
      final offline = <bool>[];
      final repo = CachingTicketsRepository(
        inner: ApiTicketsRepository(
          Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = _OfflineAdapter(),
        ),
        cache: cache,
        onOffline: offline.add,
      );
      final list = await repo.tickets(date: '2026-09-26', mine: true);
      expect(list.single.id, 't1');
      expect(list.single.dishes.single.name, 'Dal Tadka');
      expect((await repo.ticket('t1')).version, 3);
      expect(offline, [true, true]);
      // Nothing cached → the error surfaces.
      await expectLater(repo.ticket('nope'), throwsA(isA<OfflineError>()));
    });

    testWidgets('K1 opens from the cache in airplane mode and queues writes', (tester) async {
      final store = MemoryStore();
      final cache = TicketCache(store);
      await cache.saveList(TicketCache.listKey(date: '2026-09-26', mine: true), [sample('t1')]);
      final adapter = _OfflineAdapter();
      final c = await pumpBanega(
        tester,
        Routes.cook,
        tall: true,
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          cookUsesApiProvider.overrideWithValue(true),
          cookTicketsRepositoryProvider.overrideWith(
            (ref) => CachingTicketsRepository(
              inner: ApiTicketsRepository(Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter),
              cache: ref.watch(ticketCacheProvider),
              onOffline: ref.read(cookOfflineProvider.notifier).set,
            ),
          ),
        ],
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('cook-ticket-t1')), findsOneWidget);
      expect(find.text('Dal Tadka'), findsOneWidget);
      expect(find.byKey(const ValueKey('cook-offline')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cook-action-t1-accepted')));
      await settle(tester);
      expect(find.byKey(const ValueKey('cook-not-sent')), findsOneWidget);
      expect(find.text('स्वीकार हुआ'), findsOneWidget); // shown optimistically
      final queued = await c.read(mutationQueueProvider).all();
      expect(queued.single.to, TicketStatus.accepted);
      expect(queued.single.version, 3);
      expect(adapter.requests.any((r) => r.path.endsWith('/transitions')), isTrue);
    });

    test('the queue replays in order on reconnect; server rejections are dropped', () async {
      final store = MemoryStore();
      final q = MutationQueue(store);
      await q.add(
        const QueuedMutation(key: 'k1', ticketId: 't1', kind: 'transition', to: TicketStatus.accepted, version: 3),
      );
      await q.add(
        const QueuedMutation(key: 'k2', ticketId: 't1', kind: 'transition', to: TicketStatus.cooking, version: 3),
      );
      await q.add(
        const QueuedMutation(key: 'k3', ticketId: 't1', kind: 'transition', to: TicketStatus.ready, version: 3),
      );
      final calls = <String>[];
      final adapter = _RouteAdapter((o) {
        final body = o.data as Map;
        calls.add('${body['to']}@${o.headers['If-Match']}#${o.headers['Idempotency-Key']}');
        if (body['to'] == 'ready') {
          return (
            409,
            {
              'code': 'invalid_transition',
              'allowed': ['completed'],
            },
          );
        }
        final v = int.parse('${o.headers['If-Match']}') + 1;
        return (200, {...sample('t1').toJson(), 'status': body['to'], 'version': v});
      });
      final repo = ApiTicketsRepository(Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter);
      final r = await q.replay(repo);
      expect(r.done, 3);
      expect(r.dropped.single.$1.key, 'k3', reason: '409 is dropped and reported');
      // The second write chains on the version the first returned.
      expect(calls, ['accepted@3#k1', 'cooking@4#k2', 'ready@5#k3']);
      expect(await q.all(), isEmpty);
    });
  });
}

class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.handler);

  final (int, Object) Function(RequestOptions o) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final (status, body) = handler(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
