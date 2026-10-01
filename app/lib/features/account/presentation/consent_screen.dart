import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../ui/ui.dart';
import '../../recipe/application/recipe_providers.dart' show urlLauncherProvider;
import '../application/account_providers.dart';

const kPrivacyPolicyUrl = 'https://banega.app/privacy';

/// First-run DPDP consent (F-X-02, FR-A9): after Splash, before Family.
/// "Maan liya" stores the consent on the device and POSTs /v1/consent.
/// [review] opens it from Settings (no onward navigation).
class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key, this.review = false, this.next});

  final bool review;

  /// Where to go after accepting (the demo link passes `/home`); Family
  /// otherwise.
  final String? next;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final accepted = ref.watch(consentProvider) ?? false;
    return Scaffold(
      backgroundColor: BColors.haldi,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: BIconButton(
                  icon: BIcons.chevronLeft,
                  semanticLabel: l.back,
                  background: BColors.card.withValues(alpha: .55),
                  onPressed: () => context.canPop() ? context.pop() : context.go(Routes.splash),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    Text(l.consentTitle, style: BText.display(BType.h1Family, height: 1.05)),
                    const SizedBox(height: 14),
                    Text(l.consentBody, style: BText.body(BType.cta, color: BColors.ink2, height: 1.45)),
                    const SizedBox(height: 12),
                    _Note(icon: BIcons.chef, text: l.consentLlmNote),
                    const SizedBox(height: 8),
                    _Note(icon: BIcons.users, text: l.consentKids),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BTextButton(
                        label: l.consentPrivacy,
                        onPressed: () => ref.read(urlLauncherProvider)(Uri.parse(kPrivacyPolicyUrl)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!review || !accepted)
                BCta(
                  key: const ValueKey('consent-accept'),
                  label: l.consentAccept,
                  trailing: BIcons.arrowRight,
                  onPressed: () {
                    // Saved in the background: the local flag flips at once.
                    unawaited(ref.read(consentProvider.notifier).accept());
                    if (review) {
                      context.pop();
                    } else {
                      final to = next;
                      if (to != null && to.startsWith('/')) {
                        context.go(to);
                      } else {
                        context.pushReplacement(Routes.family);
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final BIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BColors.card.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(BRadii.cta),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BIcon(icon, size: 18, color: BColors.ink2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
