import 'package:banega/core/config.dart';
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/account/data/billing_adapter.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show RouteAdapter;
import 'helpers.dart';

void main() {
  group('billing', () {
    test('the store adapter has nothing to restore until in_app_purchase is wired', () async {
      const store = StoreBillingAdapter();
      expect(store.available, isFalse);
      expect(await store.restoreToken(), isNull);
      expect(await store.purchaseWeekly(), isNull);
    });

    test('API mode: restore sends nothing when billing is unavailable', () async {
      final a = RouteAdapter(const {});
      final c = containerAt(
        testNoon,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          httpClientAdapterProvider.overrideWithValue(a),
        ],
      );
      expect(c.read(billingAdapterProvider), isA<StoreBillingAdapter>());
      expect(await c.read(accountActionsProvider).restore(), isNull);
      expect(await c.read(accountActionsProvider).subscribe(), isFalse);
      expect(a.requests.where((r) => r.path.contains('/subscription/restore')), isEmpty);
    });
  });

  group('unknown ticket status', () {
    test('an unrecognised wire status is unknown, closed, with no actions', () {
      final s = TicketStatus.fromWire('teleported');
      expect(s, TicketStatus.unknown);
      expect(s.isOpen, isFalse);
      expect(s.editable, isFalse);
      expect(legalTransitions[s], isEmpty);
      expect(cookNextSteps(s), (null, null));
    });

    test('KitchenError.fromJson reads details.allowed and the localized messages', () {
      final e = KitchenError.fromJson(403, {
        'code': 'transition_not_allowed',
        'message_en': 'Only the cook can start',
        'message_hi': 'सिर्फ़ कुक शुरू कर सकते हैं',
        'details': {
          'allowed': ['cancelled'],
        },
      });
      expect(e.code, 'transition_not_allowed');
      expect(e.allowed, [TicketStatus.cancelled]);
      expect(e.messageEn, 'Only the cook can start');
      expect(e.messageHi, isNotNull);
    });
  });

  test('ticket / thread / cook providers are autoDispose (no unbounded growth)', () async {
    final c = containerAt(testNoon);
    final providers = [
      ticketProvider('t1'),
      threadProvider(('t1', false)),
      cookTicketsProvider('2026-09-26'),
      cookTicketProvider('t1'),
      cookRecipeProvider(('t1', 'daltadka', 4)),
    ];
    for (final p in providers) {
      final sub = c.listen(p, (_, _) {});
      expect(c.exists(p), isTrue);
      sub.close();
      await pumpEventQueue();
      expect(c.exists(p), isFalse, reason: '$p');
    }
  });
}
