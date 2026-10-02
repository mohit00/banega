import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/data_source.dart';
import '../../features/account/application/account_providers.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/session.dart';
import '../../features/kitchen/application/kitchen_providers.dart';
import '../../features/kitchen/domain/kitchen_models.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'routes.dart';

/// Whether the first-run flow (Splash → …) has been completed on this
/// device (shared_preferences `onboarding.done`); null while loading.
final onboardingProvider = NotifierProvider<OnboardingController, bool?>(OnboardingController.new);

class OnboardingController extends Notifier<bool?> {
  static const storeKey = 'onboarding.done';

  @override
  bool? build() {
    Future.microtask(_load);
    return null;
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(keyValueStoreProvider).get(storeKey);
      if (ref.mounted && state == null) state = v == '1';
    } catch (_) {
      if (ref.mounted && state == null) state = false;
    }
  }

  Future<void> markDone() async {
    if (state == true) return;
    state = true;
    try {
      await ref.read(keyValueStoreProvider).set(storeKey, '1');
    } catch (_) {}
  }
}

/// Everything the startup gate decides on.
@immutable
class GateInput {
  const GateInput({
    required this.api,
    required this.auth,
    required this.consent,
    required this.onboarded,
    required this.me,
  });

  /// API mode (false → demo sandbox / no backend).
  final bool api;
  final AuthStatus auth;
  final bool? consent;
  final bool? onboarded;

  /// Cached / fetched /v1/me (API mode).
  final Me? me;
}

const _authRoutes = {Routes.phone, Routes.otp};

/// The startup state machine, as a GoRouter redirect:
///
/// - Sandbox (demo): only the entry point is gated: `/start` → Splash on
///   first launch, else consent (if missing) → Home. The Splash demo link
///   passes consent itself.
/// - API mode: signed out → Splash on first launch, else `/phone`; no
///   consent → `/consent`; no household → create one (or join one with
///   an invite code); hired cook →
///   `/cook`; entry screens → Home. Waits (null) while a piece is loading.
String? startupRedirect(GateInput g, Uri uri) {
  final loc = uri.path;
  if (!g.api) {
    if (loc != Routes.start) return null;
    if (g.onboarded == null || g.consent == null) return null;
    if (!g.onboarded!) return Routes.splash;
    return g.consent! ? Routes.home : Routes.consentThen(Routes.home);
  }
  switch (g.auth) {
    case AuthStatus.unknown:
      return null;
    case AuthStatus.signedOut:
      if (loc == Routes.splash || loc == Routes.consent || _authRoutes.contains(loc)) return null;
      if (g.onboarded == null) return null;
      return g.onboarded! ? Routes.phone : Routes.splash;
    case AuthStatus.signedIn:
      break;
  }
  if (g.consent == false && loc != Routes.consent) {
    final target = loc == Routes.start || _authRoutes.contains(loc) || loc == Routes.splash ? Routes.home : '$uri';
    return Routes.consentThen(target);
  }
  final me = g.me;
  if (me == null) return null; // wait for /v1/me (the start screen fetches it)
  if (!me.hasHousehold) {
    const open = {Routes.createHousehold, Routes.joinHousehold, Routes.consent};
    return open.contains(loc) ? null : Routes.createHousehold;
  }
  if (me.cookOnly && !loc.startsWith(Routes.cook) && loc != Routes.settings && loc != Routes.consent) {
    return Routes.cook;
  }
  if (loc == Routes.start ||
      loc == Routes.splash ||
      _authRoutes.contains(loc) ||
      loc == Routes.createHousehold ||
      loc == Routes.joinHousehold) {
    return SessionController.routeFor(me);
  }
  return null;
}

/// Reads the gate's inputs (and starts loading the ones that persist).
GateInput readGate(Ref ref) {
  final api = ref.read(dataSourceProvider) == DataSource.api;
  return GateInput(
    api: api,
    auth: api ? ref.read(authControllerProvider).status : AuthStatus.signedOut,
    consent: ref.read(consentProvider),
    onboarded: ref.read(onboardingProvider),
    me: api ? ref.read(sessionProvider) : null,
  );
}

/// Notifies GoRouter whenever an input of the gate changes.
class GateRefresh extends ChangeNotifier {
  GateRefresh(Ref ref) {
    ref.listen<DataSource>(dataSourceProvider, (_, _) => notifyListeners());
    ref.listen<bool?>(consentProvider, (_, _) => notifyListeners());
    ref.listen<bool?>(onboardingProvider, (_, _) => notifyListeners());
    ref.listen<Me?>(sessionProvider, (_, _) => notifyListeners());
    ref.listen(authControllerProvider, (prev, next) {
      // A fresh session: load the cached /me before the network answers.
      if (next.status == AuthStatus.signedIn && prev?.status != AuthStatus.signedIn) {
        ref.read(sessionProvider.notifier).loadCached();
      }
      notifyListeners();
    });
  }
}

/// `/start`: a plain haldi screen while the gate waits (tokens, consent,
/// onboarding flag, /v1/me). Fetches /v1/me in API mode and offers a retry
/// when it fails without a cached copy.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final api = ref.watch(dataSourceProvider) == DataSource.api;
    final signedIn = api && ref.watch(authControllerProvider).status == AuthStatus.signedIn;
    final me = signedIn ? ref.watch(meProvider) : null;
    return Scaffold(
      backgroundColor: BColors.haldi,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                text: l.wordmark,
                children: const [
                  TextSpan(
                    text: '.',
                    style: TextStyle(color: BColors.green),
                  ),
                ],
              ),
              style: BText.display(BType.h1),
            ),
            const SizedBox(height: 20),
            if (me != null && me.hasError && ref.watch(sessionProvider) == null) ...[
              Text(l.offlineBanner, textAlign: TextAlign.center, style: BText.body(BType.body)),
              const SizedBox(height: 10),
              TextButton(
                key: const ValueKey('start-retry'),
                onPressed: () => ref.invalidate(meProvider),
                child: Text(
                  l.retry,
                  style: BText.body(BType.body, weight: FontWeight.w800, color: BColors.green),
                ),
              ),
            ] else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: BColors.ink),
              ),
          ],
        ),
      ),
    );
  }
}
