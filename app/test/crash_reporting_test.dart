import 'package:banega/core/crash_reporting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';

void main() {
  test('no DSN: the app just runs (Sentry is never initialised)', () async {
    var ran = false;
    await runWithCrashReporting(() => ran = true, dsn: '');
    expect(ran, isTrue);
    expect(Sentry.isEnabled, isFalse);
  });

  test('phones, tokens and codes are masked in free text', () {
    for (final p in ['+919876543210', '+91 98765 43210', '9876543210', '09876543210', '%2B919876543210']) {
      expect(scrubText('login $p failed'), isNot(contains(p.replaceAll('%2B', ''))), reason: p);
    }
    expect(scrubText('Authorization: Bearer abc.def'), isNot(contains('abc.def')));
    expect(scrubText('token $_jwt'), isNot(contains(_jwt)));
    expect(scrubText('{"phone": "+919876543210", "code": "123456"}'), isNot(contains('123456')));
    expect(scrubText('code=K7Q4MX&x=1'), isNot(contains('K7Q4MX')));
    // Ids, times and status codes survive.
    const keep = 'ticket 3f1c9a2e-5b7d-4c11-9e0a-1234567890ab status_code=500 at 13:30';
    expect(scrubText(keep), keep);
  });

  test('events lose bodies, headers and personal data', () {
    final e = SentryEvent(
      message: SentryMessage('OTP for +919876543210 failed'),
      user: SentryUser(id: 'u1', username: '+919876543210', ipAddress: '1.2.3.4'),
      request: SentryRequest(
        url: 'https://api.banega.app/v1/invites',
        method: 'POST',
        data: {'phone': '+919876543210'},
        headers: {'Authorization': 'Bearer $_jwt'},
        cookies: 'a=b',
      ),
      exceptions: [SentryException(type: 'DioException', value: 'refresh $_jwt for 9876543210')],
      breadcrumbs: [
        Breadcrumb(message: 'GET /v1/me', data: {'phone': '+919876543210', 'status_code': 200}),
      ],
    );
    final out = scrubEvent(e)!;
    expect(out.message!.formatted, isNot(contains('9876543210')));
    expect(out.user!.id, 'u1');
    expect(out.user!.username, isNull);
    expect(out.user!.ipAddress, isNull);
    expect(out.request!.data, isNull);
    expect(out.request!.headers, isEmpty);
    expect(out.request!.cookies, isNull);
    expect(out.request!.method, 'POST');
    expect(out.exceptions!.single.value, isNot(contains(_jwt)));
    expect(out.exceptions!.single.value, isNot(contains('9876543210')));
    expect(out.breadcrumbs!.single.data!['phone'], '[Filtered]');
    expect(out.breadcrumbs!.single.data!['status_code'], 200);
  });
}
