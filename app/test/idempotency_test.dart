import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/router/routes.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/data/kitchen_api.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'offline_queue_test.dart' show sample;

class _Gated implements HttpClientAdapter {
  _Gated({this.fail = false});

  bool fail;
  final List<RequestOptions> requests = [];
  Completer<void> gate = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    await gate.future;
    if (fail) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    final body = o.data is Map ? o.data as Map : const {};
    return ResponseBody.fromString(
      jsonEncode({...sample('t1').toJson(), 'status': body['to'] ?? 'accepted', 'version': 4}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('intent keys: same intent → same key; new version or target → new key', () {
    final c = containerAt(testNoon);
    final key = c.read(intentKeyProvider);
    expect(key(['transition', 't1', 3, 'accepted']), key(['transition', 't1', 3, 'accepted']));
    expect(key(['transition', 't1', 3, 'accepted']), isNot(key(['transition', 't1', 4, 'accepted'])));
    expect(key(['transition', 't1', 3, 'accepted']), isNot(key(['transition', 't1', 3, 'cooking'])));
    expect(key(['confirm', 'm1', 2]), matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('a double tap sends one write', () async {
    final a = _Gated();
    final c = containerAt(
      testNoon,
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryStore()),
        cookUsesApiProvider.overrideWithValue(true),
        cookTicketsRepositoryProvider.overrideWith(
          (ref) => CachingTicketsRepository(
            inner: ApiTicketsRepository(Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = a),
            cache: ref.watch(ticketCacheProvider),
          ),
        ),
      ],
    );
    final actions = c.read(cookTicketActionsProvider);
    final t = sample('t1');
    final first = actions.transition(t, TicketStatus.accepted);
    await expectLater(actions.transition(t, TicketStatus.accepted), throwsA(isA<AlreadyInFlight>()));
    expect(c.read(ticketsInFlightProvider), contains('t1'));
    a.gate.complete();
    await first;
    expect(a.requests, hasLength(1));
    expect(c.read(ticketsInFlightProvider), isEmpty);
  });

  test('a retried intent reuses its Idempotency-Key (offline → queued → replay)', () async {
    final a = _Gated(fail: true)..gate.complete();
    final store = MemoryStore();
    final c = containerAt(
      testNoon,
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        cookUsesApiProvider.overrideWithValue(true),
        cookTicketsRepositoryProvider.overrideWith(
          (ref) => CachingTicketsRepository(
            inner: ApiTicketsRepository(Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = a),
            cache: ref.watch(ticketCacheProvider),
          ),
        ),
      ],
    );
    final t = sample('t1');
    await c.read(cookTicketActionsProvider).transition(t, TicketStatus.accepted);
    final firstKey = a.requests.single.headers['Idempotency-Key'];
    final queued = await c.read(mutationQueueProvider).all();
    expect(queued.single.key, firstKey);
    a.fail = false;
    await c.read(mutationQueueProvider).replay(c.read(cookTicketsRepositoryProvider));
    expect(a.requests.last.headers['Idempotency-Key'], firstKey);
    expect(firstKey, c.read(intentKeyProvider)(['transition', 't1', t.version, 'accepted']));
  });

  testWidgets('K1 action buttons are disabled while a write for that ticket is in flight', (tester) async {
    final c = await pumpBanega(tester, Routes.cook, tall: true);
    final k = c.read(demoKitchenProvider);
    late String id;
    await tester.runAsync(() async {
      var m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
      m = await k.patchMenu(m.id, MenuPatch(assigneeCookId: 'c1', assigneeSet: true));
      id = (await k.confirm(m.id, version: m.version, idempotencyKey: 'y')).ticket.id;
    });
    c.read(demoCookRoleProvider.notifier).set('c1');
    c.read(ticketsInFlightProvider.notifier).begin(id);
    c.read(kitchenRevisionProvider.notifier).bump();
    await settle(tester);
    final button = find.byKey(ValueKey('cook-action-$id-accepted'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await settle(tester);
    expect(k.ticketsSnapshot.firstWhere((t) => t.id == id).status, TicketStatus.fresh, reason: 'disabled: no write');
    c.read(ticketsInFlightProvider.notifier).end(id);
    await settle(tester);
    await tester.tap(button);
    await settle(tester);
    expect(k.ticketsSnapshot.firstWhere((t) => t.id == id).status, TicketStatus.accepted);
  });
}
