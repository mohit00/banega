import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/clock.dart';
import 'core/motion/motion.dart';
import 'core/perf.dart';
import 'core/l10n/gen/app_localizations.dart';
import 'core/router/router.dart';
import 'core/theme/theme.dart';
import 'features/account/application/account_providers.dart';
import 'features/account/application/locale_controller.dart';
import 'features/kitchen/application/kitchen_providers.dart' show cookUsesApiProvider;
import 'features/kitchen/application/sync_service.dart';

export 'features/account/application/locale_controller.dart' show hinglish, localeProvider, deviceLocaleProvider;

// The family-side locale follows the Settings choice, else the device:
// Hinglish for hi-IN, English otherwise (build-plan §1.6, F-10-05).

class BanegaApp extends ConsumerWidget {
  const BanegaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // GET /v1/subscription on app start (trial / grace / read-only state).
    ref.listen(subscriptionProvider, (_, _) {});
    // API mode: one SyncService replays the offline queue on reconnect /
    // resume (idempotent start).
    if (ref.watch(cookUsesApiProvider)) ref.read(syncServiceProvider).start();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: LowEndScope(
        lowEnd: ref.watch(lowEndProvider),
        child: DayTicker(
          child: MaterialApp.router(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            theme: BTheme.light(),
            locale: ref.watch(localeProvider),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
  }
}
