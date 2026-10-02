import 'package:banega/core/config.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/features/recipe/application/recipe_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Play requires a public privacy policy URL; Settings and the consent
/// screen open the hosted pages (docs/legal/site).
void main() {
  group('Legal links', () {
    test('default to the hosted pages', () {
      // No --dart-define in tests: the defaults apply.
      expect(kPrivacyPolicyUrl, 'https://banega.kornea.in/privacy');
      expect(kTermsUrl, 'https://banega.kornea.in/terms');
      expect(Uri.parse(kPrivacyPolicyUrl).isScheme('https'), isTrue);
      expect(Uri.parse(kTermsUrl).isScheme('https'), isTrue);
    });

    testWidgets('Settings opens the privacy policy and the terms', (tester) async {
      final opened = <Uri>[];
      await pumpBanega(
        tester,
        Routes.settings,
        tall: true,
        device: const Locale('en', 'US'),
        overrides: [
          urlLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      final privacy = find.byKey(const ValueKey('settings-privacy-policy'));
      await tester.scrollUntilVisible(privacy, 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms of service'), findsOneWidget);

      await tester.tap(privacy);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-terms')));
      await settle(tester);
      expect(opened, [Uri.parse(kPrivacyPolicyUrl), Uri.parse(kTermsUrl)]);
    });

    testWidgets('the consent screen opens the privacy policy', (tester) async {
      final opened = <Uri>[];
      await pumpBanega(
        tester,
        Routes.consent,
        tall: true,
        overrides: [
          urlLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      expect(find.text('Privacy policy padho'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('consent-privacy')));
      await settle(tester);
      expect(opened, [Uri.parse(kPrivacyPolicyUrl)]);
    });

    testWidgets('the consent note says what the AI service receives', (tester) async {
      await pumpBanega(tester, Routes.consent, tall: true, device: const Locale('en', 'US'));
      expect(find.textContaining('Anthropic'), findsOneWidget);
      expect(find.textContaining('health needs are never sent'), findsOneWidget);
    });
  });
}
