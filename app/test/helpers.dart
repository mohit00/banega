import 'package:banega/app.dart';
import 'package:banega/core/config.dart';
import 'package:banega/core/l10n/gen/app_localizations.dart';
import 'package:banega/core/router/router.dart';
import 'package:banega/core/theme/theme.dart';
import 'package:banega/core/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Sets the test surface to the prototype's 390×844 phone frame.
void usePhoneFrame(WidgetTester tester) {
  tester.view.physicalSize = BSizes.frame * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// A phone-width surface tall enough that every Home tile / Detail section is
/// laid out without scrolling (ListView builds lazily).
void useTallFrame(WidgetTester tester, {double height = 2600}) {
  tester.view.physicalSize = Size(BSizes.frame.width, height) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Midday, so Home opens on lunch like the prototype.
final testNoon = DateTime(2026, 9, 26, 12);

/// Pumps the whole app starting at [location]. Looping animations never
/// settle, so this advances a fixed amount of time instead of pumpAndSettle.
Future<ProviderContainer> pumpBanega(
  WidgetTester tester,
  String location, {
  bool reduceMotion = false,
  bool tall = false,
  DateTime? now,
  List<Override> overrides = const [],
  Locale? device = const Locale('hi', 'IN'),
}) async {
  if (tall) {
    useTallFrame(tester);
  } else {
    usePhoneFrame(tester);
  }
  final clock = now ?? testNoon;
  final container = ProviderContainer(
    overrides: [
      initialLocationProvider.overrideWith((ref) => location),
      clockProvider.overrideWithValue(() => clock),
      // A hi-IN phone: the family side defaults to Hinglish (F-10-05).
      if (device != null) deviceLocaleProvider.overrideWithValue(device),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  Widget app = UncontrolledProviderScope(container: container, child: const BanegaApp());
  if (reduceMotion) {
    app = MediaQuery(data: const MediaQueryData(disableAnimations: true), child: app);
  }
  await tester.pumpWidget(app);
  await settle(tester);
  return container;
}

/// Lets entrance animations and page transitions finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Hosts a single component with localizations and theme, for layout tests.
Future<void> pumpComponent(WidgetTester tester, Widget child, {double width = 390}) async {
  usePhoneFrame(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: BTheme.light(),
      locale: hinglish,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await settle(tester);
}

/// A bare container with the clock pinned to [now] (provider-level tests).
ProviderContainer containerAt(DateTime now, {List<Override> overrides = const []}) {
  final c = ProviderContainer(overrides: [clockProvider.overrideWithValue(() => now), ...overrides]);
  addTearDown(c.dispose);
  return c;
}
