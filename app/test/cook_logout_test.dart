import 'package:banega/core/config.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/auth/application/auth_controller.dart';
import 'package:banega/features/auth/data/token_store.dart';
import 'package:banega/features/auth/domain/auth_models.dart';
import 'package:banega/features/auth/presentation/auth_screens.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show RouteAdapter, meJson;
import 'helpers.dart';

void main() {
  testWidgets('a hired cook can log out from the cook header', (tester) async {
    final a = RouteAdapter({
      'GET /v1/me': (_) => (
        200,
        {
          ...meJson(modes: const ['cook']),
          'cook': {'id': 'c1', 'kind': 'hired', 'login_mode': 'own', 'on_duty': true},
        },
      ),
      'GET /v1/tickets': (_) => (200, <Object>[]),
      'GET /v1/cooks': (_) => (
        200,
        [
          {'id': 'c1', 'name': 'Ramesh ji', 'kind': 'hired', 'is_primary': true, 'is_backup': false, 'on_duty': true},
        ],
      ),
      'GET /v1/inbox': (_) => (200, <Object>[]),
      'GET /v1/subscription': (_) => (200, {'status': 'trial', 'days_left': 7}),
      'POST /v1/auth/logout': (_) => (200, <String, Object?>{}),
    });
    final store = MemoryTokenStore(const AuthTokens(accessToken: 'a1', refreshToken: 'r1', userId: 'u1'));
    await pumpBanega(
      tester,
      Routes.cook,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
        tokenStoreProvider.overrideWithValue(store),
        keyValueStoreProvider.overrideWithValue(MemoryStore({ConsentController.storeKey: kConsentVersion})),
        httpClientAdapterProvider.overrideWithValue(a),
      ],
    );
    await settle(tester);
    final logout = find.byKey(const ValueKey('cook-logout'));
    expect(logout, findsOneWidget);

    await tester.tap(logout);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cook-logout-cancel')));
    await settle(tester);
    expect(store.tokens, isNotNull, reason: 'cancel keeps the session');

    await tester.tap(logout);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('cook-logout-confirm')));
    await settle(tester);
    await settle(tester);
    expect(a.count('POST /v1/auth/logout'), 1);
    expect(store.tokens, isNull);
    expect(find.byType(PhoneScreen), findsOneWidget);
  });

  testWidgets('a hired cook sees the duty toggle from /me even though /v1/cooks is 403', (tester) async {
    final a = RouteAdapter({
      'GET /v1/me': (_) => (
        200,
        {
          ...meJson(modes: const ['cook']),
          'cook': {'id': 'c1', 'kind': 'hired', 'login_mode': 'own', 'on_duty': true, 'off_duty_until': null},
        },
      ),
      'GET /v1/tickets': (_) => (200, <Object>[]),
      'GET /v1/cooks': (_) => (
        403,
        {
          'code': 'forbidden',
          'details': {'reason': 'cook_mode'},
        },
      ),
      'GET /v1/inbox': (_) => (200, <Object>[]),
      'GET /v1/subscription': (_) => (200, {'status': 'trial', 'days_left': 7}),
    });
    await pumpBanega(
      tester,
      Routes.cook,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
        tokenStoreProvider.overrideWithValue(
          MemoryTokenStore(const AuthTokens(accessToken: 'a1', refreshToken: 'r1', userId: 'u1')),
        ),
        keyValueStoreProvider.overrideWithValue(MemoryStore({ConsentController.storeKey: kConsentVersion})),
        httpClientAdapterProvider.overrideWithValue(a),
      ],
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('cook-duty')), findsOneWidget);
  });
}
