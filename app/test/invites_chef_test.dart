import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/config.dart';
import 'package:banega/core/l10n/gen/app_localizations.dart';
import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/data/repositories.dart' show wireDate;
import 'package:banega/features/account/application/account_providers.dart';
import 'package:banega/features/account/application/locale_controller.dart' show hinglish;
import 'package:banega/features/auth/application/auth_controller.dart';
import 'package:banega/features/auth/application/session.dart';
import 'package:banega/features/auth/data/token_store.dart';
import 'package:banega/features/auth/domain/auth_models.dart';
import 'package:banega/features/auth/presentation/auth_screens.dart';
import 'package:banega/features/chat/presentation/chat_labels.dart';
import 'package:banega/features/invites/application/invites_providers.dart';
import 'package:banega/features/invites/data/invites_repository.dart';
import 'package:banega/features/invites/domain/invite_models.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

typedef _Handler = (int, Object?) Function(RequestOptions o);

class _Routes implements HttpClientAdapter {
  _Routes(this.routes);

  final Map<String, _Handler> routes;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    await Future<void>.delayed(Duration.zero);
    final h = routes['${o.method} ${o.path}'];
    final (status, data) = h == null ? (404, {'code': 'not_found'}) : h(o);
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

Dio _dio(_Routes a) => Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = a;

Map<String, Object?> _err(String code) => {'code': code, 'message_en': code, 'message_hi': code};

Map<String, Object?> _me({String? household}) => {
  'user': {'id': 'u2', 'phone': '+919800000002'},
  'membership': household == null
      ? null
      : {'household_id': household, 'is_admin': false, 'is_member': true, 'status': 'active'},
  'modes': ['family'],
  'consent': {'current_version': '2026-09', 'required': false},
};

/// A ticket confirmed through the demo kitchen for today's lunch with no cook.
Future<Ticket> _unassigned(ProviderContainer c) async {
  final k = c.read(demoKitchenProvider);
  var m = await k.putDishes(wireDate(testNoon), 'lunch', ['daltadka', 'lauki']);
  m = await k.patchMenu(m.id, const MenuPatch(assigneeCookId: null, assigneeSet: true));
  final t = (await k.confirm(m.id, version: m.version, idempotencyKey: 'chef-test')).ticket;
  c.read(kitchenRevisionProvider.notifier).bump();
  return t;
}

void main() {
  group('invites repository (fake adapter)', () {
    test('create / list / revoke / accept-code shapes', () async {
      final a = _Routes({
        'POST /v1/invites': (o) => (
          201,
          {
            'id': 'i1',
            'phone': (o.data as Map)['phone'],
            'role': 'member',
            'member_id': (o.data as Map)['member_id'],
            'expires_at': '2026-10-09T08:00:00Z',
            'used_at': null,
            'revoked_at': null,
            'created_at': '2026-10-02T08:00:00Z',
            'token': 'tok',
            'link': 'https://banega.app/invite/tok',
            'code': 'K7Q4MX',
            'share_text': 'Namaste! ... K7Q4MX',
          },
        ),
        'GET /v1/invites': (_) => (
          200,
          [
            {'id': 'i1', 'phone': '+919800000002', 'role': 'member', 'expires_at': '2026-10-09T08:00:00Z'},
          ],
        ),
        'DELETE /v1/invites/i1': (_) => (204, null),
        'POST /v1/invites/accept-code': (_) => (200, _me(household: 'h1')),
      });
      final repo = ApiInvitesRepository(_dio(a));
      final inv = await repo.create(phone: '+919800000002', memberId: 'm9');
      expect(inv.code, 'K7Q4MX');
      expect(inv.shareText, contains('K7Q4MX'));
      expect(inv.expiresAt, isNotNull);
      expect(inv.phoneMasked, '+91******0002');
      expect(a.requests.last.data, {'phone': '+919800000002', 'role': 'member', 'member_id': 'm9'});

      final pending = await repo.pending();
      expect(pending.single.id, 'i1');
      await repo.revoke('i1');
      expect(a.requests.last.method, 'DELETE');

      await repo.acceptCode(' k7q-4mx ');
      expect(a.requests.last.data, {'code': 'K7Q4MX'});
    });

    test('accept-code errors map to friendly copy', () async {
      final l = lookupAppLocalizations(const Locale('en'));
      final cases = {
        (404, 'invite_code_invalid'): l.joinErrInvalid,
        (410, 'invite_expired'): l.joinErrExpired,
        (403, 'invite_phone_mismatch'): l.joinErrPhone,
        (409, 'already_in_household'): l.joinErrAlready,
        (429, 'invite_code_locked'): l.joinErrLocked,
      };
      for (final MapEntry(key: (status, code), value: text) in cases.entries) {
        final repo = ApiInvitesRepository(_dio(_Routes({'POST /v1/invites/accept-code': (_) => (status, _err(code))})));
        try {
          await repo.acceptCode('ABCDEF');
          fail('expected $code');
        } on AppError catch (e) {
          expect(appErrorCode(e), code);
          expect(joinErrorText(l, e), text, reason: code);
        }
      }
    });

    test('demo invites: code from the safe alphabet, revoke removes', () async {
      final repo = DemoInvitesRepository();
      final inv = await repo.create(phone: '+919800000002');
      expect(inv.code.length, kInviteCodeLength);
      expect(inv.code.split('').every(kInviteCodeAlphabet.contains), isTrue);
      expect((await repo.pending()).single.id, inv.id);
      await repo.revoke(inv.id);
      expect(await repo.pending(), isEmpty);
      expect(normalizeInviteCode('k7q 4-mx'), 'K7Q4MX');
    });
  });

  group('join with a code (invitee)', () {
    testWidgets('create-household offers "Code se judiye"; errors, then success â†’ Home', (tester) async {
      var joined = false;
      var attempts = 0;
      final a = _Routes({
        'GET /v1/me': (_) => (200, _me(household: joined ? 'h1' : null)),
        'POST /v1/invites/accept-code': (o) {
          attempts++;
          if (attempts == 1) return (403, _err('invite_phone_mismatch'));
          joined = true;
          return (200, _me(household: 'h1'));
        },
      });
      final c = await pumpBanega(
        tester,
        Routes.createHousehold,
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          tokenStoreProvider.overrideWithValue(
            MemoryTokenStore(const AuthTokens(accessToken: 'a1', refreshToken: 'r1', userId: 'u2')),
          ),
          keyValueStoreProvider.overrideWithValue(MemoryStore({ConsentController.storeKey: kConsentVersion})),
          httpClientAdapterProvider.overrideWithValue(a),
        ],
      );
      await settle(tester);
      expect(find.byType(CreateHouseholdScreen), findsOneWidget);
      expect(find.text('Code se judiye'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('household-join')));
      await settle(tester);
      expect(find.byType(JoinHouseholdScreen), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('join-code')), 'k7q4mx');
      await settle(tester);
      expect((a.requests.last.data as Map)['code'], 'K7Q4MX');
      expect(find.byKey(const ValueKey('join-error')), findsOneWidget);
      expect(find.text(lookupAppLocalizations(hinglish).joinErrPhone), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('join-submit')));
      await settle(tester);
      await settle(tester);
      expect(attempts, 2);
      expect(c.read(sessionProvider)?.householdId, 'h1');
      expect(find.byType(JoinHouseholdScreen), findsNothing);
      expect(c.read(authControllerProvider).status, AuthStatus.signedIn);
    });
  });

  group('Settings â†’ family on Banega (admin)', () {
    testWidgets('invite a new member: code, WhatsApp share, then revoke', (tester) async {
      final shared = <String>[];
      final c = await pumpBanega(
        tester,
        Routes.settings,
        tall: true,
        overrides: [shareTextProvider.overrideWithValue((text) async => shared.add(text))],
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('settings-invites')), findsOneWidget);
      expect(find.byKey(const ValueKey('invites-empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-invite')));
      await settle(tester);
      expect(find.byKey(const ValueKey('invite-form')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('invite-who-new')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('invite-phone')), '98000');
      await tester.tap(find.byKey(const ValueKey('invite-create')));
      await settle(tester);
      expect(find.byKey(const ValueKey('invite-error')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('invite-name')), 'Bhabhi');
      await tester.enterText(find.byKey(const ValueKey('invite-phone')), '9800000002');
      await tester.tap(find.byKey(const ValueKey('invite-create')));
      await settle(tester);
      expect(find.byKey(const ValueKey('invite-created')), findsOneWidget);
      final code = tester.widget<Text>(find.byKey(const ValueKey('invite-code'))).data!;
      expect(code.length, 6);

      await tester.tap(find.byKey(const ValueKey('invite-share')));
      await settle(tester);
      expect(shared.single, contains(code));

      await tester.tap(find.byKey(const ValueKey('invite-done')));
      await settle(tester);
      final pending = await c.read(invitesRepositoryProvider).pending();
      expect(pending.single.phone, '+919800000002');
      expect(find.byKey(ValueKey('invite-${pending.single.id}')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('invite-revoke-${pending.single.id}')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('invite-revoke-yes')));
      await settle(tester);
      expect(await c.read(invitesRepositoryProvider).pending(), isEmpty);
      expect(find.byKey(const ValueKey('invites-empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3)); // let the toast expire
    });
  });

  group('unassigned tickets + chef for the day', () {
    testWidgets('Home card shows the unassigned state', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      await _unassigned(c);
      await settle(tester);
      expect(find.byKey(const ValueKey('home-ticket-unassigned')), findsOneWidget);
      expect(find.text('Kaun banayega? Tap karke chuniye'), findsOneWidget);
    });

    testWidgets('admin assigns a hired cook â†’ new; a family cook â†’ accepted', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final t = await _unassigned(c);
      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      expect(find.byKey(const ValueKey('ticket-unassigned')), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-claim')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('assign-c1')));
      await settle(tester);
      final assigned = await c.read(demoKitchenProvider).ticket(t.id);
      expect(assigned.status, TicketStatus.fresh);
      expect(assigned.assignee?.cookId, 'c1');
      expect(find.byKey(const ValueKey('ticket-unassigned')), findsNothing);
      await tester.pump(const Duration(seconds: 3)); // let the toast expire
    });

    test('assign retries with the state the server names (409 allowed)', () async {
      final c = containerAt(testNoon);
      final t = await _unassigned(c);
      // c2 is a family cook: "new" is refused with allowed [accepted].
      await expectLater(
        c
            .read(demoKitchenProvider)
            .transition(t.id, TicketStatus.fresh, version: t.version, idempotencyKey: 'x', assigneeCookId: 'c2'),
        throwsA(isA<KitchenError>().having((e) => e.allowed, 'allowed', [TicketStatus.accepted])),
      );
      final next = await c.read(familyTicketActionsProvider).assign(t, 'c2', CookKind.hired);
      expect(next.status, TicketStatus.accepted);
      expect(next.assignee?.cookId, 'c2');
    });

    testWidgets('"Main banaunga" claims, refreshes /me (Rasoi), and a lost race toasts', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      expect((await c.read(meProvider.future)).canCook, isFalse);
      final t = await _unassigned(c);
      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ticket-claim')));
      await settle(tester);
      final claimed = await c.read(demoKitchenProvider).ticket(t.id);
      expect(claimed.status, TicketStatus.accepted);
      expect((await c.read(meProvider.future)).canCook, isTrue);
      expect(find.text(lookupAppLocalizations(hinglish).ticketClaimed), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // let the toast expire
    });

    testWidgets('claim lost to someone else â†’ "already taken" toast', (tester) async {
      final c = await pumpBanega(tester, Routes.home, tall: true);
      final t = await _unassigned(c);
      c.read(routerProvider).push(Routes.ticket(t.id));
      await settle(tester);
      // Somebody else claims first (the screen still shows the old copy).
      await c.read(demoKitchenProvider).claim(t.id);
      await tester.tap(find.byKey(const ValueKey('ticket-claim')));
      await settle(tester);
      expect(find.text(lookupAppLocalizations(hinglish).ticketAlreadyClaimed), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // let the toast expire
    });

    test('claim over the API: POST /claim, then /me is refetched', () async {
      final a = _Routes({
        'POST /v1/tickets/t1/claim': (_) => (
          200,
          {
            'id': 't1',
            'menu_id': 'm1',
            'date': '2026-09-26',
            'slot': 'lunch',
            'status': 'accepted',
            'assignee': {'cook_id': 'k9', 'name': 'Bhabhi', 'kind': 'family'},
            'version': 2,
          },
        ),
        'POST /v1/tickets/t2/claim': (_) => (409, _err('already_claimed')),
        'GET /v1/me': (_) => (
          200,
          {
            ..._me(household: 'h1'),
            'modes': ['family', 'cook'],
            'cook': {'id': 'k9', 'kind': 'family', 'login_mode': 'own'},
          },
        ),
      });
      final c = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
          tokenStoreProvider.overrideWithValue(
            MemoryTokenStore(const AuthTokens(accessToken: 'a1', refreshToken: 'r1', userId: 'u2')),
          ),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          httpClientAdapterProvider.overrideWithValue(a),
        ],
      );
      addTearDown(c.dispose);
      final unassigned = Ticket.fromJson({
        'id': 't1',
        'menu_id': 'm1',
        'date': '2026-09-26',
        'slot': 'lunch',
        'status': 'unassigned',
        'version': 1,
      });
      final next = await c.read(familyTicketActionsProvider).claim(unassigned);
      expect(next.status, TicketStatus.accepted);
      expect((await c.read(meProvider.future)).canCook, isTrue);
      await expectLater(
        c.read(familyTicketActionsProvider).claim(Ticket.fromJson({...unassigned.toJson(), 'id': 't2'})),
        throwsA(isA<KitchenError>().having((e) => e.code, 'code', 'already_claimed')),
      );
    });
  });

  group('chat chips', () {
    test('known Hinglish chips show in the app language; others pass through', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final hi = lookupAppLocalizations(const Locale('hi'));
      final hl = lookupAppLocalizations(hinglish);
      expect(en.localizeChip('Kuch halka'), 'Something light');
      expect(en.localizeChip('Dadi ke liye kya?'), 'What for Dadi?');
      expect(en.localizeChip('Aaj lunch mein kya?'), "What's for lunch today?");
      expect(hi.localizeChip('Kuch halka'), hi.followHalka);
      expect(hi.localizeChip('Kuch halka'), isNot('Kuch halka'));
      expect(hl.localizeChip('Kuch halka'), 'Kuch halka');
      // Already localized by the server, or unknown: unchanged.
      expect(en.localizeChip('Something with paneer'), 'Something with paneer');
      expect(en.localizeChip('Kuch naya'), 'Kuch naya');
    });
  });
}
