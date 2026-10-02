import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart' show SingleFlight;
import '../../../data/models.dart' show Json;
import '../domain/kitchen_models.dart';
import 'kitchen_repositories.dart';

/// String key/value storage for the cook-mode offline cache and small local
/// settings. The app uses [SharedPrefsStore]; tests use [MemoryStore].
abstract interface class KeyValueStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> keys();
}

class SharedPrefsStore implements KeyValueStore {
  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  @override
  Future<String?> get(String key) async => (await _p).getString(key);

  @override
  Future<void> set(String key, String value) async => (await _p).setString(key, value);

  @override
  Future<void> remove(String key) async => (await _p).remove(key);

  @override
  Future<Set<String>> keys() async => (await _p).getKeys();
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? seed]) : data = {...?seed};

  final Map<String, String> data;

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Set<String>> keys() async => data.keys.toSet();
}

/// Everything under this prefix belongs to the cook-mode cache / queue.
const kCachePrefix = 'k.';

/// Cook-mode read cache (F-10-01 Must): the K1 lists, each ticket, each
/// scaled recipe and each thread, as the wire JSON.
///
/// Keys are scoped by [scope] (`user|household`) so a second account on the
/// device never sees the first one's tickets; entries carry their write time
/// and are ignored (and evicted) after [ttl]. [purgeAll] runs on logout /
/// account deletion.
class TicketCache {
  TicketCache(this.store, {this.scope = 'local', this.ttl = const Duration(days: 3), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final KeyValueStore store;
  final String scope;
  final Duration ttl;
  final DateTime Function() _now;

  static String listKey({String? date, String? status, bool mine = false}) =>
      'list|${date ?? ''}|${status ?? ''}|${mine ? 1 : 0}';
  static String ticketKey(String id) => 'ticket|$id';
  static String recipeKey(String ticketId, String recipeId, int? servings) =>
      'recipe|$ticketId|$recipeId|${servings ?? ''}';
  static String messagesKey(String ticketId) => 'messages|$ticketId';

  String _k(String key) => '$kCachePrefix$scope|$key';

  Future<void> _put(String key, Object? value) =>
      store.set(_k(key), jsonEncode({'at': _now().millisecondsSinceEpoch, 'v': value}));

  Future<Object?> _get(String key) async {
    final raw = await store.get(_k(key));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || !j.containsKey('at')) return null;
      final at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt());
      if (_now().difference(at) > ttl) {
        await store.remove(_k(key));
        return null;
      }
      return j['v'];
    } catch (_) {
      return null;
    }
  }

  Future<void> saveList(String key, List<Ticket> tickets) async {
    await _put(key, [for (final t in tickets) t.id]);
    for (final t in tickets) {
      await saveTicket(t);
    }
  }

  Future<List<Ticket>?> list(String key) async {
    final ids = await _get(key);
    if (ids is! List) return null;
    return [for (final id in ids) ?await ticket('$id')];
  }

  Future<void> saveTicket(Ticket t) => _put(ticketKey(t.id), t.toJson());

  Future<Ticket?> ticket(String id) async {
    final v = await _get(ticketKey(id));
    return v is Map ? Ticket.fromJson(v.cast<String, dynamic>()) : null;
  }

  Future<void> saveRecipe(String ticketId, String recipeId, int? servings, Json raw) =>
      _put(recipeKey(ticketId, recipeId, servings), raw);

  Future<CookRecipe?> recipe(String ticketId, String recipeId, int? servings) async {
    final v = await _get(recipeKey(ticketId, recipeId, servings));
    return v is Map ? CookRecipe.fromJson(v.cast<String, dynamic>()) : null;
  }

  Future<void> saveMessages(String ticketId, List<TicketMessage> msgs) =>
      _put(messagesKey(ticketId), [for (final m in msgs) m.toJson()]);

  Future<List<TicketMessage>?> messages(String ticketId) async {
    final v = await _get(messagesKey(ticketId));
    if (v is! List) return null;
    return [for (final m in v) TicketMessage.fromJson((m as Map).cast<String, dynamic>())];
  }

  /// Drops entries older than [ttl] (any scope).
  Future<int> evictExpired() async {
    var n = 0;
    for (final key in await store.keys()) {
      if (!key.startsWith(kCachePrefix) || key.endsWith('|queue')) continue;
      final raw = await store.get(key);
      try {
        final j = raw == null ? null : jsonDecode(raw);
        final at = j is Map && j['at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()) : null;
        if (at == null || _now().difference(at) > ttl) {
          await store.remove(key);
          n++;
        }
      } catch (_) {
        await store.remove(key);
        n++;
      }
    }
    return n;
  }

  /// Logout / account deletion: every cached ticket, recipe, thread and
  /// queued write, for every scope.
  static Future<void> purgeAll(KeyValueStore store) async {
    for (final key in await store.keys()) {
      if (key.startsWith(kCachePrefix)) await store.remove(key);
    }
  }
}

/// Wraps the cook-mode tickets API: successful reads refresh [cache]; a
/// connection error answers from it (and [onOffline] reports which one
/// happened). Other errors surface.
class CachingTicketsRepository implements TicketsRepository {
  CachingTicketsRepository({required this.inner, required this.cache, this.onOffline});

  final TicketsRepository inner;
  final TicketCache cache;
  final void Function(bool offline)? onOffline;

  Future<T> _read<T>(Future<T> Function() remote, Future<T?> Function() cached, Future<void> Function(T) save) async {
    try {
      final v = await remote();
      onOffline?.call(false);
      await save(v);
      return v;
    } catch (e) {
      if (AppError.from(e) is! OfflineError) rethrow;
      final c = await cached();
      if (c == null) rethrow;
      onOffline?.call(true);
      return c;
    }
  }

  Future<Ticket> _write(Future<Ticket> Function() f) async {
    final t = await f();
    onOffline?.call(false);
    await cache.saveTicket(t);
    return t;
  }

  @override
  Future<List<Ticket>> tickets({String? date, String? status, bool mine = false}) {
    final key = TicketCache.listKey(date: date, status: status, mine: mine);
    return _read(
      () => inner.tickets(date: date, status: status, mine: mine),
      () => cache.list(key),
      (v) => cache.saveList(key, v),
    );
  }

  @override
  Future<Ticket> ticket(String id) => _read(() => inner.ticket(id), () => cache.ticket(id), cache.saveTicket);

  @override
  Future<CookRecipe> recipe(String ticketId, String recipeId, {int? servings}) => _read(
    () => inner.recipe(ticketId, recipeId, servings: servings),
    () => cache.recipe(ticketId, recipeId, servings),
    (v) async {
      if (v.raw != null) await cache.saveRecipe(ticketId, recipeId, servings, v.raw!);
    },
  );

  @override
  Future<List<TicketMessage>> messages(String id) =>
      _read(() => inner.messages(id), () => cache.messages(id), (v) => cache.saveMessages(id, v));

  @override
  Future<Ticket> transition(
    String id,
    TicketStatus to, {
    required int version,
    required String idempotencyKey,
    String? reason,
    String? note,
    String? assigneeCookId,
  }) => _write(
    () => inner.transition(
      id,
      to,
      version: version,
      idempotencyKey: idempotencyKey,
      reason: reason,
      note: note,
      assigneeCookId: assigneeCookId,
    ),
  );

  @override
  Future<Ticket> patchTicket(String id, TicketPatch patch, {required int version}) =>
      _write(() => inner.patchTicket(id, patch, version: version));

  @override
  Future<Ticket> claim(String id) => _write(() => inner.claim(id));

  @override
  Future<Ticket> markItemOut(String id, String ingredientId, {String? idempotencyKey}) =>
      _write(() => inner.markItemOut(id, ingredientId, idempotencyKey: idempotencyKey));

  @override
  Future<Ticket> resolveStockIssue(
    String id,
    LadderAction action, {
    String? substituteIngredientId,
    String? recipeId,
    String? idempotencyKey,
  }) => _write(
    () => inner.resolveStockIssue(
      id,
      action,
      substituteIngredientId: substituteIngredientId,
      recipeId: recipeId,
      idempotencyKey: idempotencyKey,
    ),
  );

  @override
  Future<TicketMessage> sendMessage(String id, String text, {String? idempotencyKey}) =>
      inner.sendMessage(id, text, idempotencyKey: idempotencyKey);
}

/// One cook write made while offline.
@immutable
class QueuedMutation {
  const QueuedMutation({
    required this.key,
    required this.ticketId,
    required this.kind,
    this.to,
    this.reason,
    this.note,
    this.ingredientId,
    this.text,
    this.version,
  });

  static const transition = 'transition';
  static const itemOut = 'item_out';
  static const message = 'message';

  /// Also the Idempotency-Key sent on replay.
  final String key;
  final String ticketId;
  final String kind;
  final TicketStatus? to;
  final String? reason;
  final String? note;
  final String? ingredientId;
  final String? text;

  /// The ticket version the cook saw when acting (If-Match on replay).
  final int? version;

  Json toJson() => {
    'key': key,
    'ticket_id': ticketId,
    'kind': kind,
    'to': to?.wire,
    'reason': reason,
    'note': note,
    'ingredient_id': ingredientId,
    'text': text,
    'version': version,
  };

  factory QueuedMutation.fromJson(Json j) => QueuedMutation(
    key: '${j['key']}',
    ticketId: '${j['ticket_id']}',
    kind: '${j['kind']}',
    to: j['to'] == null ? null : TicketStatus.fromWire(j['to'] as String?),
    reason: j['reason'] as String?,
    note: j['note'] as String?,
    ingredientId: j['ingredient_id'] as String?,
    text: j['text'] as String?,
    version: (j['version'] as num?)?.toInt(),
  );
}

/// What one replay did.
@immutable
class ReplayResult {
  const ReplayResult({this.sent = 0, this.dropped = const [], this.stoppedBy});

  final int sent;

  /// Writes the server rejected for good (409 / 412 / 422, or another 4xx):
  /// removed from the queue; the UI tells the cook.
  final List<(QueuedMutation, AppError)> dropped;

  /// The retryable error that stopped the replay (offline, 5xx, 408, 429,
  /// 401 after refresh): that write and the rest stay queued, in order.
  final AppError? stoppedBy;

  int get done => sent + dropped.length;
}

/// Offline write queue: replayed in order. One replay at a time (joined, not
/// doubled); every read-modify-write of the stored list runs under one lock,
/// so an [add] during a replay is never lost and a replayed write is removed
/// by its key alone.
class MutationQueue {
  MutationQueue(this.store, {this.scope = 'local'});

  final KeyValueStore store;
  final String scope;
  final _replay = SingleFlight<ReplayResult>();
  Future<void> _lock = Future.value();

  String get _key => '$kCachePrefix$scope|queue';

  Future<T> _locked<T>(Future<T> Function() f) {
    final prev = _lock;
    final done = Completer<void>();
    _lock = done.future;
    return prev.then((_) => f()).whenComplete(done.complete);
  }

  Future<List<QueuedMutation>> _read() async {
    final raw = await store.get(_key);
    if (raw == null) return const [];
    try {
      return [for (final m in jsonDecode(raw) as List) QueuedMutation.fromJson((m as Map).cast<String, dynamic>())];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<QueuedMutation> list) =>
      list.isEmpty ? store.remove(_key) : store.set(_key, jsonEncode([for (final m in list) m.toJson()]));

  Future<List<QueuedMutation>> all() => _locked(_read);

  Future<void> add(QueuedMutation m) => _locked(() async {
    final list = await _read();
    if (list.any((x) => x.key == m.key)) return; // same intent queued already
    await _write([...list, m]);
  });

  Future<void> _removeKey(String key) => _locked(() async {
    final list = await _read();
    await _write([
      for (final m in list)
        if (m.key != key) m,
    ]);
  });

  Future<Set<String>> pendingTicketIds() async => {for (final m in await all()) m.ticketId};

  /// Queued thread messages for [ticketId] (shown as "Bheja nahi gaya").
  Future<List<QueuedMutation>> queuedMessages(String ticketId) async => [
    for (final m in await all())
      if (m.kind == QueuedMutation.message && m.ticketId == ticketId) m,
  ];

  bool get replaying => _replay.busy;

  /// Sends queued writes in order; concurrent callers share one run.
  Future<ReplayResult> replay(TicketsRepository repo, {TicketCache? cache}) =>
      _replay.run(() => _replayOnce(repo, cache));

  Future<ReplayResult> _replayOnce(TicketsRepository repo, TicketCache? cache) async {
    var sent = 0;
    final dropped = <(QueuedMutation, AppError)>[];
    final versions = <String, int>{};
    while (true) {
      final list = await all();
      if (list.isEmpty) break;
      final m = list.first;
      try {
        switch (m.kind) {
          case QueuedMutation.transition:
            final t = await repo.transition(
              m.ticketId,
              m.to!,
              version: versions[m.ticketId] ?? m.version ?? 0,
              idempotencyKey: m.key,
              reason: m.reason,
              note: m.note,
            );
            versions[m.ticketId] = t.version;
            await cache?.saveTicket(t);
          case QueuedMutation.itemOut:
            final t = await repo.markItemOut(m.ticketId, m.ingredientId!, idempotencyKey: m.key);
            versions[m.ticketId] = t.version;
            await cache?.saveTicket(t);
          case QueuedMutation.message:
            await repo.sendMessage(m.ticketId, m.text!, idempotencyKey: m.key);
        }
        sent++;
      } catch (e) {
        final err = AppError.from(e);
        if (err is KitchenError) {
          // Rejected for good: server state wins; tell the cook.
          dropped.add((m, err));
        } else {
          // Offline / 5xx / 408 / 429 / 401 after refresh / unknown: keep it
          // (and everything after it) for the next replay.
          return ReplayResult(sent: sent, dropped: dropped, stoppedBy: err);
        }
      }
      await _removeKey(m.key);
    }
    return ReplayResult(sent: sent, dropped: dropped);
  }
}
