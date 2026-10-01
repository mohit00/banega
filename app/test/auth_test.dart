import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/config.dart';
import 'package:banega/core/network/api_client.dart';
import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/data_source.dart';
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/auth/application/auth_controller.dart';
import 'package:banega/features/auth/application/session.dart';
import 'package:banega/features/auth/data/token_store.dart';
import 'package:banega/features/auth/domain/auth_models.dart';
import 'package:banega/features/auth/presentation/auth_screens.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:banega/features/members/presentation/family_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

typedef Handler = (int, Object?) Function(RequestOptions o);

/// Routes `METHOD /path` to a handler; records every request.
class RouteAdapter implements HttpClientAdapter {
  RouteAdapter(this.routes);

  final Map<String, Handler> routes;
  final List<RequestOptions> requests = [];

  int count(String key) => requests.where((r) => '${r.method} ${r.path}' == key).length;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    await Future<void>.delayed(Duration.zero);
    final h = routes['${o.method} ${o.path}'];
    final (status, data) = h == null ? (404, {'detail': 'not found'}) : h(o);
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _tokens = AuthTokens(accessToken: 'a1', refreshToken: 'r1', userId: 'u1');

Map<String, Object?> tokenJson(String a, String r) => {
  'access_token': a,
  'refresh_token': r,
  'access_expires_at': '2026-09-27T00:00:00Z',
  'refresh_expires_at': '2026-10-27T00:00:00Z',
  'user_id': 'u1',
};

Map<String, Object?> meJson({String? household = 'h1', List<String> modes = const ['family']}) => {
  'user': {'id': 'u1', 'phone': '+919876543210'},
  'membership': household == null
      ? null
      : {
          'household_id': household,
          'is_admin': true,
          'is_member': true,
          'member_id': null,
          'cook_id': null,
          'status': 'active',
        },
  'modes': modes,
  'consent': {'current_version': '2026-09', 'required': false},
};

ProviderContainer apiContainer(RouteAdapter adapter, {TokenStore? store}) {
  final c = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
      tokenStoreProvider.overrideWithValue(store ?? MemoryTokenStore(_tokens)),
      keyValueStoreProvider.overrideWithValue(MemoryStore()),
      httpClientAdapterProvider.overrideWithValue(adapter),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AppError mapping (one place)', () {
    test('status → variant; envelope fields parsed', () {
      expect(AppError.fromResponse(401, null), isA<UnauthorizedError>());
      expect(AppError.fromResponse(503, null), isA<ServerError>());
      expect(AppError.fromResponse(429, null).retryable, isTrue);
      expect(AppError.fromResponse(408, null), isA<ServerError>());
      final v = AppError.fromResponse(422, {'code': 'reason_required', 'message_en': 'Say why', 'message_hi': 'क्यों'});
      expect(v, isA<ValidationError>());
      expect((v as KitchenError).code, 'reason_required');
      expect(v.localizedMessage(const Locale('hi')), 'क्यों');
      expect(v.localizedMessage(const Locale('en')), 'Say why');

      final c = AppError.fromResponse(409, {
        'code': 'invalid_transition',
        'message_en': 'Not now',
        'details': {
          'allowed': ['cooking', 'cancelled'],
        },
      });
      expect(c, isA<ConflictError>());
      expect((c as KitchenError).allowed, [TicketStatus.cooking, TicketStatus.cancelled]);

      final m = AppError.fromResponse(412, {
        'detail': {
          'code': 'version_mismatch',
          'details': {'current_version': 7},
        },
      });
      expect((m as KitchenError).currentVersion, 7);
      expect(m.isConflict, isTrue);

      expect(
        AppError.from(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError)),
        isA<OfflineError>(),
      );
      expect(
        AppError.from(DioException(requestOptions: RequestOptions(), type: DioExceptionType.receiveTimeout)),
        isA<OfflineError>(),
      );
    });
  });

  group('ApiClient interceptors', () {
    test('bearer, Accept-Language and X-Request-Id on every request', () async {
      final a = RouteAdapter({'GET /v1/me': (_) => (200, meJson())});
      final c = apiContainer(a);
      await c.read(authControllerProvider.notifier).ready();
      await c.read(cooksRepositoryProvider).me();
      final r = a.requests.firstWhere((r) => r.path == '/v1/me');
      expect(r.headers['Authorization'], 'Bearer a1');
      expect(r.headers['Accept-Language'], isNotEmpty);
      expect(r.headers['X-Request-Id'], isNotEmpty);
    });

    test('401 → one refresh for concurrent requests, then replay with the new token', () async {
      final refreshGate = Completer<void>();
      final a = RouteAdapter({
        'GET /v1/me': (o) => o.headers['Authorization'] == 'Bearer a2' ? (200, meJson()) : (401, {'code': 'expired'}),
        'GET /v1/cooks': (o) =>
            o.headers['Authorization'] == 'Bearer a2' ? (200, <Object>[]) : (401, {'code': 'expired'}),
        'POST /v1/auth/refresh': (o) {
          if (!refreshGate.isCompleted) refreshGate.complete();
          return (200, tokenJson('a2', 'r2'));
        },
      });
      final store = MemoryTokenStore(_tokens);
      final c = apiContainer(a, store: store);
      await c.read(authControllerProvider.notifier).ready();
      final results = await Future.wait([
        c.read(cooksRepositoryProvider).me(),
        c.read(cooksRepositoryProvider).cooks(),
      ]);
      expect(results, hasLength(2));
      expect(a.count('POST /v1/auth/refresh'), 1, reason: 'single-flight');
      expect(store.tokens?.accessToken, 'a2');
      expect(c.read(authControllerProvider).tokens?.refreshToken, 'r2');
    });

    test('a rejected refresh logs out and surfaces UnauthorizedError', () async {
      final a = RouteAdapter({
        'GET /v1/me': (_) => (401, {'code': 'expired'}),
        'POST /v1/auth/refresh': (_) => (401, {'code': 'refresh_invalid'}),
      });
      final store = MemoryTokenStore(_tokens);
      final c = apiContainer(a, store: store);
      await c.read(authControllerProvider.notifier).ready();
      await expectLater(c.read(cooksRepositoryProvider).me(), throwsA(isA<UnauthorizedError>()));
      expect(c.read(authControllerProvider).status, AuthStatus.signedOut);
      expect(store.tokens, isNull);
    });

    test('offline during refresh keeps the session', () async {
      final a = RouteAdapter({
        'GET /v1/me': (_) => (401, {'code': 'expired'}),
      });
      final c = apiContainer(a);
      await c.read(authControllerProvider.notifier).ready();
      // The refresh call itself cannot reach the server.
      c.read(plainDioProvider).httpClientAdapter = _Offline();
      await expectLater(c.read(cooksRepositoryProvider).me(), throwsA(isA<OfflineError>()));
      expect(c.read(authControllerProvider).status, AuthStatus.signedIn);
    });

    test('SingleFlight joins concurrent callers', () async {
      final sf = SingleFlight<int>();
      var runs = 0;
      final gate = Completer<int>();
      final a = sf.run(() {
        runs++;
        return gate.future;
      });
      final b = sf.run(() async => 99);
      gate.complete(1);
      expect(await a, 1);
      expect(await b, 1);
      expect(runs, 1);
    });
  });

  group('OTP login', () {
    test('phone normalisation', () {
      expect(normalizeIndianPhone('98765 43210'), '+919876543210');
      expect(normalizeIndianPhone('+91-98765-43210'), '+919876543210');
      expect(normalizeIndianPhone('09876543210'), '+919876543210');
      expect(normalizeIndianPhone('12345'), isNull);
      expect(normalizeIndianPhone('1234567890'), isNull);
    });

    testWidgets('phone → OTP (dev code shown) → no household → create → Family', (tester) async {
      var hasHousehold = false;
      final a = RouteAdapter({
        'POST /v1/auth/otp': (o) => (200, {'sent': true, 'expires_in': 300, 'resend_after': 30, 'dev_code': '123456'}),
        'POST /v1/auth/verify': (o) =>
            (o.data as Map)['code'] == '123456' ? (200, tokenJson('a1', 'r1')) : (400, {'code': 'otp_invalid'}),
        'GET /v1/me': (_) => (200, meJson(household: hasHousehold ? 'h1' : null)),
        'POST /v1/households': (o) {
          hasHousehold = true;
          return (
            201,
            {
              'household': {'id': 'h1', 'name': (o.data as Map)['name']},
            },
          );
        },
        'GET /v1/members': (_) => (200, {'items': <Object>[]}),
      });
      final store = MemoryTokenStore();
      final c = await pumpBanega(
        tester,
        Routes.phone,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          tokenStoreProvider.overrideWithValue(store),
          keyValueStoreProvider.overrideWithValue(MemoryStore({ConsentController.storeKey: kConsentVersion})),
          httpClientAdapterProvider.overrideWithValue(a),
        ],
      );
      expect(find.byType(PhoneScreen), findsOneWidget);
      expect(find.text('Apna number'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('auth-phone')), '12345');
      await tester.tap(find.byKey(const ValueKey('auth-send-otp')));
      await settle(tester);
      expect(find.byKey(const ValueKey('auth-error')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('auth-phone')), '9876543210');
      await tester.tap(find.byKey(const ValueKey('auth-send-otp')));
      await settle(tester);
      expect(find.byType(OtpScreen), findsOneWidget);
      expect((a.requests.last.data as Map)['phone'], '+919876543210');
      expect(find.text('Dev code: 123456'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-resend-wait')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('auth-otp')), '123456');
      await settle(tester);
      await settle(tester);
      expect(store.tokens?.accessToken, 'a1');
      expect(find.byType(CreateHouseholdScreen), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('household-name')), 'Sharma Parivaar');
      await tester.tap(find.byKey(const ValueKey('household-create')));
      await settle(tester);
      await settle(tester);
      expect(a.count('POST /v1/households'), 1);
      expect(c.read(sessionProvider)?.householdId, 'h1');
      expect(find.byType(FamilyScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('resend unlocks after 30 s', (tester) async {
      final a = RouteAdapter({
        'POST /v1/auth/otp': (o) => (200, {'sent': true, 'expires_in': 300, 'resend_after': 30}),
      });
      final c = await pumpBanega(
        tester,
        Routes.splash,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          httpClientAdapterProvider.overrideWithValue(a),
        ],
      );
      c.read(otpChallengeProvider.notifier).set(const OtpChallenge(phone: '+919876543210'));
      c.read(routerProvider).push(Routes.otp);
      await settle(tester);
      expect(find.byKey(const ValueKey('auth-resend')), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.byKey(const ValueKey('auth-resend')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-resend')));
      await settle(tester);
      expect(a.count('POST /v1/auth/otp'), 1);
      expect(c.read(dataSourceProvider), DataSource.api);
    });
  });
}

class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);

  @override
  void close({bool force = false}) {}
}
