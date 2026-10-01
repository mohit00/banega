import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/ui.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'routes.dart';

/// GoRouter's errorBuilder: an unknown link lands here with a way home.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.notFoundTitle, textAlign: TextAlign.center, style: BText.display(BType.display22)),
              const SizedBox(height: 18),
              BCta(
                key: const ValueKey('not-found-home'),
                label: l.notFoundHome,
                onPressed: () => context.go(Routes.start),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
