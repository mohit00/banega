import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ticket_cache.dart';
import 'kitchen_providers.dart';

/// Fires when the device's network may have come back (connectivity_plus).
/// Tests override it.
final connectivityChangesProvider = Provider<Stream<void>>((ref) {
  try {
    return Connectivity().onConnectivityChanged
        .where((r) => r.any((c) => c != ConnectivityResult.none))
        .map((_) {})
        .handleError((Object _) {});
  } catch (_) {
    return const Stream.empty();
  }
});

/// Writes the last replay dropped (the server rejected them for good); cook
/// screens show a toast when it grows.
@immutable
class SyncDrops {
  const SyncDrops({this.count = 0});
  final int count;
}

final syncDropsProvider = NotifierProvider<SyncDropsController, SyncDrops>(SyncDropsController.new);

class SyncDropsController extends Notifier<SyncDrops> {
  @override
  SyncDrops build() => const SyncDrops();

  void add(int n) {
    if (n > 0) state = SyncDrops(count: state.count + n);
  }
}

/// The one owner of offline-queue replay: runs it (single-flight) when the
/// network comes back (connectivity_plus), when the app resumes, and when a
/// cook list loads. Also evicts expired cache entries on start.
final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(ref);
  ref.onDispose(s.dispose);
  return s;
});

class SyncService {
  SyncService(this.ref);

  final Ref ref;
  StreamSubscription<void>? _net;
  AppLifecycleListener? _life;
  bool _started = false;

  /// Starts listening (idempotent). Only meaningful when cook mode talks to
  /// the backend.
  void start() {
    if (_started) return;
    _started = true;
    try {
      _net = ref.read(connectivityChangesProvider).listen((_) => replay(), onError: (Object _) {});
    } catch (_) {}
    try {
      _life = AppLifecycleListener(onResume: replay);
    } catch (_) {}
    unawaited(ref.read(ticketCacheProvider).evictExpired().catchError((Object _) => 0));
  }

  /// Replays the queue once (joining a replay already running). Dropped
  /// writes are reported through [syncDropsProvider]; the ticket views
  /// refresh when anything changed.
  Future<ReplayResult> replay() async {
    if (!ref.read(cookUsesApiProvider)) return const ReplayResult();
    final queue = ref.read(mutationQueueProvider);
    final r = await queue.replay(ref.read(cookTicketsRepositoryProvider), cache: ref.read(ticketCacheProvider));
    if (r.dropped.isNotEmpty) ref.read(syncDropsProvider.notifier).add(r.dropped.length);
    if (r.done > 0) ref.read(kitchenRevisionProvider.notifier).bump();
    return r;
  }

  void dispose() {
    _net?.cancel();
    _life?.dispose();
  }
}
