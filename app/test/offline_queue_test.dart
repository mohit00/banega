import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:banega/core/router/routes.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/application/sync_service.dart';
import 'package:banega/features/kitchen/data/kitchen_api.dart';
import 'package:banega/features/kitchen/data/ticket_cache.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Ticket sample(String id, {int version = 3, TicketStatus status = TicketStatus.fresh}) => Ticket.fromJson({
  'id': id,
  'menu_id': 'm-$id',
  'date': '2026-09-26',
  'slot': 'lunch',
  'status': status.wire,
  'version': version,
  'dishes': [
    {'recipe_id': 'daltadka', 'name': 'Dal Tadka', 'colour': '#F3EFE6'},
  ],
});

/// Answers by a handler; can hold every response until [gate] completes.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final (int, Object?) Function(RequestOptions o) handler;
  final List<RequestOptions> requests = [];
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    if (gate != null) await gate!.future;
    final (status, body) = handler(o);
    if (status == 0) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
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

ApiTicketsRepository _repo(_Adapter a) =>
    ApiTicketsRepository(Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = a);

QueuedMutation _t(String key, TicketStatus to, {String? note}) =>
    QueuedMutation(key: key, ticketId: 't1', kind: QueuedMutation.transition, to: to, version: 3, note: note);

(int, Object?) _ok(RequestOptions o) {
  final body = o.data as Map;
  final v = int.parse('${o.headers['If-Match'] ?? 3}') + 1;
  return (200, {...sample('t1').toJson(), 'status': body['to'], 'version': v});
}

void main() {
  group('MutationQueue', () {
    test('5xx / 429 / offline keep the write (and the rest) queued, in order', () async {
      for (final status in [0, 500, 503, 408, 429]) {
        final q = MutationQueue(MemoryStore());
        await q.add(_t('k1', TicketStatus.accepted));
        await q.add(_t('k2', TicketStatus.cooking));
        final r = await q.replay(_repo(_Adapter((_) => (status, {'code': 'x'}))));
        expect(r.sent, 0, reason: '$status');
        expect(r.stoppedBy?.retryable, isTrue, reason: '$status');
        expect((await q.all()).map((m) => m.key), ['k1', 'k2'], reason: '$status');
      }
    });

    test('409 / 412 / 422 are dropped and reported', () async {
      for (final status in [409, 412, 422]) {
        final q = MutationQueue(MemoryStore());
        await q.add(_t('k1', TicketStatus.accepted));
        final r = await q.replay(_repo(_Adapter((_) => (status, {'code': 'nope'}))));
        expect(r.dropped.single.$1.key, 'k1', reason: '$status');
        expect(await q.all(), isEmpty);
      }
    });

    test('one replay at a time; an add during a replay is not lost', () async {
      final q = MutationQueue(MemoryStore());
      await q.add(_t('k1', TicketStatus.accepted));
      final a = _Adapter(_ok)..gate = Completer<void>();
      final first = q.replay(_repo(a));
      final second = q.replay(_repo(a));
      await pumpEventQueue();
      await q.add(_t('k2', TicketStatus.cooking));
      a.gate!.complete();
      final (r1, r2) = (await first, await second);
      expect(identical(r1, r2), isTrue, reason: 'joined, not doubled');
      expect(a.requests.where((r) => r.headers['Idempotency-Key'] == 'k1'), hasLength(1));
      // k2 was added mid-replay: sent by the same run or kept for the next.
      final rest = await q.all();
      expect(rest.every((m) => m.key == 'k2'), isTrue);
      if (rest.isNotEmpty) {
        await q.replay(_repo(_Adapter(_ok)));
        expect(await q.all(), isEmpty);
      }
    });

    test('keeps the transition note and replays it', () async {
      final q = MutationQueue(MemoryStore());
      await q.add(_t('k1', TicketStatus.completed, note: 'thoda namak kam'));
      expect((await q.all()).single.note, 'thoda namak kam');
      final a = _Adapter(_ok);
      await q.replay(_repo(a));
      expect((a.requests.single.data as Map)['note'], 'thoda namak kam');
    });

    test('the same intent is queued once', () async {
      final q = MutationQueue(MemoryStore());
      await q.add(_t('k1', TicketStatus.accepted));
      await q.add(_t('k1', TicketStatus.accepted));
      expect(await q.all(), hasLength(1));
    });
  });

  group('TicketCache', () {
    test('scoped by user + household', () async {
      final store = MemoryStore();
      await TicketCache(store, scope: 'u1|h1').saveTicket(sample('t1'));
      expect(await TicketCache(store, scope: 'u1|h1').ticket('t1'), isNotNull);
      expect(await TicketCache(store, scope: 'u2|h2').ticket('t1'), isNull);
    });

    test('entries older than 3 days are ignored and evicted; purge wipes everything', () async {
      final store = MemoryStore();
      var now = DateTime(2026, 9, 26, 12);
      final cache = TicketCache(store, now: () => now);
      await cache.saveTicket(sample('t1'));
      await cache.saveMessages('t1', const [TicketMessage(id: 'm1', text: 'Namaste', author: 'Mummy')]);
      expect((await cache.messages('t1'))!.single.text, 'Namaste');
      now = now.add(const Duration(days: 3, hours: 1));
      expect(await cache.ticket('t1'), isNull);
      await cache.saveTicket(sample('t2'));
      await MutationQueue(store).add(_t('k1', TicketStatus.accepted));
      expect(await cache.evictExpired(), greaterThanOrEqualTo(1));
      expect(await cache.ticket('t2'), isNotNull);
      await TicketCache.purgeAll(store);
      expect(store.data.keys.where((k) => k.startsWith(kCachePrefix)), isEmpty);
    });

    test('thread messages come from the cache when offline', () async {
      final store = MemoryStore();
      final cache = TicketCache(store);
      final online = CachingTicketsRepository(
        inner: _repo(
          _Adapter(
            (_) => (
              200,
              [
                {
                  'id': 'm1',
                  'text': 'Dal ready',
                  'author': {'name': 'Ramesh', 'role': 'cook'},
                },
              ],
            ),
          ),
        ),
        cache: cache,
      );
      expect((await online.messages('t1')).single.text, 'Dal ready');
      final offline = CachingTicketsRepository(inner: _repo(_Adapter((_) => (0, null))), cache: cache);
      final msgs = await offline.messages('t1');
      expect(msgs.single.text, 'Dal ready');
      expect(msgs.single.fromCook, isTrue);
    });
  });

  group('SyncService', () {
    testWidgets('replays when connectivity returns; thread shows queued messages as not sent', (tester) async {
      final store = MemoryStore();
      final net = StreamController<void>.broadcast();
      addTearDown(net.close);
      var online = false;
      final a = _Adapter((o) {
        if (!online) return (0, null);
        if (o.path.endsWith('/messages') && o.method == 'POST') {
          return (201, {'id': 'm9', 'text': (o.data as Map)['text']});
        }
        if (o.path.endsWith('/messages')) return (200, <Object>[]);
        return (200, sample('t1').toJson());
      });
      final c = await pumpBanega(
        tester,
        Routes.cookThread('t1'),
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          cookUsesApiProvider.overrideWithValue(true),
          connectivityChangesProvider.overrideWithValue(net.stream),
          cookTicketsRepositoryProvider.overrideWith(
            (ref) => CachingTicketsRepository(inner: _repo(a), cache: ref.watch(ticketCacheProvider)),
          ),
        ],
      );
      await c
          .read(mutationQueueProvider)
          .add(const QueuedMutation(key: 'q1', ticketId: 't1', kind: QueuedMutation.message, text: 'Doodh khatam'));
      c.read(kitchenRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const ValueKey('queued-q1')), findsOneWidget);
      expect(find.text('Doodh khatam'), findsOneWidget);

      c.read(syncServiceProvider).start();
      online = true;
      net.add(null);
      await settle(tester);
      expect(await c.read(mutationQueueProvider).all(), isEmpty);
      expect(a.requests.any((r) => r.method == 'POST' && r.headers['Idempotency-Key'] == 'q1'), isTrue);
      expect(find.byKey(const ValueKey('queued-q1')), findsNothing);
    });
  });
}
