import 'package:banega/core/config.dart';
import 'package:banega/core/router/not_found_screen.dart';
import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/core/router/startup_gate.dart';
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/auth/application/auth_controller.dart';
import 'package:banega/features/auth/application/session.dart';
import 'package:banega/features/auth/data/token_store.dart';
import 'package:banega/features/auth/domain/auth_models.dart';
import 'package:banega/features/auth/presentation/auth_screens.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:banega/features/onboarding/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show RouteAdapter, meJson;
import 'helpers.dart';

const _family = Me(householdId: 'h1');
const _cook = Me(
  modes: ['cook'],
  cook: MeCook(id: 'c1', kind: CookKind.hired),
  householdId: 'h1',
);
const _noHouse = Me();

GateInput g({
  bool api = true,
  AuthStatus auth = AuthStatus.signedIn,
  bool? consent = true,
  bool? onboarded = true,
  Me? me = _family,
}) => GateInput(api: api, auth: auth, consent: consent, onboarded: onboarded, me: me);

String? at(GateInput i, String loc) => startupRedirect(i, Uri.parse(loc));

void main() {
  group('startupRedirect', () {
    test('sandbox: only the entry point is gated', () {
      expect(at(g(api: false, onboarded: false), Routes.start), Routes.splash);
      expect(at(g(api: false, consent: false), Routes.start), Routes.consentThen(Routes.home));
      expect(at(g(api: false), Routes.start), Routes.home);
      expect(at(g(api: false, consent: null), Routes.start), isNull, reason: 'waits while loading');
      expect(at(g(api: false, consent: false), Routes.home), isNull);
    });

    test('API, signed out: Splash on first launch, else phone login', () {
      expect(at(g(auth: AuthStatus.unknown), Routes.home), isNull);
      expect(at(g(auth: AuthStatus.signedOut, onboarded: false), Routes.start), Routes.splash);
      expect(at(g(auth: AuthStatus.signedOut), Routes.start), Routes.phone);
      expect(at(g(auth: AuthStatus.signedOut), Routes.home), Routes.phone);
      expect(at(g(auth: AuthStatus.signedOut), Routes.otp), isNull);
      expect(at(g(auth: AuthStatus.signedOut), Routes.consent), isNull);
    });

    test('API, signed in: consent, household, cook-only, entry screens', () {
      expect(at(g(consent: false), Routes.start), Routes.consentThen(Routes.home));
      expect(at(g(consent: false), Routes.plan), Routes.consentThen(Routes.plan));
      expect(at(g(me: null), Routes.start), isNull, reason: 'waits for /v1/me');
      expect(at(g(me: _noHouse), Routes.home), Routes.createHousehold);
      expect(at(g(me: _noHouse), Routes.createHousehold), isNull);
      expect(at(g(me: _cook), Routes.home), Routes.cook);
      expect(at(g(me: _cook), Routes.cookTicket('t1')), isNull);
      expect(at(g(), Routes.start), Routes.home);
      expect(at(g(), Routes.phone), Routes.home);
      expect(at(g(), Routes.plan), isNull);
      expect(at(g(me: _cook), Routes.start), Routes.cook);
    });
  });

  group('startup (widgets)', () {
    testWidgets('sandbox first launch shows Splash; later launches go straight Home', (tester) async {
      await pumpBanega(tester, Routes.start, overrides: [keyValueStoreProvider.overrideWithValue(MemoryStore())]);
      expect(find.byType(SplashScreen), findsOneWidget);
    });

    testWidgets('sandbox, onboarded and consented: /start → Home', (tester) async {
      final c = await pumpBanega(
        tester,
        Routes.start,
        overrides: [
          keyValueStoreProvider.overrideWithValue(
            MemoryStore({OnboardingController.storeKey: '1', ConsentController.storeKey: kConsentVersion}),
          ),
        ],
      );
      expect(c.read(routerProvider).state.uri.path, Routes.home);
    });

    testWidgets('API: signed out after onboarding → phone login', (tester) async {
      await pumpBanega(
        tester,
        Routes.start,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          keyValueStoreProvider.overrideWithValue(MemoryStore({OnboardingController.storeKey: '1'})),
          httpClientAdapterProvider.overrideWithValue(RouteAdapter(const {})),
        ],
      );
      expect(find.byType(PhoneScreen), findsOneWidget);
    });

    testWidgets('API: a hired cook lands on /cook and /me is cached', (tester) async {
      final store = MemoryStore({OnboardingController.storeKey: '1', ConsentController.storeKey: kConsentVersion});
      final c = await pumpBanega(
        tester,
        Routes.start,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore(const AuthTokens(accessToken: 'a', refreshToken: 'r'))),
          keyValueStoreProvider.overrideWithValue(store),
          httpClientAdapterProvider.overrideWithValue(
            RouteAdapter({
              'GET /v1/me': (_) => (
                200,
                {
                  ...meJson(modes: ['cook']),
                  'cook': {'id': 'c1', 'kind': 'hired', 'login_mode': 'app', 'on_duty': true},
                },
              ),
              'GET /v1/tickets': (_) => (200, <Object>[]),
            }),
          ),
        ],
      );
      await settle(tester);
      expect(c.read(sessionProvider)?.cookOnly, isTrue);
      expect(c.read(routerProvider).state.uri.path, Routes.cook);
      expect(store.data[SessionController.cacheKey], isNotNull, reason: '/me is cached for the next cold start');
    });

    testWidgets('unknown links show the not-found screen', (tester) async {
      final c = await pumpBanega(tester, Routes.home);
      c.read(routerProvider).go('/definitely/not/here');
      await settle(tester);
      expect(find.byType(NotFoundScreen), findsOneWidget);
    });
  });
}
