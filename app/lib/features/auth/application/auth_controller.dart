import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/app_error.dart';
import '../../../core/network/network_status.dart';
import '../../../core/session/local_data.dart';
import '../../account/application/locale_controller.dart';
import '../../kitchen/application/kitchen_providers.dart' show keyValueStoreProvider;
import '../data/auth_repository.dart';
import '../data/token_store.dart';
import '../domain/auth_models.dart';

enum AuthStatus {
  /// Tokens not read from secure storage yet.
  unknown,
  signedOut,
  signedIn,
}

@immutable
class AuthState {
  const AuthState(this.status, [this.tokens]);

  final AuthStatus status;
  final AuthTokens? tokens;

  bool get signedIn => status == AuthStatus.signedIn && tokens != null;

  @override
  bool operator ==(Object other) => other is AuthState && other.status == status && other.tokens == tokens;

  @override
  int get hashCode => Object.hash(status, tokens);
}

/// Session tokens (Keystore / Keychain). Tests override with
/// [MemoryTokenStore].
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// `Accept-Language` value for the app's language.
final acceptLanguageProvider = Provider<String Function()>(
  (ref) =>
      () => ref.read(localeProvider).toLanguageTag(),
);

/// Stable per-install id sent as `X-Device-Id` (OTP limits are per device).
final installIdProvider = Provider<InstallId>((ref) {
  final store = ref.watch(keyValueStoreProvider);
  return InstallId(store.get, store.set);
});

/// Dio for the auth endpoints and replays: headers + reachability, no auth
/// interceptor.
final plainDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final status = ref.read(networkOfflineProvider.notifier);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl ?? '',
      connectTimeout: config.connectTimeout,
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors
    ..add(RequestHeadersInterceptor(language: ref.read(acceptLanguageProvider)))
    ..add(DeviceIdInterceptor(ref.read(installIdProvider).call))
    ..add(NetworkStatusInterceptor(status.set));
  final adapter = ref.watch(httpClientAdapterProvider);
  if (adapter != null) dio.httpClientAdapter = adapter;
  ref.onDispose(dio.close);
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) => ApiAuthRepository(ref.watch(plainDioProvider)));

/// The login session: OTP request / verify, single-flight refresh, logout.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  final _refresh = SingleFlight<String?>();

  @override
  AuthState build() {
    Future.microtask(_load);
    return const AuthState(AuthStatus.unknown);
  }

  TokenStore get _store => ref.read(tokenStoreProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _load() async {
    AuthTokens? t;
    try {
      t = await _store.read();
    } catch (_) {
      t = null; // no secure storage (tests / first run)
    }
    if (!ref.mounted || state.status != AuthStatus.unknown) return;
    state = t == null ? const AuthState(AuthStatus.signedOut) : AuthState(AuthStatus.signedIn, t);
  }

  /// Waits for the stored session to be read.
  Future<AuthState> ready() async {
    if (state.status == AuthStatus.unknown) await _load();
    return state;
  }

  String? get accessToken => state.tokens?.accessToken;

  Future<OtpChallenge> requestOtp(String phone) => _repo.requestOtp(phone);

  Future<AuthTokens> verify(String phone, String code) async {
    final t = await _repo.verify(phone, code);
    await _save(t);
    return t;
  }

  Future<void> _save(AuthTokens t) async {
    try {
      await _store.write(t);
    } catch (_) {}
    if (ref.mounted) state = AuthState(AuthStatus.signedIn, t);
  }

  /// Single-flight refresh. [failedToken] is the access token a 401 came
  /// back for: when another caller already refreshed past it, the current
  /// token is returned without a new POST. Null → session over (logged out).
  /// Throws [OfflineError] / [ServerError] when the refresh could not be
  /// attempted (the session is kept).
  Future<String?> refreshFor(String? failedToken) {
    final cur = state.tokens;
    if (cur == null) return Future.value(null);
    if (failedToken != null && cur.accessToken != failedToken) return Future.value(cur.accessToken);
    return _refresh.run(() async {
      try {
        final t = await _repo.refresh(cur.refreshToken);
        await _save(t);
        return t.accessToken;
      } on AppError catch (e) {
        if (e.retryable) rethrow;
        await _signOutLocally();
        return null;
      }
    });
  }

  /// POST /v1/auth/logout (best effort), then forget the session and purge
  /// local caches.
  Future<void> logout() async {
    final t = state.tokens;
    if (t != null) {
      try {
        await _repo.logout(t.accessToken);
      } catch (_) {}
    }
    await _signOutLocally();
  }

  /// DELETE /v1/me succeeded: the server already ended the session; forget
  /// it here and purge the device copy (sandbox: purge only).
  Future<void> signOutAfterDeletion() => _signOutLocally();

  Future<void> _signOutLocally() async {
    try {
      await _store.clear();
    } catch (_) {}
    try {
      await ref.read(purgeLocalDataProvider)();
    } catch (_) {}
    if (ref.mounted) state = const AuthState(AuthStatus.signedOut);
  }
}
