// Optional crash reporting (Sentry).
//
// Off unless the build passes `--dart-define=SENTRY_DSN=https://...`: with no
// DSN, [runWithCrashReporting] just runs the app and nothing is sent. Every
// event and breadcrumb is scrubbed first: phone numbers, bearer tokens / JWTs
// and OTP / invite codes are masked; request bodies, cookies and headers are
// dropped; the user is reduced to its opaque id.
import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

const kSentryDsn = String.fromEnvironment('SENTRY_DSN');
const kSentryEnvironment = String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'production');

const _filtered = '[Filtered]';

// +91 98765 43210, 09876543210, 9876543210, +919876543210, %2B919876543210.
final _phone = RegExp(
  r'(?<![\w-])(?:(?:\+|%2B)\d{1,3}[\s-]?)?0?[6-9]\d{4}[\s-]?\d{5}(?![\w-])|(?:\+|%2B)\d{10,15}(?!\d)',
  caseSensitive: false,
);
final _jwt = RegExp(r'eyJ[\w-]{5,}\.[\w-]{5,}\.[\w-]{5,}');
final _bearer = RegExp(r'\bbearer\s+[\w.~+/=-]+', caseSensitive: false);
// "code": "123456", otp=123456, refresh_token: abc...
final _secretPair = RegExp(
  r'''(?<![\w-])(["']?(?:code|otp|dev_code|access_token|refresh_token|token|push_token)["']?\s*[:=]\s*["']?)[^"'&,\s}]+''',
  caseSensitive: false,
);
final _sensitiveKey = RegExp(
  r'(phone|token|password|secret|otp|authorization|cookie|device[_-]?id|idempotency)|^(code|invite_code|dev_code)$',
  caseSensitive: false,
);

/// Masks phone numbers, tokens and codes inside free text.
String scrubText(String s) => s
    .replaceAll(_jwt, _filtered)
    .replaceAllMapped(_bearer, (_) => 'Bearer $_filtered')
    .replaceAllMapped(_secretPair, (m) => '${m[1]}$_filtered')
    .replaceAll(_phone, _filtered);

Object? _scrubValue(Object? v, [int depth = 0]) {
  if (depth > 10) return _filtered;
  if (v is String) return scrubText(v);
  if (v is Map) {
    return {
      for (final e in v.entries)
        e.key: e.key is String && _sensitiveKey.hasMatch(e.key as String) && e.value != null
            ? _filtered
            : _scrubValue(e.value, depth + 1),
    };
  }
  if (v is Iterable) return [for (final x in v) _scrubValue(x, depth + 1)];
  return v;
}

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? m) =>
    m == null ? null : (_scrubValue(m) as Map).cast<String, dynamic>();

Breadcrumb? scrubBreadcrumb(Breadcrumb? b, [Hint? hint]) {
  if (b == null) return null;
  // sentry 9: fields are assigned in place (copyWith is deprecated).
  b.message = b.message == null ? null : scrubText(b.message!);
  b.data = _scrubMap(b.data);
  return b;
}

/// `beforeSend`: never drops the event, only strips what identifies people.
SentryEvent? scrubEvent(SentryEvent e, [Hint? hint]) {
  final req = e.request;
  final user = e.user;
  final msg = e.message;
  // copyWith keeps a field when given null, so request / user are rebuilt
  // and then swapped in.
  // ignore: deprecated_member_use
  final extra = _scrubMap(e.extra);
  return SentryEvent(
    eventId: e.eventId,
    timestamp: e.timestamp,
    platform: e.platform,
    logger: e.logger,
    serverName: e.serverName,
    release: e.release,
    dist: e.dist,
    environment: e.environment,
    modules: e.modules,
    message: msg == null ? null : SentryMessage(scrubText(msg.formatted)),
    transaction: e.transaction == null ? null : scrubText(e.transaction!),
    throwable: e.throwable,
    level: e.level,
    culprit: e.culprit,
    tags: e.tags?.map((k, v) => MapEntry(k, scrubText(v))),
    // ignore: deprecated_member_use
    extra: extra,
    fingerprint: e.fingerprint,
    // No phone, name, email or IP: the opaque id only.
    user: user == null ? null : SentryUser(id: user.id),
    contexts: e.contexts,
    breadcrumbs: e.breadcrumbs?.map((b) => scrubBreadcrumb(b)!).toList(),
    sdk: e.sdk,
    // Bodies, cookies and headers (bearer token, X-Device-Id) are dropped.
    request: req == null
        ? null
        : SentryRequest(
            url: req.url == null ? null : scrubText(req.url!),
            method: req.method,
            queryString: req.queryString == null ? null : scrubText(req.queryString!),
          ),
    debugMeta: e.debugMeta,
    exceptions: e.exceptions?.map((x) {
      if (x.value != null) x.value = scrubText(x.value!);
      return x;
    }).toList(),
    threads: e.threads,
    type: e.type,
  );
}

/// Runs the app, inside Sentry when a DSN was compiled in.
Future<void> runWithCrashReporting(FutureOr<void> Function() appRunner, {String dsn = kSentryDsn}) async {
  if (dsn.isEmpty) {
    await appRunner();
    return;
  }
  await SentryFlutter.init((o) {
    o.dsn = dsn;
    o.environment = kSentryEnvironment;
    o.sendDefaultPii = false;
    o.attachScreenshot = false;
    o.tracesSampleRate = 0;
    o.beforeSend = scrubEvent;
    o.beforeBreadcrumb = scrubBreadcrumb;
  }, appRunner: appRunner);
}
