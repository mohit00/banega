import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config.dart';
import '../../../data/data_source.dart';
import '../../auth/application/session.dart';
import '../../../data/repositories.dart' show wireDate, SlotWire;
import '../../home/home_providers.dart';
import '../../members/application/members_controller.dart';
import '../data/demo_kitchen.dart';
import '../data/kitchen_api.dart';
import '../data/kitchen_repositories.dart';
import '../data/ticket_cache.dart';
import 'sync_service.dart';
import '../domain/kitchen_models.dart';

// ------------------------------------------------------------------ plumbing

/// A fresh random key (thread message drafts get one and keep it until the
/// message is sent).
final idempotencyKeyProvider = Provider<String Function()>(
  (ref) =>
      () => const Uuid().v4(),
);

/// Idempotency-Key per **intent**: derived from what the write means (kind,
/// resource id, the version it was based on, the target), scoped to the
/// signed-in household. A retry of the same intent (double tap, replay after
/// a timeout, the offline queue) reuses the key until the server accepts or
/// definitively rejects it; a new version is a new intent.
final intentKeyProvider = Provider<String Function(List<Object?> parts)>((ref) {
  final scope = ref.watch(cacheScopeProvider);
  return (parts) => const Uuid().v5(Namespace.url.value, 'banega:$scope:${parts.join('|')}');
});

/// Ticket ids with a write in flight: a second tap is ignored and the
/// buttons for that ticket are disabled until the first answer.
final ticketsInFlightProvider = NotifierProvider<InFlight, Set<String>>(InFlight.new);

class InFlight extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool begin(String id) {
    if (state.contains(id)) return false;
    state = {...state, id};
    return true;
  }

  void end(String id) {
    if (!state.contains(id)) return;
    state = {
      for (final x in state)
        if (x != id) x,
    };
  }
}

/// A write for this resource is already on its way.
class AlreadyInFlight implements Exception {
  const AlreadyInFlight(this.id);
  final String id;
}

/// Opens the OS share sheet (WhatsApp path, F-2-01). Overridden in tests.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) =>
      (text) async => SharePlus.instance.share(ShareParams(text: text)),
);

/// Bumped after every ticket / menu write so the ticket views refetch.
final kitchenRevisionProvider = NotifierProvider<KitchenRevision, int>(KitchenRevision.new);

class KitchenRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// The in-memory kitchen behind demo mode (kept for the whole session).
final demoKitchenProvider = Provider<DemoKitchen>(
  (ref) => DemoKitchen(members: () => ref.read(membersProvider), now: ref.read(clockProvider)),
);

// ------------------------------------------------------------------ repositories

final menusRepositoryProvider = Provider<MenusRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider);
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiMenusRepository(ref.watch(dioProvider));
});

final ticketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider);
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiTicketsRepository(ref.watch(dioProvider));
});

final cooksRepositoryProvider = Provider<CooksRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider);
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiCooksRepository(ref.watch(dioProvider));
});

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  final demo = ref.watch(demoKitchenProvider);
  if (ref.watch(dataSourceProvider) == DataSource.demo) return demo;
  return ApiInboxRepository(ref.watch(dioProvider));
});

// ------------------------------------------------------------------ cook mode offline

final keyValueStoreProvider = Provider<KeyValueStore>((ref) => SharedPrefsStore());

/// Cache / queue scope: `user|household` for a signed-in API session, so
/// one account never reads another's cached tickets or replays its writes.
final cacheScopeProvider = Provider<String>((ref) {
  if (ref.watch(dataSourceProvider) != DataSource.api) return 'local';
  final me = ref.watch(sessionProvider);
  if (me == null || me.userId == null) return 'local';
  return '${me.userId}|${me.householdId ?? ''}';
});

final ticketCacheProvider = Provider<TicketCache>(
  (ref) => TicketCache(
    ref.watch(keyValueStoreProvider),
    scope: ref.watch(cacheScopeProvider),
    now: ref.watch(clockProvider),
  ),
);

final mutationQueueProvider = Provider<MutationQueue>(
  (ref) => MutationQueue(ref.watch(keyValueStoreProvider), scope: ref.watch(cacheScopeProvider)),
);

/// True while cook mode is answering from the offline cache.
final cookOfflineProvider = NotifierProvider<CookOffline, bool>(CookOffline.new);

class CookOffline extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) {
    if (state != v) state = v;
  }
}

/// Whether cook mode talks to the backend (and so caches and queues);
/// offline it reads its cache.
final cookUsesApiProvider = Provider<bool>((ref) => ref.watch(dataSourceProvider) == DataSource.api);

/// Cook mode's tickets: the API behind the offline cache, or the demo kitchen.
final cookTicketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  if (!ref.watch(cookUsesApiProvider)) return ref.watch(demoKitchenProvider).asCook;
  final offline = ref.read(cookOfflineProvider.notifier);
  return CachingTicketsRepository(
    inner: ApiTicketsRepository(ref.watch(dioProvider)),
    cache: ref.watch(ticketCacheProvider),
    onOffline: offline.set,
  );
});

// ------------------------------------------------------------------ roles

/// Demo stand-in for the caller's cook role (Settings stub): null → family
/// only, `c1` → Ramesh ji (hired), `c2` → Mummy (family cook).
final demoCookRoleProvider = NotifierProvider<DemoCookRole, String?>(DemoCookRole.new);

class DemoCookRole extends Notifier<String?> {
  @override
  String? build() => ref.read(demoKitchenProvider).meCookId;

  void set(String? cookId) {
    ref.read(demoKitchenProvider).meCookId = cookId;
    state = cookId;
  }
}

/// GET /v1/me: modes, cook role, household. API mode caches it on the device
/// (the startup gate reads the cache on a cold start); offline answers from
/// that cache, other failures surface (a hired cook is never shown the
/// family side because /me failed).
final meProvider = FutureProvider<Me>((ref) async {
  ref.watch(demoCookRoleProvider);
  final repo = ref.watch(cooksRepositoryProvider);
  if (ref.watch(dataSourceProvider) != DataSource.api) return repo.me();
  try {
    final me = await repo.me();
    await ref.read(sessionProvider.notifier).remember(me);
    return me;
  } on OfflineError {
    final cached = ref.read(sessionProvider) ?? await ref.read(sessionProvider.notifier).loadCached();
    if (cached != null) return cached;
    rethrow;
  }
}, retry: (_, _) => null);

/// GET /v1/cooks.
final cooksProvider = FutureProvider<List<Cook>>((ref) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(cooksRepositoryProvider).cooks();
}, retry: (_, _) => null);

// ------------------------------------------------------------------ family views

/// Today's ticket for the slot Home shows (the open one, else the latest).
final homeTicketProvider = FutureProvider<Ticket?>((ref) async {
  ref.watch(kitchenRevisionProvider);
  final slot = ref.watch(slotProvider).wire;
  final date = wireDate(ref.watch(planDateProvider));
  final list = await ref.watch(ticketsRepositoryProvider).tickets(date: date);
  final mine = [
    for (final t in list)
      if (t.slot == slot) t,
  ];
  if (mine.isEmpty) return null;
  return mine.where((t) => t.status.isOpen).lastOrNull ?? mine.last;
}, retry: (_, _) => null);

final ticketProvider = FutureProvider.autoDispose.family<Ticket, String>((ref, id) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(ticketsRepositoryProvider).ticket(id);
}, retry: (_, _) => null);

/// K6 thread, family or cook side.
final threadProvider = FutureProvider.autoDispose.family<List<TicketMessage>, (String, bool)>((ref, key) {
  ref.watch(kitchenRevisionProvider);
  final repo = key.$2 ? ref.watch(cookTicketsRepositoryProvider) : ref.watch(ticketsRepositoryProvider);
  return repo.messages(key.$1);
}, retry: (_, _) => null);

final inboxProvider = FutureProvider<List<InboxItem>>((ref) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(inboxRepositoryProvider).inbox();
}, retry: (_, _) => null);

final unreadInboxProvider = Provider<int>((ref) => ref.watch(inboxProvider).value?.where((i) => i.unread).length ?? 0);

// ------------------------------------------------------------------ cook views

/// K1: the caller's tickets for [date] (`YYYY-MM-DD`), by due time. Replays
/// queued offline writes first so server state reflects them.
final cookTicketsProvider = FutureProvider.autoDispose.family<List<Ticket>, String>((ref, date) async {
  ref.watch(kitchenRevisionProvider);
  final repo = ref.watch(cookTicketsRepositoryProvider);
  if (ref.watch(cookUsesApiProvider)) {
    final sync = ref.read(syncServiceProvider)..start();
    await sync.replay();
  }
  final list = await repo.tickets(date: date, mine: true);
  return [...list]..sort((a, b) => (a.dueAt ?? DateTime(0)).compareTo(b.dueAt ?? DateTime(0)));
}, retry: (_, _) => null);

final cookTicketProvider = FutureProvider.autoDispose.family<Ticket, String>((ref, id) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(cookTicketsRepositoryProvider).ticket(id);
}, retry: (_, _) => null);

/// K5: a ticket's recipe scaled to (ticket, recipe, servings).
final cookRecipeProvider = FutureProvider.autoDispose.family<CookRecipe, (String, String, int)>(
  (ref, key) => ref.watch(cookTicketsRepositoryProvider).recipe(key.$1, key.$2, servings: key.$3),
  retry: (_, _) => null,
);

/// Thread messages still in the offline queue for a ticket (cook side).
final queuedMessagesProvider = FutureProvider.autoDispose.family<List<QueuedMutation>, String>((ref, ticketId) async {
  ref.watch(kitchenRevisionProvider);
  if (!ref.watch(cookUsesApiProvider)) return const [];
  return ref.read(mutationQueueProvider).queuedMessages(ticketId);
}, retry: (_, _) => null);

/// Tickets with writes waiting in the offline queue ("Bheja nahi gaya").
final pendingTicketIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(kitchenRevisionProvider);
  if (!ref.watch(cookUsesApiProvider)) return const {};
  return ref.read(mutationQueueProvider).pendingTicketIds();
}, retry: (_, _) => null);

/// The next state a K1/K2 primary button moves to, and the optional
/// secondary one (cooking → "Taiyaar").
(TicketStatus?, TicketStatus?) cookNextSteps(TicketStatus s) => switch (s) {
  TicketStatus.fresh => (TicketStatus.accepted, null),
  TicketStatus.accepted => (TicketStatus.cooking, null),
  TicketStatus.cooking => (TicketStatus.completed, TicketStatus.ready),
  TicketStatus.ready => (TicketStatus.completed, null),
  _ => (null, null),
};

// ------------------------------------------------------------------ writes

/// Ticket writes for one side of the app. Cook mode ([cook] true) queues
/// writes that fail for lack of network and shows them optimistically.
class TicketActions {
  TicketActions(this.ref, {required this.cook});

  final Ref ref;
  final bool cook;

  TicketsRepository get _repo => cook ? ref.read(cookTicketsRepositoryProvider) : ref.read(ticketsRepositoryProvider);

  String _intent(List<Object?> parts) => ref.read(intentKeyProvider)(parts);

  /// Runs [f] unless a write for [id] is already in flight (then throws
  /// [AlreadyInFlight], which the screens ignore).
  Future<T> _once<T>(String id, Future<T> Function() f) async {
    final flight = ref.read(ticketsInFlightProvider.notifier);
    if (!flight.begin(id)) throw AlreadyInFlight(id);
    try {
      return await f();
    } finally {
      if (ref.mounted) flight.end(id);
    }
  }

  void _changed() => ref.read(kitchenRevisionProvider.notifier).bump();

  bool get _queues => cook && ref.read(cookUsesApiProvider);

  /// Worth queueing for a later replay (offline, 5xx, 408, 429).
  bool _queueable(Object e) => _queues && AppError.from(e).retryable;

  Future<Ticket> transition(Ticket t, TicketStatus to, {String? reason, String? note}) =>
      _once(t.id, () => _transition(t, to, reason: reason, note: note));

  Future<Ticket> _transition(Ticket t, TicketStatus to, {String? reason, String? note}) async {
    final key = _intent(['transition', t.id, t.version, to.wire]);
    try {
      final next = await _repo.transition(
        t.id,
        to,
        version: t.version,
        idempotencyKey: key,
        reason: reason,
        note: note,
      );
      _changed();
      return next;
    } catch (e) {
      if (e is KitchenError) _changed(); // refresh to the server's state
      if (!_queueable(e)) rethrow;
      await ref
          .read(mutationQueueProvider)
          .add(
            QueuedMutation(
              key: key,
              ticketId: t.id,
              kind: QueuedMutation.transition,
              to: to,
              reason: reason,
              note: note,
              version: t.version,
            ),
          );
      final local = t.copyWith(status: to);
      await ref.read(ticketCacheProvider).saveTicket(local);
      _changed();
      return local;
    }
  }

  Future<Ticket> markItemOut(Ticket t, RequiredItem item) => _once(t.id, () => _markItemOut(t, item));

  Future<Ticket> _markItemOut(Ticket t, RequiredItem item) async {
    final key = _intent(['item_out', t.id, t.version, item.ingredientId]);
    try {
      final next = await _repo.markItemOut(t.id, item.ingredientId, idempotencyKey: key);
      _changed();
      return next;
    } catch (e) {
      if (!_queueable(e)) rethrow;
      await ref
          .read(mutationQueueProvider)
          .add(QueuedMutation(key: key, ticketId: t.id, kind: QueuedMutation.itemOut, ingredientId: item.ingredientId));
      final local = t.copyWith(
        stockIssueOpen: true,
        requiredItems: [
          for (final i in t.requiredItems) i.ingredientId == item.ingredientId ? i.withStatus(ItemStatus.out) : i,
        ],
      );
      await ref.read(ticketCacheProvider).saveTicket(local);
      _changed();
      return local;
    }
  }

  /// Out-of-stock ladder: skip / swap / change dish. Online only (the
  /// answer decides what the cook sees next).
  Future<Ticket> resolve(Ticket t, LadderAction action, {String? substituteIngredientId, String? recipeId}) =>
      _once(t.id, () => _resolve(t, action, substituteIngredientId: substituteIngredientId, recipeId: recipeId));

  Future<Ticket> _resolve(Ticket t, LadderAction action, {String? substituteIngredientId, String? recipeId}) async {
    try {
      final next = await _repo.resolveStockIssue(
        t.id,
        action,
        substituteIngredientId: substituteIngredientId,
        recipeId: recipeId,
        idempotencyKey: _intent(['resolve', t.id, t.version, action.wire, substituteIngredientId, recipeId]),
      );
      _changed();
      return next;
    } on KitchenError {
      _changed();
      rethrow;
    }
  }

  /// Returns false when the message was queued instead of sent. [key] is the
  /// draft's Idempotency-Key (kept by the screen until the message is sent).
  Future<bool> sendMessage(String ticketId, String text, {String? key}) =>
      _once('msg:$ticketId', () => _sendMessage(ticketId, text, key ?? ref.read(idempotencyKeyProvider)()));

  Future<bool> _sendMessage(String ticketId, String text, String key) async {
    try {
      await _repo.sendMessage(ticketId, text, idempotencyKey: key);
      _changed();
      return true;
    } catch (e) {
      if (!_queueable(e)) rethrow;
      await ref
          .read(mutationQueueProvider)
          .add(QueuedMutation(key: key, ticketId: ticketId, kind: QueuedMutation.message, text: text));
      _changed();
      return false;
    }
  }

  Future<Ticket> patch(Ticket t, TicketPatch p) => _once(t.id, () => _patch(t, p));

  Future<Ticket> _patch(Ticket t, TicketPatch p) async {
    try {
      final next = await _repo.patchTicket(t.id, p, version: t.version);
      _changed();
      return next;
    } on KitchenError {
      _changed();
      rethrow;
    }
  }
}

final familyTicketActionsProvider = Provider<TicketActions>((ref) => TicketActions(ref, cook: false));
final cookTicketActionsProvider = Provider<TicketActions>((ref) => TicketActions(ref, cook: true));

/// Cook mode's language: Hindi first (app_hi.arb); a family cook (or anyone
/// reading along) can switch to Hinglish or English from the cook header.
/// Stored on the device.
final cookLocaleProvider = NotifierProvider<CookLocale, Locale>(CookLocale.new);

class CookLocale extends Notifier<Locale> {
  static const storeKey = 'cook.language';
  static const hindi = Locale('hi');
  static const hinglish = Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn');
  static const english = Locale('en');
  static const cycle = [hindi, hinglish, english];
  bool _chosen = false;

  @override
  Locale build() {
    Future.microtask(_load);
    return hindi;
  }

  static String _key(Locale l) => l.scriptCode == null ? l.languageCode : '${l.languageCode}_${l.scriptCode}';

  Future<void> _load() async {
    try {
      final v = await ref.read(keyValueStoreProvider).get(storeKey);
      final found = cycle.where((l) => _key(l) == v).firstOrNull;
      if (found != null && ref.mounted && !_chosen) state = found;
    } catch (_) {}
  }

  Future<void> set(Locale l) async {
    _chosen = true;
    state = l;
    try {
      await ref.read(keyValueStoreProvider).set(storeKey, _key(l));
    } catch (_) {}
  }

  /// Hindi → Hinglish → English → Hindi.
  Future<void> next() => set(cycle[(cycle.indexOf(state) + 1) % cycle.length]);
}
