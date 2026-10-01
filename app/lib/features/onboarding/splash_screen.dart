import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/ui.dart';
import '../../core/config.dart';
import '../../core/router/startup_gate.dart' show onboardingProvider;
import '../../data/data_source.dart';
import '../account/application/account_providers.dart';

/// S1 — Splash (prototype "SPLASH"). "Apna ghar set karo" goes through the
/// DPDP consent screen on first run (F-X-02), then Family.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final consented = ref.watch(consentProvider) ?? false;
    return Scaffold(
      backgroundColor: BColors.haldi,
      body: SafeArea(
        // Fills the screen at normal sizes; scrolls when large text needs more
        // room (the thali shrinks first).
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Semantics(
                              header: true,
                              label: l.appTitle,
                              child: ExcludeSemantics(
                                child: Text.rich(
                                  TextSpan(
                                    text: l.wordmark,
                                    children: const [
                                      TextSpan(
                                        text: '.',
                                        style: TextStyle(color: BColors.green),
                                      ),
                                    ],
                                  ),
                                  style: BText.display(BType.display26),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          BBadge(label: l.aiMaharajBadge, background: BColors.ink, foreground: BColors.haldi),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: ThaliHero.sceneSize.width,
                              height: ThaliHero.sceneSize.height,
                              child: ThaliHero(orbit: true, semanticLabel: l.thaliAlt),
                            ),
                          ),
                        ),
                      ),
                      Text(l.splashTitle, style: BText.display(BType.h1, height: 1.02)),
                      const SizedBox(height: 12),
                      Text(l.splashBody, style: BText.body(BType.cta, color: BColors.ink2, height: 1.45)),
                      const SizedBox(height: 24),
                      BCta(
                        label: l.splashCta,
                        trailing: BIcons.arrowRight,
                        onPressed: () {
                          ref.read(sandboxProvider.notifier).exit();
                          // With a backend: consent → phone login → household; the
                          // local-only build goes straight to Family.
                          final next = ref.read(appConfigProvider).hasApi ? Routes.phone : Routes.family;
                          context.push(
                            consented ? next : (next == Routes.family ? Routes.consent : Routes.consentThen(next)),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      // The demo sandbox is an explicit choice, and it passes consent too.
                      BTextButton(
                        label: l.splashDemo,
                        onPressed: () {
                          ref.read(sandboxProvider.notifier).enter();
                          ref.read(onboardingProvider.notifier).markDone();
                          context.go(consented ? Routes.home : Routes.consentThen(Routes.home));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
