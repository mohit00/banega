import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/repositories.dart' show wireDate;
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/account/application/locale_controller.dart';
import 'package:banega/features/account/data/account_api.dart';
import 'package:banega/features/account/domain/account_models.dart';
import 'package:banega/features/account/presentation/consent_screen.dart';
import 'package:banega/features/home/home_screen.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/demo_kitchen.dart';
import 'package:banega/features/kitchen/data/kitchen_api.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:banega/features/members/data/members_repository.dart';
import 'package:banega/features/members/presentation/family_screen.dart';
import 'package:banega/features/menu/application/day_menu.dart';
import 'package:banega/features/pantry/application/pantry_providers.dart';
import 'package:banega/features/pantry/data/pantry_api.dart';
import 'package:banega/features/pantry/domain/pantry_models.dart';
import 'package:banega/features/pantry/presentation/stock_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Switch;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A demo kitchen on a movable clock with the demo family.
(DemoKitchen, void Function(Duration)) _kitchen() {
  var now = DateTime(2026, 9, 26, 7);
  final k = DemoKitchen(members: () => const DemoMembersRepository().initialMembers(), now: () => now);
  return (k, (d) => now = now.add(d));
}

/// A confirmed ticket for today's [slot] with [recipes], assigned to [cookId].
Future<Ticket> _ticket(DemoKitchen k, String slot, List<String> recipes, {String cookId = 'c1'}) async {
  var m = await k.putDishes(k.today, slot, recipes);
  m = await k.patchMenu(m.id, MenuPatch(assigneeCookId: cookId, assigneeSet: true));
  return (await k.confirm(m.id, version: m.version, idempotencyKey: 'confirm-$slot-$cookId')).ticket;
}

Future<Ticket> _ticketIn(ProviderContainer c, String slot, List<String> recipes, {String cookId = 'c1'}) async {
  final t = await _ticket(c.read(demoKitchenProvider), slot, recipes, cookId: cookId);
  c.read(kitchenRevisionProvider.notifier).bump();
  return t;
}

void main() {
  // ------------------------------------------------------------------ stock + ration
  group('stock and ration (demo)', () {
    test('required items read live stock levels; a level change flows to menus and the inbox', () async {
      final (k, _) = _kitchen();
      final m = await k.putDishes(k.today, 'lunch', ['kadhi']);
      final dahi = m.requiredItems.firstWhere((i) => i.ingredientId == 'dahi');
      expect(dahi.status, ItemStatus.low);
      expect(m.requiredItems.firstWhere((i) => i.ingredientId == 'besan').status, ItemStatus.low);
      // Untracked lines ("Taaza methi") keep a slug id and "Pata nahi".
      final thepla = await k.putDishes(k.today, 'nashta', ['thepla']);
      expect(thepla.requiredItems.firstWhere((i) => i.ingredientId == 'taaza-methi').status, ItemStatus.untracked);

      await k.pantry.setLevel('pyaaz', ItemStatus.out);
      final after = await k.menu(k.today, 'lunch');
      expect(after!.requiredItems.firstWhere((i) => i.ingredientId == 'pyaaz').status, ItemStatus.out);
      final inbox = await k.inbox();
      expect(inbox.first.event, 'stock_low');
      expect(inbox.first.title, 'Pyaaz khatam ho gaya');
      await expectLater(
        k.pantry.setLevel('nope', ItemStatus.out),
        throwsA(isA<KitchenError>().having((e) => e.status, 'status', 404)),
      );
    });

    test('ration: hired cook raises → pending → admin approves → bought puts items In', () async {
      final (k, _) = _kitchen();
      k.meCookId = 'c1';
      final r = await k.pantry.asCook.create(
        items: const [
          RationItem(ingredientId: 'dahi', name: 'Dahi'),
          RationItem(name: 'Sabudana 500g'),
        ],
      );
      expect(r.status, RationStatus.pending);
      expect(r.raisedBy, 'Ramesh ji');
      expect((await k.inbox()).first.event, 'ration_request');
      expect(await k.pantry.asCook.requests(), hasLength(1));

      final approved = await k.pantry.decide(r.id, Decision.approved, note: 'Shaam ko laayenge');
      expect(approved.status, RationStatus.approved);
      expect((await k.inbox()).first.event, 'ration_decided');
      await expectLater(k.pantry.decide(r.id, Decision.rejected), throwsA(isA<KitchenError>()));

      final bought = await k.pantry.bought(r.id);
      expect(bought.status, RationStatus.bought);
      expect(k.pantry.levelOf('dahi'), ItemStatus.inStock);

      // A family cook's and the admin's own requests are auto-approved (F-2-04).
      k.meCookId = 'c2';
      final self = await k.pantry.asCook.create(
        items: const [RationItem(ingredientId: 'ghee', name: 'Ghee')],
      );
      expect(self.status, RationStatus.approved);
      final admin = await k.pantry.create(
        items: const [RationItem(ingredientId: 'kaju', name: 'Kaju')],
      );
      expect(admin.status, RationStatus.approved);
    });

    test('suggest lists low / out items needed by open tickets in the window', () async {
      final (k, _) = _kitchen();
      await _ticket(k, 'lunch', ['kadhi']);
      final s = await k.pantry.suggest(days: 2);
      expect(s.map((i) => i.ingredientId), containsAll(['dahi', 'besan']));
    });

    testWidgets('S15: one tap changes a level, Low + Out filter, Sab In', (tester) async {
      final c = await pumpBanega(tester, Routes.stock, tall: true);
      expect(find.text('Rasoi stock'), findsOneWidget);
      expect(find.text('Doodh-dahi'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('level-dahi-out')));
      await settle(tester);
      expect(c.read(demoKitchenProvider).pantry.levelOf('dahi'), ItemStatus.out);

      await tester.tap(find.byKey(const ValueKey('stock-filter-low')));
      await settle(tester);
      expect(find.byKey(const ValueKey('stock-pyaaz')), findsNothing);
      expect(find.byKey(const ValueKey('stock-dahi')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stock-all-in')));
      await settle(tester);
      final stock = await c.read(stockProvider(false).future);
      expect(stock.every((s) => s.level == ItemStatus.inStock), isTrue);
      expect(find.text('Kuch nahi mila'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('stock-search')), 'paneer');
      await tester.tap(find.byKey(const ValueKey('stock-filter-all')));
      await settle(tester);
      expect(find.byType(LevelPills), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Plan: "Missing saaman order karo" raises a ration request from low / out items', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      c.read(dayMenuProvider.notifier).toggle('pbm', 'Paneer Butter Masala');
      c.read(routerProvider).push(Routes.plan);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('plan-order-missing')));
      await settle(tester);
      expect(find.text('Ration request bhej di'), findsOneWidget);
      final rs = await c.read(rationRequestsProvider(false).future);
      expect(rs.single.status, RationStatus.approved);
      expect(rs.single.items.map((i) => i.ingredientId), containsAll(['paneer', 'kaju']));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('S13: approve with a note, then "Kharid liya"', (tester) async {
      final c = await pumpBanega(tester, Routes.ration, tall: true);
      final k = c.read(demoKitchenProvider)..meCookId = 'c1';
      final r = await k.pantry.asCook.create(
        items: const [RationItem(ingredientId: 'paneer', name: 'Paneer')],
      );
      c.read(kitchenRevisionProvider.notifier).bump();
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('ration-approve-${r.id}')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('ration-note')), 'Kal subah');
      await tester.tap(find.byKey(const ValueKey('ration-decide-ok')));
      await settle(tester);
      expect((await k.pantry.requests()).single.status, RationStatus.approved);

      await tester.tap(find.text('Approved'));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('ration-bought-${r.id}')));
      await settle(tester);
      expect(k.pantry.levelOf('paneer'), ItemStatus.inStock);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  // ------------------------------------------------------------------ ladder + approvals
  group('out-of-stock ladder', () {
    test('item out computes the three steps with the engine', () async {
      final (k, _) = _kitchen();
      final t = await _ticket(k, 'nashta', ['poha']);
      final out = await k.markItemOut(t.id, 'moongphali');
      expect(out.stockIssueOpen, isTrue);
      expect(k.pantry.levelOf('moongphali'), ItemStatus.out);
      final ladder = out.ladder!;
      expect(ladder.step, LadderStep.saveDish);
      expect(ladder.skip!.ok, isTrue);
      expect(ladder.swaps.map((s) => s.substituteIngredientId), ['kaju']);
      expect(ladder.swaps.single.fitAfter, isNotNull);
      expect(ladder.dishes, hasLength(3));
      expect(ladder.dishes.map((d) => d.id), isNot(contains('poha')));
      // Paneer is out → cheela (paneer stuffing) is never offered.
      expect(ladder.dishes.map((d) => d.id), isNot(contains('cheela')));
      // Round-trips through JSON (offline cache).
      expect(StockLadder.fromJson(ladder.toJson())!.swaps.single.name, 'Kaju');
    });

    test('a swap never introduces a No: tree-nut allergy drops moongphali → kaju', () async {
      var now = DateTime(2026, 9, 26, 7);
      final members = [
        for (final m in const DemoMembersRepository().initialMembers())
          m.id == 'm1' ? m.copyWith(allergens: ['tree_nut']) : m,
      ];
      final k = DemoKitchen(members: () => members, now: () => now);
      final t = await _ticket(k, 'nashta', ['poha']);
      final out = await k.markItemOut(t.id, 'moongphali');
      expect(out.ladder!.swaps, isEmpty);
      now = now.add(Duration.zero);
    });

    test('skip closes the issue; swap by a hired cook is self-approved unless the admin turned it off', () async {
      final (k, _) = _kitchen();
      final t = await _ticket(k, 'nashta', ['poha']);
      await k.markItemOut(t.id, 'moongphali');
      final skipped = await k.asCook.resolveStockIssue(t.id, LadderAction.skip);
      expect(skipped.stockIssueOpen, isFalse);
      expect(skipped.changeLog.last.action, LadderLog.skip);

      final t2 = await _ticket(k, 'lunch', ['kadhi']);
      await k.markItemOut(t2.id, 'dahi');
      final swapped = await k.asCook.resolveStockIssue(t2.id, LadderAction.swap, substituteIngredientId: 'doodh');
      expect(swapped.stockIssueOpen, isFalse);
      expect(swapped.changeLog.last.action, LadderLog.swap);
      expect(swapped.requiredItems.any((i) => i.ingredientId == 'doodh'), isTrue);

      await k.account.patchHousehold(const HouseholdPatch(cookCanApproveSwaps: false));
      final t3 = await _ticket(k, 'dinner', ['gatte']);
      await k.markItemOut(t3.id, 'dahi');
      final asked = await k.asCook.resolveStockIssue(t3.id, LadderAction.swap, substituteIngredientId: 'doodh');
      expect(asked.stockIssueOpen, isTrue);
      expect(asked.issue!.state, StockIssueState.pending);
      final pending = await k.pantry.approvalsRepo.approvals(status: 'pending');
      expect(pending.single.type, ApprovalType.swap);
      expect(pending.single.detail, 'Dahi → Doodh + nimbu');
    });

    test('approval decide: approve applies the dish change, a second answer is 409; reject reopens', () async {
      final (k, _) = _kitchen();
      final t = await _ticket(k, 'nashta', ['poha']);
      final out = await k.markItemOut(t.id, 'moongphali');
      final pick = out.ladder!.dishes.first;
      final asked = await k.asCook.resolveStockIssue(t.id, LadderAction.changeDish, recipeId: pick.id);
      expect(asked.issue!.state, StockIssueState.pending);
      expect((await k.inbox()).first.event, 'approval_request');

      final a = (await k.pantry.approvalsRepo.approvals(status: 'pending')).single;
      expect(a.type, ApprovalType.changeDish);
      expect(a.ticketId, t.id);
      await k.pantry.approvalsRepo.decide(a.id, Decision.approved);
      final done = await k.ticket(t.id);
      expect(done.stockIssueOpen, isFalse);
      expect(done.dishes.map((d) => d.recipeId), [pick.id]);
      expect(done.changeLog.map((c) => c.action), containsAllInOrder([LadderLog.approved, LadderLog.changeDish]));
      await expectLater(
        k.pantry.approvalsRepo.decide(a.id, Decision.rejected),
        throwsA(isA<KitchenError>().having((e) => e.code, 'code', 'already_decided')),
      );

      final t2 = await _ticket(k, 'lunch', ['kadhi']);
      final out2 = await k.markItemOut(t2.id, 'dahi');
      await k.asCook.resolveStockIssue(t2.id, LadderAction.changeDish, recipeId: out2.ladder!.dishes.first.id);
      final a2 = (await k.pantry.approvalsRepo.approvals(status: 'pending')).single;
      await k.pantry.approvalsRepo.decide(a2.id, Decision.rejected);
      final reopened = await k.ticket(t2.id);
      expect(reopened.stockIssueOpen, isTrue);
      expect(reopened.issue!.state, StockIssueState.open);
      expect(reopened.changeLog.last.action, LadderLog.rejected);
    });

    test('a pending approval times out after 30 min: admin alerted, issue stays open', () async {
      final (k, advance) = _kitchen();
      final t = await _ticket(k, 'nashta', ['poha']);
      final out = await k.markItemOut(t.id, 'moongphali');
      await k.asCook.resolveStockIssue(t.id, LadderAction.changeDish, recipeId: out.ladder!.dishes.first.id);
      advance(const Duration(minutes: 29));
      expect((await k.ticket(t.id)).issue!.state, StockIssueState.pending);
      advance(const Duration(minutes: 2));
      final timedOut = await k.ticket(t.id);
      expect(timedOut.stockIssueOpen, isTrue);
      expect(timedOut.issue!.state, StockIssueState.timedOut);
      expect(timedOut.changeLog.last.action, LadderLog.timeout);
      expect((await k.inbox()).first.event, 'stock_issue_timeout');
    });

    testWidgets('K4 ladder sheet walks the three steps and waits for the family', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true, now: DateTime(2026, 9, 26, 7));
      final t = await _ticketIn(c, 'nashta', ['poha']);
      c.read(demoCookRoleProvider.notifier).set('c1');
      c.read(routerProvider).go(Routes.cookTicket(t.id));
      await settle(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('cook-out-moongphali')));
      await tester.tap(find.byKey(const ValueKey('cook-out-moongphali')));
      await settle(tester);
      // Step 1: save the dish (moongphali is optional in poha).
      expect(find.text('बिना Moongphali के बना लो?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ladder-more')));
      await settle(tester);
      // Step 2: engine-checked substitutes.
      expect(find.byKey(const ValueKey('ladder-swap-card-kaju')), findsOneWidget);
      expect(find.text('Kaju'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ladder-change')));
      await settle(tester);
      // Step 3: three dishes for the slot.
      final cards = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ladder-dish-card-'),
      );
      expect(cards, findsNWidgets(3));
      final ladder = (await c.read(cookTicketProvider(t.id).future)).ladder!;
      await tester.tap(find.byKey(ValueKey('ladder-dish-${ladder.dishes.first.id}')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ladder-pending')), findsOneWidget);
      expect(find.text('परिवार से पूछ रहे हैं…'), findsOneWidget);

      // The family says yes → the sheet shows the change is done.
      final a = (await c.read(approvalsRepositoryProvider).approvals(status: 'pending')).single;
      await c.read(familyPantryActionsProvider).decideApproval(a.id, Decision.approved);
      await settle(tester);
      expect(find.byKey(const ValueKey('ladder-done')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('family: approval sheet from the inbox, stock banner on the ticket', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true, now: DateTime(2026, 9, 26, 7));
      final k = c.read(demoKitchenProvider);
      final t = await _ticketIn(c, 'nashta', ['poha']);
      final out = await k.markItemOut(t.id, 'moongphali');
      await k.asCook.resolveStockIssue(t.id, LadderAction.changeDish, recipeId: out.ladder!.dishes.first.id);
      c.read(kitchenRevisionProvider.notifier).bump();

      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      expect(find.byKey(const ValueKey('stock-issue-banner')), findsOneWidget);
      expect(find.text('Moongphali khatam hai'), findsOneWidget);
      expect(find.textContaining('Cook ne poochha: Kanda Poha →'), findsOneWidget);
      // Change log shows the ladder entries.
      expect(find.textContaining('Family se poochha'), findsOneWidget);

      c.read(routerProvider).go(Routes.inbox);
      await settle(tester);
      final a = (await c.read(pendingApprovalsProvider.future)).single;
      await tester.tap(find.byKey(ValueKey('approval-${a.id}')));
      await settle(tester);
      expect(find.text('Aapki haan chahiye'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('approval-no')));
      await settle(tester);
      expect(find.text('Cook ko bata diya: nahi'), findsOneWidget);
      final after = await k.ticket(t.id);
      expect(after.issue!.state, StockIssueState.open);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  // ------------------------------------------------------------------ ratings
  group('ratings', () {
    testWidgets('rate sheet posts a score per eater and dish and sets rated_at', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final k = c.read(demoKitchenProvider);
      final yesterday = wireDate(testNoon.subtract(const Duration(days: 1)));
      final t = (await k.tickets(date: yesterday)).single;
      expect(t.status, TicketStatus.completed);
      expect(t.ratedAt, isNull);
      final before = k.account.summaryFor('daltadka')!.count;

      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ticket-rate')));
      await settle(tester);
      expect(find.text('Dinner kaisa bana?'), findsOneWidget);
      // Kids are rated on their behalf (proxy).
      expect(find.byKey(const ValueKey('rate-proxy-m4')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rate-m1-3')));
      await tester.tap(find.byKey(const ValueKey('rate-m4-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rate-submit')));
      await settle(tester);

      final rated = await k.ticket(t.id);
      expect(rated.ratedAt, isNotNull);
      expect(k.account.summaryFor('daltadka')!.count, before + 2);
      expect(find.byKey(const ValueKey('ticket-rated')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('family cook: appreciation-first copy; ratings off hides the prompt', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true, now: DateTime(2026, 9, 26, 7));
      final k = c.read(demoKitchenProvider);
      final t = await _ticketIn(c, 'nashta', ['poha'], cookId: 'c2');
      final cooking = await k.transition(t.id, TicketStatus.cooking, version: t.version, idempotencyKey: 'x1');
      await k.transition(t.id, TicketStatus.completed, version: cooking.version, idempotencyKey: 'x2');
      expect((await k.inbox()).first.event, 'rate_prompt');
      c.read(kitchenRevisionProvider.notifier).bump();

      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ticket-rate')));
      await settle(tester);
      expect(find.text('Mummy ne banaya — shukriya bolo!'), findsOneWidget);
      expect(find.text('Shukriya bhejo'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await settle(tester);

      await k.account.patchHousehold(const HouseholdPatch(ratingsEnabled: false));
      c.read(kitchenRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const ValueKey('ticket-rate')), findsNothing);
    });

    test('hired cook sees aggregate only unless show_names_to_cook', () {
      final (k, _) = _kitchen();
      expect(k.account.summaryFor('rajma')!.members, isNotEmpty);
      expect(k.account.summaryFor('rajma', forHiredCook: true)!.members, isEmpty);
      expect(k.account.summaryFor('rajma', forHiredCook: true)!.count, 3);
      expect(k.account.summaryFor('poha'), isNull);
    });

    testWidgets('recipe detail shows "Ghar ki rating"', (tester) async {
      await pumpBanega(tester, Routes.recipe('daltadka'), tall: true);
      expect(find.text('Ghar ki rating'), findsOneWidget);
      expect(find.text('2.7/3 · 3 rating'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ paywall
  group('subscription', () {
    testWidgets('trial banner; expired → read-only with "Plan band hai"; subscribe flips to active', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      expect(find.text('Free trial · 5 din baaki'), findsOneWidget);

      c.read(demoKitchenProvider).account.setStatus(SubscriptionStatus.expired);
      c.read(kitchenRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const ValueKey('sub-banner-expired')), findsOneWidget);
      expect(c.read(readOnlyProvider), isTrue);
      await tester.tap(find.text('ADD').first);
      await settle(tester);
      expect(find.byKey(const ValueKey('plan-band-sheet')), findsOneWidget);
      expect(c.read(activeMenuProvider), isEmpty);
      expect(find.byType(PlanBar), findsNothing);

      await tester.tap(find.byKey(const ValueKey('plan-band-cta')));
      await settle(tester);
      expect(find.text('₹50/hafta'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paywall-subscribe')));
      await settle(tester);
      expect(c.read(readOnlyProvider), isFalse);
      expect((await c.read(subscriptionProvider.future))!.status, SubscriptionStatus.active);
      expect(find.byKey(const ValueKey('paywall-subscribe')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('grace shows its banner; cook mode stays workable when expired', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true, now: DateTime(2026, 9, 26, 7));
      final t = await _ticketIn(c, 'nashta', ['poha']);
      c.read(demoKitchenProvider).account.setStatus(SubscriptionStatus.grace);
      c.read(kitchenRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.text('Payment atki hai — 3 din mein theek karo'), findsOneWidget);

      c.read(demoKitchenProvider).account.setStatus(SubscriptionStatus.expired);
      c.read(demoCookRoleProvider.notifier).set('c1');
      c.read(routerProvider).go(Routes.cook);
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('cook-action-${t.id}-accepted')));
      await settle(tester);
      expect((await c.read(demoKitchenProvider).ticket(t.id)).status, TicketStatus.accepted);
    });
  });

  // ------------------------------------------------------------------ settings, locale, consent
  group('settings and consent', () {
    test('F-10-05: English unless the device is hi-IN', () {
      expect(defaultLanguageFor(const Locale('en', 'US')), AppLanguage.english);
      expect(defaultLanguageFor(const Locale('ta', 'IN')), AppLanguage.english);
      expect(defaultLanguageFor(const Locale('hi', 'IN')), AppLanguage.hinglish);
    });

    testWidgets('an en-US device opens in English', (tester) async {
      await pumpBanega(tester, Routes.settings, tall: true, device: const Locale('en', 'US'));
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Bhasha'), findsNothing);
    });

    testWidgets('language switch changes strings and is remembered', (tester) async {
      final store = MemoryStore();
      final c = await pumpBanega(
        tester,
        Routes.settings,
        tall: true,
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      expect(find.text('Bhasha'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lang-en')));
      await settle(tester);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Household name'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lang-hi')));
      await settle(tester);
      expect(find.text('भाषा'), findsOneWidget);
      expect(store.data[LocaleController.storeKey], 'hi');
      expect(c.read(localeProvider), const Locale('hi'));
    });

    testWidgets('settings: rename household, one hired cook, export, delete + restore', (tester) async {
      final c = await pumpBanega(tester, Routes.settings, tall: true);
      final k = c.read(demoKitchenProvider);
      await tester.tap(find.byKey(const ValueKey('settings-name')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('settings-text')), 'Sharma Parivaar');
      await tester.tap(find.byKey(const ValueKey('settings-text-save')));
      await settle(tester);
      expect(k.account.settings.name, 'Sharma Parivaar');

      await tester.tap(find.byKey(const ValueKey('settings-add-cook')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('cook-name')), 'Suresh');
      await tester.enterText(find.byKey(const ValueKey('cook-phone')), '9812345678');
      await tester.tap(find.byKey(const ValueKey('cook-add-save')));
      await settle(tester);
      expect(find.text('Ek ghar mein ek hi hired cook ho sakta hai'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.byKey(const ValueKey('cook-primary-c2')));
      await settle(tester);
      final cooks = await k.cooks();
      expect(cooks.firstWhere((x) => x.id == 'c2').isPrimary, isTrue);
      expect(cooks.firstWhere((x) => x.id == 'c1').isPrimary, isFalse);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pref-stock_low')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('pref-stock_low')), matching: find.byType(Switch)),
      );
      await settle(tester);
      expect((await k.account.notificationPrefs()).firstWhere((p) => p.event == 'stock_low').enabled, isFalse);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-export')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('settings-export')));
      await settle(tester);
      expect(find.text('Inbox mein link aayega'), findsOneWidget);
      expect((await k.inbox()).first.event, 'export_ready');
      await tester.pump(const Duration(seconds: 3));

      await tester.ensureVisible(find.byKey(const ValueKey('settings-delete-household')));
      await tester.tap(find.byKey(const ValueKey('settings-delete-household')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-yes')));
      await settle(tester);
      expect(k.account.settings.pendingDeletion, isTrue);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-restore')));
      await settle(tester);
      expect(k.account.settings.pendingDeletion, isFalse);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('consent shows once, is stored locally and posted', (tester) async {
      final store = MemoryStore();
      final c = await pumpBanega(tester, Routes.splash, overrides: [keyValueStoreProvider.overrideWithValue(store)]);
      await tester.tap(find.text('Apna ghar set karo'));
      await settle(tester);
      expect(find.byType(ConsentScreen), findsOneWidget);
      expect(find.text('Aapka data, aapka haq'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('consent-accept')));
      await settle(tester);
      expect(find.byType(FamilyScreen), findsOneWidget);
      expect(store.data[ConsentController.storeKey], kConsentVersion);
      expect(c.read(demoKitchenProvider).account.consentVersion, kConsentVersion);

      c.read(routerProvider).go(Routes.splash);
      await settle(tester);
      await tester.tap(find.text('Apna ghar set karo'));
      await settle(tester);
      expect(find.byType(FamilyScreen), findsOneWidget);
      expect(find.byType(ConsentScreen), findsNothing);
    });

    testWidgets('consent already on the device skips straight to Family', (tester) async {
      final store = MemoryStore({ConsentController.storeKey: kConsentVersion});
      await pumpBanega(tester, Routes.splash, overrides: [keyValueStoreProvider.overrideWithValue(store)]);
      await tester.tap(find.text('Apna ghar set karo'));
      await settle(tester);
      expect(find.byType(FamilyScreen), findsOneWidget);
    });
  });

  testWidgets('new Phase 6/7 family screens render at 390x844 without overflow', (tester) async {
    final c = await pumpBanega(tester, Routes.home);
    for (final route in [Routes.stock, Routes.ration, Routes.paywall, Routes.consent, Routes.settings]) {
      c.read(routerProvider).go(route);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: route);
    }
    c.read(demoKitchenProvider).account.setStatus(SubscriptionStatus.expired);
    c.read(kitchenRevisionProvider.notifier).bump();
    c.read(routerProvider).go(Routes.home);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------------ cook mode
  group('cook mode stock', () {
    testWidgets('K-stock in Hindi at 200% text: no overflow, one tap sets a level', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await pumpBanega(tester, Routes.cook);
      c.read(demoCookRoleProvider.notifier).set('c1');
      c.read(routerProvider).go(Routes.cook);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('cook-rasoi')));
      await settle(tester);
      expect(find.byType(StockScreen), findsOneWidget);
      expect(find.text('रसोई स्टॉक'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('stock-search')), 'dahi');
      await settle(tester);
      expect(find.text('दही'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('level-dahi-out')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('level-dahi-out')));
      await settle(tester);
      expect(c.read(demoKitchenProvider).pantry.levelOf('dahi'), ItemStatus.out);
      expect(tester.takeException(), isNull);
    });

    testWidgets('K2 "Ration maango" raises the ticket\'s out items + free text', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true, now: DateTime(2026, 9, 26, 7));
      final t = await _ticketIn(c, 'lunch', ['pbm']);
      c.read(demoCookRoleProvider.notifier).set('c1');
      c.read(routerProvider).go(Routes.cookTicket(t.id));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('cook-ration-ask')));
      await tester.tap(find.byKey(const ValueKey('cook-ration-ask')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('raise-free')), 'Dhaniya patta');
      await tester.tap(find.byKey(const ValueKey('raise-add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('raise-send')));
      await settle(tester);
      final mine = await c.read(demoKitchenProvider).pantry.asCook.requests();
      expect(mine.single.status, RationStatus.pending);
      expect(mine.single.ticketId, t.id);
      expect(mine.single.items.map((i) => i.name), contains('Dhaniya patta'));
      expect(mine.single.items.map((i) => i.ingredientId), contains('paneer'));

      c.read(routerProvider).go(Routes.cookRation);
      await settle(tester);
      expect(find.byKey(ValueKey('ration-${mine.single.id}')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  // ------------------------------------------------------------------ wire contract
  group('API wire shapes', () {
    test('stock, ration, approvals, resolve, ratings, subscription, consent, prefs', () async {
      final a = _Adapter({
        'GET /v1/stock': (
          200,
          [
            {
              'ingredient_id': 'dahi',
              'name': 'Dahi',
              'name_hi': 'दही',
              'level': 'low',
              'qty': 1,
              'unit': 'kg',
              'low_threshold': 0.5,
              'updated_at': '2026-09-26T09:00:00+05:30',
              'updated_by': {'id': 'u1', 'name': 'Ramesh ji'},
              'category': 'dairy',
            },
          ],
        ),
        'PUT /v1/stock/dahi': (200, {'ingredient_id': 'dahi', 'name': 'Dahi', 'level': 'out'}),
        'POST /v1/stock/bulk': (200, {'items': []}),
        'POST /v1/ration-requests': (201, {'id': 'rr1', 'status': 'pending', 'items': [], 'raised_by': 'u2'}),
        'POST /v1/ration-requests/rr1/decide': (200, {'id': 'rr1', 'status': 'approved', 'items': []}),
        'POST /v1/ration-requests/rr1/bought': (200, {'id': 'rr1', 'status': 'bought', 'items': []}),
        'GET /v1/approvals': (
          200,
          [
            {
              'id': 'ap1',
              'ticket_id': 't1',
              'type': 'change_dish',
              'requested_by': 'u2',
              'auto': false,
              'expires_at': '2026-09-26T09:30:00+05:30',
            },
          ],
        ),
        'POST /v1/approvals/ap1/decide': (200, {'id': 'ap1', 'type': 'swap', 'decision': 'approved'}),
        'POST /v1/tickets/t1/stock-issue/resolve': (200, {'id': 't1', 'status': 'cooking', 'stock_issue_open': true}),
        'POST /v1/tickets/t1/ratings': (
          200,
          {'id': 't1', 'status': 'completed', 'rated_at': '2026-09-26T14:00:00+05:30'},
        ),
        'GET /v1/ratings/summary': (
          200,
          {
            'recipe_id': 'r1',
            'average': 2.5,
            'count': 4,
            'members': [
              {'member_id': 'm1', 'average': 3, 'count': 2},
            ],
          },
        ),
        'GET /v1/subscription': (
          200,
          {
            'status': 'grace',
            'trial_ends_at': null,
            'renews_at': '2026-09-29T10:00:00+05:30',
            'product_id': 'w',
            'store': 'play',
          },
        ),
        'POST /v1/subscription/restore': (200, {'status': 'active'}),
        'POST /v1/consent': (204, {}),
        'GET /v1/me/notification-prefs': (
          200,
          {
            'prefs': [
              {'event': 'ticket_created', 'enabled': true, 'mandatory': true},
              {'event': 'stock_low', 'enabled': true, 'mandatory': false},
            ],
          },
        ),
        'PUT /v1/me/notification-prefs': (200, {'prefs': []}),
      });
      final dio = _dio(a);

      final stock = ApiStockRepository(dio);
      final items = await stock.stock();
      expect(items.single.level, ItemStatus.low);
      expect(items.single.updatedBy, 'Ramesh ji');
      expect(items.single.category, 'dairy');
      expect((await stock.setLevel('dahi', ItemStatus.out)).level, ItemStatus.out);
      expect(a.last.data, {'level': 'out'});
      await stock.bulk([('dahi', ItemStatus.inStock)]);
      expect(a.last.data, {
        'items': [
          {'ingredient_id': 'dahi', 'level': 'in'},
        ],
      });

      final ration = ApiRationRepository(dio);
      await ration.create(
        ticketId: 't1',
        items: const [
          RationItem(ingredientId: 'dahi', name: 'Dahi'),
          RationItem(name: 'Sabudana', qty: 500, unit: 'g'),
        ],
      );
      expect(a.last.data, {
        'ticket_id': 't1',
        'items': [
          {'ingredient_id': 'dahi', 'name': 'Dahi'},
          {'ingredient_id': null, 'name': 'Sabudana', 'qty': 500.0, 'unit': 'g'},
        ],
      });
      await ration.decide('rr1', Decision.approved, note: 'ok');
      expect(a.last.data, {'decision': 'approved', 'note': 'ok'});
      expect((await ration.bought('rr1')).status, RationStatus.bought);

      final approvals = ApiApprovalsRepository(dio);
      final list = await approvals.approvals(status: 'pending');
      expect(a.last.queryParameters, {'status': 'pending'});
      expect(list.single.type, ApprovalType.changeDish);
      expect(list.single.pending, isTrue);
      await approvals.decide('ap1', Decision.approved);
      expect(a.last.data, {'decision': 'approved'});

      final tickets = ApiTicketsRepository(dio);
      final t = await tickets.resolveStockIssue(
        't1',
        LadderAction.swap,
        substituteIngredientId: 'doodh',
        idempotencyKey: 'k1',
      );
      expect(a.last.data, {'action': 'swap', 'substitute_ingredient_id': 'doodh'});
      expect(a.last.headers['Idempotency-Key'], 'k1');
      expect(t.issue!.state, StockIssueState.open);

      final ratings = ApiRatingsRepository(dio);
      final rated = await ratings.rate('t1', const [
        RatingInput(recipeId: 'r1', memberId: 'm1', score: RatingScore.bahutAccha, note: 'Perfect namak'),
        RatingInput(recipeId: 'r1', memberId: 'm4', score: RatingScore.theek),
      ]);
      expect(a.last.data, {
        'ratings': [
          {'recipe_id': 'r1', 'member_id': 'm1', 'score': 3, 'note': 'Perfect namak'},
          {'recipe_id': 'r1', 'member_id': 'm4', 'score': 2},
        ],
      });
      expect(rated!.ratedAt, isNotNull);
      final sum = await ratings.summary('r1');
      expect(a.last.queryParameters, {'recipe_id': 'r1'});
      expect(sum!.average, 2.5);
      expect(sum.members.single.name, isNull);

      final subs = ApiSubscriptionRepository(dio);
      expect((await subs.subscription()).status, SubscriptionStatus.grace);
      await subs.restore(store: 'play', purchaseToken: 'tok');
      expect(a.last.data, {'store': 'play', 'purchase_token': 'tok'});

      final account = ApiAccountRepository(dio);
      await account.consent(kConsentVersion);
      expect(a.last.data, {'version': kConsentVersion});
      final prefs = await account.notificationPrefs();
      await account.putNotificationPrefs([for (final p in prefs) p.withEnabled(false)]);
      expect(a.last.data, {
        'prefs': [
          {'event': 'stock_low', 'enabled': false},
        ],
      });
    });

    test('ladder parses the map form and a bare options list', () {
      final full = Ticket.fromJson({
        'id': 't1',
        'status': 'cooking',
        'stock_issue_open': true,
        'ladder': {
          'step': 'swap',
          'ingredient': {'ingredient_id': 'dahi', 'name': 'Dahi'},
          'options': {
            'save_dish': {
              'type': 'skip',
              'ingredient': {'ingredient_id': 'dahi', 'name': 'Dahi'},
              'ok': false,
            },
            'swap': [
              {
                'substitute_ingredient_id': 'doodh',
                'name': 'Doodh + nimbu',
                'ratio': '1:1',
                'note_hi': 'दूध में नींबू',
                'fit_after': {'badge': 'fit', 'label_key': 'all_perfect', 'note_key': 'everyone_happy'},
              },
            ],
            'change_dish': [],
          },
        },
      });
      expect(full.ladder!.step, LadderStep.swap);
      expect(full.ladder!.canSkip, isFalse);
      expect(full.ladder!.swaps.single.fitAfter!.labelKey, 'all_perfect');

      final bare = StockLadder.fromJson({
        'step': 'swap',
        'ingredient_id': 'dahi',
        'options': [
          {'substitute_ingredient_id': 'doodh', 'name': 'Doodh', 'ratio': 1},
        ],
      })!;
      expect(bare.ingredientId, 'dahi');
      expect(bare.swaps.single.ratio, '1');

      // Without `stock_issue`, the change log tells where the issue stands.
      final derived = Ticket.fromJson({
        'id': 't2',
        'status': 'cooking',
        'stock_issue_open': true,
        'change_log': [
          {'at': '2026-09-26T09:00:00+05:30', 'by': 'Ramesh ji', 'action': 'item_out', 'detail': 'Dahi'},
          {'at': '2026-09-26T09:01:00+05:30', 'by': 'Ramesh ji', 'action': 'approval_requested', 'detail': 'x'},
        ],
      });
      expect(derived.issue!.state, StockIssueState.pending);
      expect(derived.issue!.name, 'Dahi');
      expect(derived.issue!.expiresAt, DateTime.parse('2026-09-26T09:31:00+05:30').toLocal());
    });
  });
}

/// Answers by "METHOD path" and records every request.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);

  final Map<String, (int, Object)> routes;
  final List<RequestOptions> requests = [];

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    final (status, body) = routes['${o.method} ${o.path}'] ?? (404, {'detail': 'not found'});
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

Dio _dio(_Adapter a) => Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = a;
