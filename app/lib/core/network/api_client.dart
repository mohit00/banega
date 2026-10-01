import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../data/models.dart' show Json;
import 'app_error.dart';

/// Shared plumbing for every `Api*Repository`: one [guard] that turns any
/// failure into an [AppError] (via [AppError.from], the single mapping), plus
/// JSON helpers.
mixin ApiGuard {
  /// Runs [f]; transport / HTTP failures and malformed payloads surface as
  /// an [AppError]. Domain exceptions thrown by [f] itself (e.g. a
  /// `RecipeNotFound` built from a 404) pass through.
  Future<T> guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw AppError.from(e);
    } on TypeError catch (e) {
      throw UnknownError(cause: e);
    } on FormatException catch (e) {
      throw UnknownError(cause: e);
    }
  }

  Json json(Object? data) => (data as Map).cast<String, dynamic>();

  /// A bare list or a paginated `{items: [...]}` envelope.
  List<Json> jsonList(Object? data) {
    final l = data is List ? data : (data is Map ? data['items'] as List? ?? const [] : const []);
    return [for (final x in l) (x as Map).cast<String, dynamic>()];
  }

  /// If-Match / Idempotency-Key headers.
  Options headers({int? version, String? idempotencyKey}) =>
      Options(headers: {'If-Match': ?version?.toString(), 'Idempotency-Key': ?idempotencyKey});

  String enc(String s) => Uri.encodeComponent(s);
}

/// Adds `Accept-Language` (the app's language tag) and a fresh
/// `X-Request-Id` to every request.
class RequestHeadersInterceptor extends Interceptor {
  RequestHeadersInterceptor({required this.language, String Function()? requestId})
    : _requestId = requestId ?? (() => const Uuid().v4());

  final String Function() language;
  final String Function() _requestId;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Accept-Language'] = language();
    options.headers.putIfAbsent('X-Request-Id', _requestId);
    handler.next(options);
  }
}

/// Adds `X-Device-Id` (a stable per-install id) so the server scopes OTP
/// rate limits and wrong-code locks to this device instead of the IP.
class DeviceIdInterceptor extends Interceptor {
  DeviceIdInterceptor(this.deviceId);

  final Future<String?> Function() deviceId;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    Future<String?> lookup;
    try {
      // Re-type as Future<String?> so the null timeout value is accepted even
      // when the source is a Future<String>.
      lookup = deviceId().then<String?>((v) => v);
    } catch (_) {
      lookup = Future<String?>.value();
    }
    // No id is fine: the server falls back to the client IP.
    lookup
        .timeout(const Duration(seconds: 2), onTimeout: () => null)
        .then<String?>((id) => id, onError: (Object _) => null)
        .then((id) {
          if (id != null && id.isNotEmpty) options.headers['X-Device-Id'] = id;
          handler.next(options);
        });
  }
}

/// Loads (or creates once) the per-install id, cached for the process.
class InstallId {
  InstallId(this._get, this._set);

  final Future<String?> Function(String key) _get;
  final Future<void> Function(String key, String value) _set;
  Future<String?>? _cached;

  static const key = 'app.install_id';

  Future<String?> call() => _cached ??= _load();

  Future<String?> _load() async {
    final existing = await _get(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _set(key, id);
    return id;
  }
}

/// Bearer auth with single-flight refresh.
///
/// - Every request (except `/v1/auth/*`) carries `Authorization: Bearer`.
/// - A 401 asks [refresh] for a new access token (the caller makes it
///   single-flight: concurrent 401s share one POST /v1/auth/refresh), then
///   replays the request once with it.
/// - When [refresh] yields null (refresh token rejected) the session is over:
///   the request fails with [UnauthorizedError] and the caller logs out.
///
/// Queued (a [QueuedInterceptorsWrapper]) so errors are handled one at a
/// time: a burst of 401s waits for the one refresh.
class AuthInterceptor extends QueuedInterceptorsWrapper {
  AuthInterceptor({required this.dio, required this.accessToken, required this.refresh});

  /// The client to replay through: one **without** this interceptor (a
  /// replay failing inside the queued error handler would otherwise wait on
  /// itself).
  final Dio dio;
  final String? Function() accessToken;

  /// Given the token that failed, returns a fresh access token or null.
  final Future<String?> Function(String? failedToken) refresh;

  static const _retried = 'banega.auth.retried';

  static bool _isAuthPath(String path) => path.contains('/v1/auth/');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = accessToken();
    if (token != null && token.isNotEmpty && !_isAuthPath(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (err.response?.statusCode != 401 || _isAuthPath(req.path) || req.extra[_retried] == true) {
      if (err.response?.statusCode == 401 && req.extra[_retried] == true) {
        return handler.reject(_unauthorized(err));
      }
      return handler.next(err);
    }
    final failed = '${req.headers['Authorization'] ?? ''}'.replaceFirst('Bearer ', '');
    String? fresh;
    try {
      fresh = await refresh(failed.isEmpty ? null : failed);
    } catch (e) {
      // Offline during refresh: keep the session, surface the transport error.
      return handler.reject(DioException(requestOptions: req, error: AppError.from(e), type: DioExceptionType.unknown));
    }
    if (fresh == null) return handler.reject(_unauthorized(err));
    try {
      req.headers['Authorization'] = 'Bearer $fresh';
      req.extra[_retried] = true;
      final res = await dio.fetch<Object?>(req);
      handler.resolve(res);
    } on DioException catch (e) {
      handler.reject(e.response?.statusCode == 401 ? _unauthorized(e) : e);
    }
  }

  DioException _unauthorized(DioException err) => DioException(
    requestOptions: err.requestOptions,
    response: err.response,
    type: DioExceptionType.badResponse,
    error: const UnauthorizedError(),
  );
}

/// Joins concurrent callers onto one in-flight [run] (single-flight).
class SingleFlight<T> {
  Future<T>? _inFlight;

  Future<T> run(Future<T> Function() f) {
    final cur = _inFlight;
    if (cur != null) return cur;
    final next = f().whenComplete(() => _inFlight = null);
    _inFlight = next;
    return next;
  }

  bool get busy => _inFlight != null;
}
