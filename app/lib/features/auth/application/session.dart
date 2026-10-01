import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/router/startup_gate.dart' show onboardingProvider;
import '../../../data/data_source.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';

/// POST /v1/households `{name, timezone}` (first login without a household).
class ApiHouseholdSetup with ApiGuard {
  ApiHouseholdSetup(this.dio);

  final Dio dio;

  Future<void> create(String name, {String timezone = 'Asia/Kolkata'}) => guard(() async {
    await dio.post<Object?>('/v1/households', data: {'name': name, 'timezone': timezone});
  });
}

final householdSetupProvider = Provider<ApiHouseholdSetup>((ref) => ApiHouseholdSetup(ref.watch(dioProvider)));

/// The signed-in caller's `/v1/me`, cached on the device (so a cold start
/// knows the household / cook role before the network answers). Null until
/// read. Demo sandbox: unused.
final sessionProvider = NotifierProvider<SessionController, Me?>(SessionController.new);

class SessionController extends Notifier<Me?> {
  static const cacheKey = 'session.me';

  @override
  Me? build() => null;

  /// Reads the cached /me (cold start).
  Future<Me?> loadCached() async {
    try {
      final raw = await ref.read(keyValueStoreProvider).get(cacheKey);
      if (raw == null) return null;
      final me = Me.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      if (ref.mounted && state == null) state = me;
      return me;
    } catch (_) {
      return null;
    }
  }

  /// Stores a fetched /me (cache + state).
  Future<void> remember(Me me) async {
    if (me.raw != null) {
      try {
        await ref.read(keyValueStoreProvider).set(cacheKey, jsonEncode(me.raw));
      } catch (_) {}
    }
    if (ref.mounted) state = me;
  }

  /// GET /v1/me (through [meProvider]) and cache it. Errors surface.
  Future<Me> refreshMe() => ref.refresh(meProvider.future);

  /// After OTP verify: where to go next (no household → create one; hired
  /// cook → cook mode; else Home). Marks the first run done.
  Future<String> afterSignIn() async {
    final me = await refreshMe();
    await ref.read(onboardingProvider.notifier).markDone();
    return routeFor(me);
  }

  static String routeFor(Me me) {
    if (!me.hasHousehold) return Routes.createHousehold;
    if (me.cookOnly) return Routes.cook;
    return Routes.home;
  }

  Future<void> createHousehold(String name) async {
    await ref.read(householdSetupProvider).create(name.trim());
    await refreshMe();
  }

  /// Logout / account deletion.
  Future<void> clear() async {
    try {
      await ref.read(keyValueStoreProvider).remove(cacheKey);
    } catch (_) {}
    if (ref.mounted) state = null;
  }
}
