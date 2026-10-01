import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../../features/kitchen/domain/kitchen_models.dart' show TicketStatus;
import 'network_status.dart';

/// Every failure a repository can surface. Mapped in ONE place
/// ([AppError.from]) from Dio / transport errors and the backend's envelope
/// `{code, message_en, message_hi, details: {allowed, current_version}}`
/// (FastAPI may wrap it in `detail`).
///
/// - [UnauthorizedError]: 401 that survived the refresh (session over).
/// - [OfflineError]: the backend could not be reached (no network, DNS,
///   refused, timeouts).
/// - [KitchenError]: a 4xx answer the UI reacts to; [ConflictError] (409 /
///   412, with `allowed` and `current_version`) and [ValidationError] (422)
///   are its typed forms.
/// - [ServerError]: 5xx, 408, 429 (retry later).
/// - [UnknownError]: anything else.
sealed class AppError implements Exception {
  const AppError({this.status, this.messageEn, this.messageHi});

  final int? status;
  final String? messageEn;
  final String? messageHi;

  /// Worth retrying later without user action (the offline queue keeps it).
  bool get retryable => false;

  /// The server's localized message for [locale], when it sent one.
  String? localizedMessage(Locale locale) =>
      locale.languageCode == 'hi' && locale.scriptCode == null ? (messageHi ?? messageEn) : (messageEn ?? messageHi);

  /// Maps any thrown object to an [AppError] (identity for [AppError]).
  static AppError from(Object e) {
    if (e is AppError) return e;
    if (e is DioException) {
      final inner = e.error;
      if (inner is AppError) return inner;
      final res = e.response;
      if (res == null) {
        return isOfflineDioError(e) ? OfflineError(cause: e) : UnknownError(cause: e);
      }
      return fromResponse(res.statusCode, res.data);
    }
    return UnknownError(cause: e);
  }

  /// Maps an HTTP answer ([status] + JSON [body]).
  static AppError fromResponse(int? status, Object? body) {
    final env = ErrorEnvelope.parse(body);
    return switch (status) {
      401 => UnauthorizedError(code: env.code ?? 'unauthorized', messageEn: env.messageEn, messageHi: env.messageHi),
      408 || 429 => ServerError(status: status!, code: env.code, messageEn: env.messageEn, messageHi: env.messageHi),
      final s? when s >= 500 => ServerError(
        status: s,
        code: env.code,
        messageEn: env.messageEn,
        messageHi: env.messageHi,
      ),
      409 || 412 => ConflictError(
        status: status!,
        code: env.code ?? (status == 412 ? KitchenError.versionMismatch : 'conflict'),
        allowed: env.allowed,
        currentVersion: env.currentVersion,
        message: env.message,
        messageEn: env.messageEn,
        messageHi: env.messageHi,
      ),
      422 => ValidationError(
        code: env.code ?? 'validation_error',
        message: env.message,
        messageEn: env.messageEn,
        messageHi: env.messageHi,
        allowed: env.allowed,
      ),
      final s? when s >= 400 => KitchenError(
        status: s,
        code: env.code ?? 'http_$s',
        allowed: env.allowed,
        currentVersion: env.currentVersion,
        message: env.message,
        messageEn: env.messageEn,
        messageHi: env.messageHi,
      ),
      _ => UnknownError(status: status, cause: body),
    };
  }
}

/// The parsed error body: top-level fields, `details`, an `error` wrapper,
/// or FastAPI's `detail`.
class ErrorEnvelope {
  const ErrorEnvelope({
    this.code,
    this.message,
    this.messageEn,
    this.messageHi,
    this.allowed = const [],
    this.currentVersion,
  });

  final String? code;
  final String? message;
  final String? messageEn;
  final String? messageHi;
  final List<TicketStatus> allowed;
  final int? currentVersion;

  static String? _s(Object? v) => v == null ? null : '$v';

  factory ErrorEnvelope.parse(Object? body) {
    var j = body is Map ? body.cast<String, dynamic>() : const <String, dynamic>{};
    final detailString = j['detail'] is String ? j['detail'] as String : null;
    if (j['detail'] is Map) j = (j['detail'] as Map).cast<String, dynamic>();
    if (j['error'] is Map) j = (j['error'] as Map).cast<String, dynamic>();
    final details = j['details'] is Map ? (j['details'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final allowedRaw = j['allowed'] as List? ?? details['allowed'] as List? ?? const [];
    final cv = details['current_version'] ?? j['current_version'];
    return ErrorEnvelope(
      code: _s(j['code']),
      message: _s(j['message']) ?? _s(j['message_en']) ?? detailString,
      messageEn: _s(j['message_en']),
      messageHi: _s(j['message_hi']),
      allowed: [for (final a in allowedRaw) TicketStatus.fromWire('$a')],
      currentVersion: cv is num ? cv.toInt() : int.tryParse('${cv ?? ''}'),
    );
  }
}

/// 401 after the refresh failed: the user has to log in again.
final class UnauthorizedError extends AppError {
  const UnauthorizedError({this.code = 'unauthorized', super.messageEn, super.messageHi}) : super(status: 401);
  final String code;

  @override
  String toString() => 'UnauthorizedError($code)';
}

/// The backend could not be reached.
final class OfflineError extends AppError {
  const OfflineError({this.cause});
  final Object? cause;

  @override
  bool get retryable => true;

  @override
  String toString() => 'OfflineError($cause)';
}

/// 5xx / 408 / 429.
final class ServerError extends AppError {
  const ServerError({required int super.status, this.code, super.messageEn, super.messageHi});
  final String? code;

  @override
  bool get retryable => true;

  @override
  String toString() => 'ServerError($status, $code)';
}

final class UnknownError extends AppError {
  const UnknownError({super.status, this.cause});
  final Object? cause;

  @override
  String toString() => 'UnknownError($status, $cause)';
}

/// A 4xx answer the UI reacts to: 409 `invalid_transition` (with the allowed
/// next states), version conflicts (409/412), validation (422), 403 / 404.
base class KitchenError extends AppError {
  const KitchenError({
    super.status,
    required this.code,
    this.allowed = const [],
    this.message,
    this.currentVersion,
    super.messageEn,
    super.messageHi,
  });

  final String code;
  final List<TicketStatus> allowed;
  final String? message;

  /// `details.current_version` on a 412 `version_mismatch`.
  final int? currentVersion;

  static const invalidTransition = 'invalid_transition';
  static const versionMismatch = 'version_mismatch';
  static const reasonRequired = 'reason_required';
  static const alreadyConfirmed = 'menu_already_confirmed';

  /// The server's copy moved on: refresh and tell the user.
  bool get isConflict => status == 409 || status == 412 || code == invalidTransition || code == versionMismatch;

  bool get isValidation => status == 422;

  /// Rejected for good (replaying it will not help): 409 / 412 / 422.
  bool get isDefinitive => status == 409 || status == 412 || status == 422;

  /// Parses a 4xx body (any other status still yields a [KitchenError]).
  factory KitchenError.fromJson(int? status, Object? body) {
    final e = AppError.fromResponse(status, body);
    if (e is KitchenError) return e;
    final env = ErrorEnvelope.parse(body);
    return KitchenError(
      status: status,
      code: env.code ?? 'http_$status',
      allowed: env.allowed,
      currentVersion: env.currentVersion,
      message: env.message,
      messageEn: env.messageEn,
      messageHi: env.messageHi,
    );
  }

  @override
  String toString() => 'KitchenError($status, $code, allowed: ${allowed.map((a) => a.wire).toList()})';
}

/// 409 / 412.
final class ConflictError extends KitchenError {
  const ConflictError({
    super.status = 409,
    required super.code,
    super.allowed,
    super.currentVersion,
    super.message,
    super.messageEn,
    super.messageHi,
  });
}

/// 422.
final class ValidationError extends KitchenError {
  const ValidationError({required super.code, super.message, super.messageEn, super.messageHi, super.allowed})
    : super(status: 422);
}
