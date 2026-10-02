import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/data_source.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/kitchen/application/kitchen_providers.dart';
import '../router/router.dart';
import '../router/routes.dart';
import 'push_messaging.dart';

/// Registers this install's FCM token with the API and opens what a tapped
/// notification points at.
///
/// - Signed in (API mode): permission → token → `POST /v1/devices`
///   `{platform: android, push_token}`; again on every token refresh. The
///   returned device id is kept on the device.
/// - Logout: `DELETE /v1/devices/{id}` (while the session is still valid),
///   then the FCM token is deleted so the next login gets a fresh one.
/// - Tap: `ticket_id` → the ticket (cook mode for a hired cook), anything
///   else → the inbox (K1 for a hired cook). While the startup gate is still
///   deciding, the route waits until Home / K1 is shown.
class PushRegistrar {
  PushRegistrar(this.ref);

  final Ref ref;

  static const deviceKey = 'push.device_id';
  static const tokenKey = 'push.token';

  final List<StreamSubscription<Object?>> _subs = [];
  bool _started = false;
  String? _pendingRoute;
  VoidCallback? _routerListener;

  PushMessaging? get _push => ref.read(pushMessagingProvider);

  /// Idempotent: called whenever the app is signed in in API mode.
  Future<void> start() async {
    final push = _push;
    if (_started || push == null) return;
    _started = true;
    if (!await push.start()) {
      _started = false;
      return;
    }
    _subs
      ..add(push.onTokenRefresh.listen((t) => unawaited(_register(t))))
      ..add(push.onOpened.listen(open))
      ..add(push.onForeground.listen((_) => ref.read(kitchenRevisionProvider.notifier).bump()));
    final token = await push.token();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    if (!ref.read(authControllerProvider).signedIn) return;
    try {
      final r = await ref
          .read(dioProvider)
          .post<Map<String, dynamic>>('/v1/devices', data: {'platform': 'android', 'push_token': token});
      final id = r.data?['id'];
      final store = ref.read(keyValueStoreProvider);
      if (id != null) await store.set(deviceKey, '$id');
      await store.set(tokenKey, token);
    } catch (e) {
      debugPrint('push: device registration failed ($e)');
    }
  }

  /// Before logout: drop this device server-side and locally.
  Future<void> unregister() async {
    final store = ref.read(keyValueStoreProvider);
    final id = await store.get(deviceKey);
    if (id != null) {
      try {
        await ref.read(dioProvider).delete<void>('/v1/devices/$id').timeout(const Duration(seconds: 3));
      } catch (_) {}
      await store.remove(deviceKey);
      await store.remove(tokenKey);
    }
    final push = _push;
    if (_started && push != null) {
      try {
        await push.deleteToken();
      } catch (_) {}
    }
    await stop();
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _started = false;
  }

  /// Route for a tapped notification's data.
  String routeFor(Map<String, String> data) {
    final cookOnly = ref.read(meProvider).value?.cookOnly ?? false;
    final ticket = data['ticket_id'];
    if (ticket != null && ticket.isNotEmpty) return cookOnly ? Routes.cookTicket(ticket) : Routes.ticket(ticket);
    return cookOnly ? Routes.cook : Routes.inbox;
  }

  void open(Map<String, String> data) {
    final route = routeFor(data);
    final router = ref.read(routerProvider);
    if (_settled(router)) {
      router.push(route);
      return;
    }
    _pendingRoute = route;
    if (_routerListener != null) return;
    void listener() {
      final pending = _pendingRoute;
      if (pending == null || !_settled(router)) return;
      _pendingRoute = null;
      router.routerDelegate.removeListener(_routerListener!);
      _routerListener = null;
      router.push(pending);
    }

    _routerListener = listener;
    router.routerDelegate.addListener(listener);
  }

  static bool _settled(GoRouter router) {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    return path == Routes.home || path == Routes.cook || path == Routes.inbox;
  }
}

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  final r = PushRegistrar(ref);
  ref.onDispose(r.stop);
  return r;
});

/// Watched by the app: starts push registration once signed in on the API.
final pushBootstrapProvider = Provider<void>((ref) {
  final api = ref.watch(dataSourceProvider) == DataSource.api;
  final signedIn = ref.watch(authControllerProvider.select((s) => s.signedIn));
  if (api && signedIn) Future.microtask(() => ref.read(pushRegistrarProvider).start());
});
