import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/features/kitchen/data/kitchen_api.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers by "METHOD path" and records every request.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);

  final Map<String, (int, Object)> routes;
  final List<RequestOptions> requests = [];

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

const _dish = {
  'recipe_id': 'r-dal',
  'name': 'Dal Tadka',
  'colour': '#E8B73A',
  'image_url': 'https://cdn.test/dal.webp',
  'mins': 30,
  'summary': {
    'badge': 'tweak',
    'label_key': 'all_with_tweaks',
    'label_params': {'count': 1},
    'note_key': 'low_oil',
    'note_params': {'name': 'Papa'},
  },
};

const _eaters = [
  {'member_id': 'm1', 'name': 'Papa', 'colour': '#2F5FC4', 'is_kid': false},
  {'member_id': 'm4', 'name': 'Daughter', 'colour': '#B85A0C', 'is_kid': true},
];

const _menu = {
  'id': 'menu-1',
  'date': '2026-09-26',
  'slot': 'lunch',
  'dishes': [_dish],
  'eaters': _eaters,
  'guests': {'adults': 2, 'kids': 1, 'diet': 'jain'},
  'servings': 4.0,
  'due_at': '2026-09-26T13:30:00+05:30',
  'assignee': {'cook_id': 'c1', 'name': 'Ramesh ji', 'kind': 'hired'},
  'coverage': {
    'all_covered': false,
    'uncovered': ['Dadi'],
  },
  'required_items': [
    {'ingredient_id': 'i-dal', 'display_text': 'Toor dal 1 cup', 'status': 'in'},
    {'ingredient_id': 'i-ghee', 'display_text': 'Ghee', 'status': 'low'},
    {'ingredient_id': 'i-hing', 'display_text': 'Hing', 'status': 'untracked'},
  ],
  'ticket_id': null,
  'version': 7,
};

const _ticket = {
  'id': 't-1',
  'menu_id': 'menu-1',
  'date': '2026-09-26',
  'slot': 'lunch',
  'due_at': '2026-09-26T13:30:00+05:30',
  'status': 'new',
  'assignee': {'cook_id': 'c1', 'name': 'Ramesh ji', 'kind': 'hired'},
  'dishes': [_dish],
  'eaters': _eaters,
  'guests': {'adults': 0, 'kids': 0, 'diet': null},
  'servings': 1.5,
  'notes': 'Dadi ke liye katori alag',
  'stock_issue_open': false,
  'accepted_at': null,
  'started_at': null,
  'completed_at': null,
  'completed_by': null,
  'rated_at': null,
  'change_log': [
    {
      'at': '2026-09-26T09:00:00+05:30',
      'by': {'id': 'u1', 'name': 'Anshul'},
      'action': 'created',
      'detail': null,
    },
  ],
  'version': 1,
};

void main() {
  test('Menu parses the contract shape', () async {
    final a = _Adapter({'GET /v1/menus': (200, _menu)});
    final m = (await ApiMenusRepository(_dio(a)).menu('2026-09-26', 'lunch'))!;
    expect(a.requests.single.queryParameters, {'date': '2026-09-26', 'slot': 'lunch'});
    expect(m.id, 'menu-1');
    expect(m.dishes.single.name, 'Dal Tadka');
    expect(m.dishes.single.summary?.noteKey, 'low_oil');
    expect(m.eaters.map((e) => e.isKid), [false, true]);
    expect(m.guests, const Guests(adults: 2, kids: 1, diet: GuestDiet.jain));
    expect(m.headcount, 5);
    expect(m.servings, 4.0);
    expect(m.dueAt!.toUtc(), DateTime.utc(2026, 9, 26, 8));
    expect(m.assignee?.kind, CookKind.hired);
    expect(m.coverage.uncovered, ['Dadi']);
    expect(m.requiredItems.map((i) => i.status), [ItemStatus.inStock, ItemStatus.low, ItemStatus.untracked]);
    expect(m.ticketId, isNull);
    expect(m.version, 7);
  });

  test('menu 404 → null; PUT dishes and PATCH send the contract bodies', () async {
    final a = _Adapter({'PUT /v1/menus/2026-09-26/lunch/dishes': (200, _menu), 'PATCH /v1/menus/menu-1': (200, _menu)});
    final repo = ApiMenusRepository(_dio(a));
    expect(await repo.menu('2026-09-26', 'dinner'), isNull);
    await repo.putDishes('2026-09-26', 'lunch', ['r-dal', 'r-roti']);
    expect(a.requests.last.data, {
      'recipe_ids': ['r-dal', 'r-roti'],
    });
    await repo.patchMenu(
      'menu-1',
      MenuPatch(
        eaters: const ['m1'],
        guests: const Guests(adults: 1),
        dueAt: DateTime(2026, 9, 26, 14),
        assigneeSet: true,
      ),
    );
    final body = a.requests.last.data as Map;
    expect(body['eaters'], ['m1']);
    expect(body['guests'], {'adults': 1, 'kids': 0, 'diet': null});
    expect(body['due_at'], startsWith('2026-09-26T14:00:00'));
    expect(body.containsKey('assignee_cook_id'), isTrue);
    expect(body['assignee_cook_id'], isNull);
    expect(body.containsKey('notes'), isFalse);
  });

  test('confirm sends Idempotency-Key and If-Match and parses {ticket, share_text}', () async {
    final a = _Adapter({
      'POST /v1/menus/menu-1/confirm': (201, {'ticket': _ticket, 'share_text': 'Aaj ka lunch…'}),
    });
    final r = await ApiMenusRepository(_dio(a)).confirm('menu-1', version: 7, idempotencyKey: 'idem-123');
    final req = a.requests.single;
    expect(req.headers['If-Match'], '7');
    expect(req.headers['Idempotency-Key'], 'idem-123');
    expect(r.shareText, 'Aaj ka lunch…');
    expect(r.ticket.status, TicketStatus.fresh);
    expect(r.ticket.notes, 'Dadi ke liye katori alag');
    expect(r.ticket.changeLog.single.by, 'Anshul');
    expect(r.ticket.servingsInt, 2);
  });

  test('transition: headers + body; 409 → KitchenError with the allowed list', () async {
    final a = _Adapter({
      'POST /v1/tickets/t-1/transitions': (
        409,
        {
          'code': 'invalid_transition',
          'allowed': ['accepted', 'cancelled'],
        },
      ),
    });
    final repo = ApiTicketsRepository(_dio(a));
    await expectLater(
      repo.transition('t-1', TicketStatus.cooking, version: 1, idempotencyKey: 'k-9', note: 'x'),
      throwsA(
        isA<KitchenError>()
            .having((e) => e.isConflict, 'conflict', isTrue)
            .having((e) => e.code, 'code', 'invalid_transition')
            .having((e) => e.allowed, 'allowed', [TicketStatus.accepted, TicketStatus.cancelled]),
      ),
    );
    final req = a.requests.single;
    expect(req.data, {'to': 'cooking', 'note': 'x'});
    expect(req.headers['If-Match'], '1');
    expect(req.headers['Idempotency-Key'], 'k-9');
  });

  test('409 wrapped in FastAPI `detail` also parses', () {
    final e = KitchenError.fromJson(409, {
      'detail': {
        'code': 'invalid_transition',
        'allowed': ['completed'],
      },
    });
    expect(e.allowed, [TicketStatus.completed]);
  });

  test('tickets list, PATCH, item out, messages and cook recipe', () async {
    final a = _Adapter({
      'GET /v1/tickets': (
        200,
        {
          'items': [_ticket],
        },
      ),
      'PATCH /v1/tickets/t-1': (200, {..._ticket, 'status': 'new', 'updated': true, 'version': 2}),
      'POST /v1/tickets/t-1/items/i-ghee/out': (200, {..._ticket, 'stock_issue_open': true, 'version': 3}),
      'GET /v1/tickets/t-1/messages': (
        200,
        [
          {
            'id': 'x1',
            'text': 'Dahi khatam hai',
            'author': {'name': 'Ramesh ji', 'role': 'cook'},
            'created_at': '2026-09-26T12:00:00+05:30',
          },
        ],
      ),
      'GET /v1/tickets/t-1/recipes/r-dal': (
        200,
        {
          'id': 'r-dal',
          'name': 'Dal Tadka',
          'base_servings': 4,
          'servings': 2,
          'ingredients': [
            {'display_text': 'Toor dal 1 cup', 'scaled_text': 'Toor dal ½ cup'},
          ],
          'steps': ['Dal dho lo.', 'Tadka lagao.'],
          'steps_hi': ['दाल धो लो।', 'तड़का लगाओ।'],
          'audio': {
            'steps_hi': ['https://cdn.test/s1.mp3', null],
          },
        },
      ),
    });
    final repo = ApiTicketsRepository(_dio(a));
    final list = await repo.tickets(date: '2026-09-26', mine: true);
    expect(list.single.id, 't-1');
    expect(a.requests.last.queryParameters, {'date': '2026-09-26', 'mine': 'true'});

    final p = await repo.patchTicket('t-1', const TicketPatch(servings: 5, notes: 'kam tel'), version: 1);
    expect(a.requests.last.headers['If-Match'], '1');
    expect(a.requests.last.data, {'servings': 5.0, 'notes': 'kam tel'});
    expect(p.updated, isTrue);

    final out = await repo.markItemOut('t-1', 'i-ghee');
    expect(out.stockIssueOpen, isTrue);

    final msgs = await repo.messages('t-1');
    expect(msgs.single.fromCook, isTrue);
    expect(msgs.single.author, 'Ramesh ji');

    final r = await repo.recipe('t-1', 'r-dal', servings: 2);
    expect(a.requests.last.queryParameters, {'servings': 2});
    expect(r.detail.ingredients.single.scaledText, 'Toor dal ½ cup');
    expect(r.audioUrl(0), 'https://cdn.test/s1.mp3');
    expect(r.audioUrl(1), isNull);
    expect(r.spokenStep(1), 'तड़का लगाओ।');
    expect(r.raw, isNotNull);
  });

  test('cooks, duty PATCH, /me modes and inbox', () async {
    final a = _Adapter({
      'GET /v1/cooks': (
        200,
        [
          {
            'id': 'c1',
            'name': 'Ramesh ji',
            'kind': 'hired',
            'member_id': null,
            'user_id': 'u9',
            'login_mode': 'otp',
            'is_primary': true,
            'is_backup': false,
            'on_duty': true,
            'off_duty_until': null,
            'phone_masked': '98xxxxxx21',
          },
        ],
      ),
      'PATCH /v1/cooks/c1': (
        200,
        {
          'id': 'c1',
          'name': 'Ramesh ji',
          'kind': 'hired',
          'on_duty': false,
          'off_duty_until': '2026-09-28T00:00:00+05:30',
        },
      ),
      'GET /v1/me': (
        200,
        {
          'modes': ['family', 'cook'],
          'cook': {'id': 'c2', 'kind': 'family', 'login_mode': 'app'},
        },
      ),
      'GET /v1/inbox': (
        200,
        [
          {
            'id': 'e1',
            'event': 'ticket_accepted',
            'title': 'Accept ho gaya',
            'body': '',
            'ticket_id': 't-1',
            'read_at': null,
            'created_at': '2026-09-26T10:00:00+05:30',
          },
        ],
      ),
      'POST /v1/inbox/e1/read': (204, {}),
    });
    final cooks = ApiCooksRepository(_dio(a));
    final list = await cooks.cooks();
    expect(list.single.isPrimary, isTrue);
    expect(list.single.phoneMasked, '98xxxxxx21');
    final off = await cooks.patchCook('c1', CookPatch(onDuty: false, offDutyUntil: DateTime(2026, 9, 28)));
    expect((a.requests.last.data as Map)['on_duty'], false);
    expect((a.requests.last.data as Map)['off_duty_until'], startsWith('2026-09-28T00:00:00'));
    expect(off.onDuty, isFalse);
    final me = await cooks.me();
    expect(me.canCook, isTrue);
    expect(me.cook?.kind, CookKind.family);

    final inbox = ApiInboxRepository(_dio(a));
    final items = await inbox.inbox();
    expect(items.single.unread, isTrue);
    expect(items.single.ticketId, 't-1');
    await inbox.markRead('e1');
    expect(a.requests.last.path, '/v1/inbox/e1/read');
  });

  test('Ticket JSON round-trips (offline cache)', () {
    final t = Ticket.fromJson(_ticket);
    final back = Ticket.fromJson(t.toJson());
    expect(back.toJson(), t.toJson());
    expect(back.dishes.single.summary?.labelKey, 'all_with_tweaks');
    expect(back.dueAt, t.dueAt);
  });
}
