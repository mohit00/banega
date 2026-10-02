import 'dart:async';

import 'package:banega/core/config.dart';
import 'package:banega/core/push/push_messaging.dart';
import 'package:banega/core/push/push_registrar.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/account/data/billing_adapter.dart';
import 'package:banega/features/auth/application/auth_controller.dart';
import 'package:banega/features/auth/data/token_store.dart';
import 'package:banega/features/auth/domain/auth_models.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show RouteAdapter, meJson;
import 'helpers.dart';

class FakePush implements PushMessaging {
  FakePush({this.allowed = true});

  final bool allowed;
  final refresh = StreamController<String>.broadcast();
  final opened = StreamController<Map<String, String>>.broadcast();
  final foreground = StreamController<Map<String, String>>.broadcast();
  String? current = 'fcm-token-1';
  int deleted = 0;

  @override
  Future<bool> start() async => allowed;

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<Map<String, String>> get onOpened => opened.stream;

  @override
  Stream<Map<String, String>> get onForeground => foreground.stream;

  @override
  Future<void> deleteToken() async => deleted++;
}

class FakeStore implements StoreClient {
  FakeStore({this.available = true, this.hasOffer = true});

  bool available;
  bool hasOffer;
  final updates = StreamController<List<StorePurchase>>.broadcast();
  final List<String> calls = [];
  final List<StorePurchase> completed = [];

  /// What the store answers to [buy] / [restore].
  List<StorePurchase> onBuy = [];
  List<StorePurchase> onRestore = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Object?> offer(String productId, String basePlanId) async {
    calls.add('offer $productId/$basePlanId');
    return hasOffer ? 'offer-handle' : null;
  }

  @override
  Future<void> buy(Object offer) async {
    calls.add('buy $offer');
    final list = onBuy;
    scheduleMicrotask(() => updates.add(list));
  }

  @override
  Stream<List<StorePurchase>> get purchases => updates.stream;

  @override
  Future<void> restore() async {
    calls.add('restore');
    final list = onRestore;
    scheduleMicrotask(() => updates.add(list));
  }

  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase);
}

StorePurchase purchased(String token, {StorePurchaseStatus status = StorePurchaseStatus.purchased}) =>
    StorePurchase(productId: 'banega_weekly_50', status: status, token: token, pendingComplete: true);

const _tokens = AuthTokens(accessToken: 'a1', refreshToken: 'r1', userId: 'u1');

final _subJson = {
  'status': 'active',
  'read_only': false,
  'store': 'play',
  'product_id': 'banega_weekly_50',
  'renews_at': '2026-10-09T10:00:00Z',
};

ProviderContainer api(RouteAdapter a, {List<Override> extra = const []}) => containerAt(
  testNoon,
  overrides: [
    appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore(_tokens)),
    keyValueStoreProvider.overrideWithValue(MemoryStore()),
    httpClientAdapterProvider.overrideWithValue(a),
    ...extra,
  ],
);

void main() {
  group('push registration', () {
    test('signed in: token is registered, re-registered on refresh, dropped on logout', () async {
      final push = FakePush();
      final a = RouteAdapter({
        'POST /v1/devices': (o) => (201, {'id': 'dev-${(o.data as Map)['push_token']}', 'platform': 'android'}),
        'DELETE /v1/devices/dev-fcm-token-2': (o) => (204, null),
        'POST /v1/auth/logout': (o) => (204, null),
      });
      final c = api(a, extra: [pushMessagingProvider.overrideWithValue(push)]);
      await c.read(authControllerProvider.notifier).ready();
      await c.read(pushRegistrarProvider).start();

      final posts = a.requests.where((r) => r.path == '/v1/devices').toList();
      expect(posts.single.data, {'platform': 'android', 'push_token': 'fcm-token-1'});
      expect(posts.single.headers['Authorization'], 'Bearer a1');
      final store = c.read(keyValueStoreProvider);
      expect(await store.get(PushRegistrar.deviceKey), 'dev-fcm-token-1');

      push.refresh.add('fcm-token-2');
      await pumpEventQueue();
      expect(a.count('POST /v1/devices'), 2);
      expect(await store.get(PushRegistrar.deviceKey), 'dev-fcm-token-2');

      await c.read(authControllerProvider.notifier).logout();
      expect(a.count('DELETE /v1/devices/dev-fcm-token-2'), 1);
      // The device is dropped before the session ends.
      final paths = a.requests.map((r) => '${r.method} ${r.path}').toList();
      expect(paths.indexOf('DELETE /v1/devices/dev-fcm-token-2'), lessThan(paths.indexOf('POST /v1/auth/logout')));
      expect(push.deleted, 1);
      expect(await store.get(PushRegistrar.deviceKey), isNull);
    });

    test('no permission / no Firebase config: nothing is registered', () async {
      final a = RouteAdapter({});
      final c = api(a, extra: [pushMessagingProvider.overrideWithValue(FakePush(allowed: false))]);
      await c.read(authControllerProvider.notifier).ready();
      await c.read(pushRegistrarProvider).start();
      expect(a.requests, isEmpty);
    });

    test('a build without push (null messaging) is a no-op', () async {
      final a = RouteAdapter({});
      final c = api(a, extra: [pushMessagingProvider.overrideWithValue(null)]);
      await c.read(pushRegistrarProvider).start();
      await c.read(pushRegistrarProvider).unregister();
      expect(a.requests, isEmpty);
    });

    test('a tap opens the ticket (cook mode for a hired cook) or the inbox', () async {
      final family = api(RouteAdapter({'GET /v1/me': (o) => (200, meJson())}));
      await family.read(meProvider.future);
      final r = family.read(pushRegistrarProvider);
      expect(r.routeFor({'event': 'ticket_created', 'ticket_id': 't1'}), Routes.ticket('t1'));
      expect(r.routeFor({'event': 'weekly_summary'}), Routes.inbox);

      final cook = api(
        RouteAdapter({
          'GET /v1/me': (o) => (200, meJson(modes: ['cook'])..['cook'] = {'id': 'c1'}),
        }),
      );
      await cook.read(meProvider.future);
      final rc = cook.read(pushRegistrarProvider);
      expect(rc.routeFor({'event': 'ticket_created', 'ticket_id': 't1'}), Routes.cookTicket('t1'));
      expect(rc.routeFor({'event': 'tomorrow_tickets'}), Routes.cook);
    });
  });

  group('Play billing adapter', () {
    test('purchase â†’ token; cancelled â†’ null; pending / error / no product throw', () async {
      final store = FakeStore()..onBuy = [purchased('play-tok-1')];
      final b = PlayBillingAdapter(store);
      expect(await b.purchaseWeekly(), (store: 'play', token: 'play-tok-1'));
      expect(store.calls, ['offer banega_weekly_50/weekly', 'buy offer-handle']);
      // Finished only after the server verified it.
      expect(store.completed, isEmpty);
      await b.finish((store: 'play', token: 'play-tok-1'));
      expect(store.completed.single.token, 'play-tok-1');

      store.onBuy = [const StorePurchase(productId: 'banega_weekly_50', status: StorePurchaseStatus.canceled)];
      expect(await b.purchaseWeekly(), isNull);

      store.onBuy = [const StorePurchase(productId: 'banega_weekly_50', status: StorePurchaseStatus.pending)];
      await expectLater(b.purchaseWeekly(), throwsA(isA<BillingPending>()));

      store.onBuy = [const StorePurchase(productId: 'banega_weekly_50', status: StorePurchaseStatus.error, error: 'x')];
      await expectLater(b.purchaseWeekly(), throwsA(isA<BillingUnavailable>()));

      store.hasOffer = false;
      await expectLater(b.purchaseWeekly(), throwsA(isA<BillingUnavailable>()));
      store.available = false;
      await expectLater(b.purchaseWeekly(), throwsA(isA<BillingUnavailable>()));
      await b.dispose();
    });

    test('restore returns the owned purchase, or null', () async {
      final store = FakeStore()..onRestore = [purchased('old-tok', status: StorePurchaseStatus.restored)];
      final b = PlayBillingAdapter(store, restoreWindow: const Duration(milliseconds: 10));
      expect(await b.restoreToken(), (store: 'play', token: 'old-tok'));
      store.onRestore = [];
      expect(await b.restoreToken(), isNull);
      await b.dispose();
    });

    test('a purchase completing outside the paywall is verified, then finished', () async {
      final store = FakeStore();
      final b = PlayBillingAdapter(store);
      final seen = <String>[];
      b.listen((t) async => seen.add(t.token));
      store.updates.add([purchased('late-tok')]);
      await pumpEventQueue();
      expect(seen, ['late-tok']);
      expect(store.completed.single.token, 'late-tok');

      // A failed server call leaves it unfinished (Play redelivers it).
      b.listen((t) async => throw StateError('offline'));
      store.updates.add([purchased('late-2')]);
      await pumpEventQueue();
      expect(store.completed, hasLength(1));
      await b.dispose();
    });

    test('API mode on Android: subscribe posts the Play token, then finishes', () async {
      final store = FakeStore()..onBuy = [purchased('play-tok-9')];
      final a = RouteAdapter({'POST /v1/subscription/restore': (o) => (200, _subJson)});
      final c = api(
        a,
        extra: [storeBillingSupportedProvider.overrideWithValue(true), storeClientProvider.overrideWithValue(store)],
      );
      expect(c.read(billingAdapterProvider), isA<PlayBillingAdapter>());
      expect(await c.read(accountActionsProvider).subscribe(), PurchaseOutcome.subscribed);
      final post = a.requests.singleWhere((r) => r.path == '/v1/subscription/restore');
      expect(post.data, {'store': 'play', 'purchase_token': 'play-tok-9'});
      expect(store.completed.single.token, 'play-tok-9');

      store.onBuy = [const StorePurchase(productId: 'banega_weekly_50', status: StorePurchaseStatus.pending)];
      expect(await c.read(accountActionsProvider).subscribe(), PurchaseOutcome.pending);
      store.onBuy = [const StorePurchase(productId: 'banega_weekly_50', status: StorePurchaseStatus.canceled)];
      expect(await c.read(accountActionsProvider).subscribe(), PurchaseOutcome.cancelled);
      expect(a.count('POST /v1/subscription/restore'), 1);
    });

    test('the sandbox keeps the demo adapter', () {
      final c = containerAt(testNoon, overrides: [storeBillingSupportedProvider.overrideWithValue(true)]);
      expect(c.read(billingAdapterProvider), isA<DemoBillingAdapter>());
    });
  });
}
