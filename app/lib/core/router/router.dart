import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/consent_screen.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/account/presentation/paywall_screen.dart';
import '../../features/account/presentation/settings_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/home/loading_screen.dart';
import '../../features/members/presentation/family_screen.dart';
import '../../features/members/presentation/prefs_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/recipe/presentation/recipe_detail_screen.dart';
import '../../features/cook_mode/cook_recipe_screen.dart';
import '../../features/cook_mode/cook_ticket_screen.dart';
import '../../features/cook_mode/cook_tickets_screen.dart';
import '../../features/cook_mode/ticket_thread_screen.dart';
import '../../features/menu/presentation/plan_screen.dart';
import '../../features/pantry/presentation/ration_screen.dart';
import '../../features/pantry/presentation/stock_screen.dart';
import '../../features/tickets/presentation/inbox_screen.dart';
import '../../features/tickets/presentation/ticket_detail_screen.dart';
import '../../ui/gallery/gallery_screen.dart';
import '../motion/motion.dart';
import 'not_found_screen.dart';
import 'routes.dart';
import 'startup_gate.dart';

/// Initial location; tests override this to start on a given screen.
final initialLocationProvider = Provider<String>((ref) => Routes.start);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = GateRefresh(ref);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    initialLocation: ref.watch(initialLocationProvider),
    refreshListenable: refresh,
    redirect: (context, state) => startupRedirect(readGate(ref), state.uri),
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.start),
      GoRoute(path: Routes.start, pageBuilder: (c, s) => _fade(s, const StartScreen())),
      GoRoute(path: Routes.splash, pageBuilder: (c, s) => _rise(s, const SplashScreen())),
      GoRoute(path: Routes.phone, pageBuilder: (c, s) => _rise(s, const PhoneScreen())),
      GoRoute(path: Routes.otp, pageBuilder: (c, s) => _rise(s, const OtpScreen())),
      GoRoute(path: Routes.createHousehold, pageBuilder: (c, s) => _rise(s, const CreateHouseholdScreen())),
      GoRoute(path: Routes.family, pageBuilder: (c, s) => _rise(s, const FamilyScreen())),
      GoRoute(
        path: Routes.prefsPattern,
        pageBuilder: (c, s) => _rise(s, PrefsScreen(memberId: s.pathParameters['memberId']!)),
      ),
      GoRoute(path: Routes.loading, pageBuilder: (c, s) => _rise(s, const LoadingScreen())),
      // Home has no `enter` class in the prototype — it appears without the rise.
      GoRoute(path: Routes.home, pageBuilder: (c, s) => _fade(s, const HomeScreen())),
      GoRoute(
        path: Routes.chat,
        pageBuilder: (c, s) => _rise(s, ChatScreen(initialQuery: s.uri.queryParameters['q'])),
      ),
      GoRoute(
        path: Routes.recipePattern,
        pageBuilder: (c, s) => _rise(
          s,
          RecipeDetailScreen(
            recipeId: s.pathParameters['recipeId']!,
            menuDate: s.uri.queryParameters['date'],
            menuSlot: s.uri.queryParameters['slot'],
          ),
        ),
      ),
      GoRoute(path: Routes.plan, pageBuilder: (c, s) => _rise(s, const PlanScreen())),
      GoRoute(
        path: Routes.ticketPattern,
        pageBuilder: (c, s) => _rise(s, TicketDetailScreen(ticketId: s.pathParameters['ticketId']!)),
      ),
      GoRoute(
        path: Routes.ticketThreadPattern,
        pageBuilder: (c, s) => _rise(s, TicketThreadScreen(ticketId: s.pathParameters['ticketId']!)),
      ),
      GoRoute(path: Routes.inbox, pageBuilder: (c, s) => _rise(s, const InboxScreen())),
      GoRoute(path: Routes.settings, pageBuilder: (c, s) => _rise(s, const SettingsScreen())),
      GoRoute(path: Routes.stock, pageBuilder: (c, s) => _rise(s, const StockScreen())),
      GoRoute(path: Routes.ration, pageBuilder: (c, s) => _rise(s, const RationScreen())),
      GoRoute(path: Routes.paywall, pageBuilder: (c, s) => _rise(s, const PaywallScreen())),
      GoRoute(
        path: Routes.consent,
        pageBuilder: (c, s) => _rise(
          s,
          ConsentScreen(review: s.uri.queryParameters['review'] == '1', next: s.uri.queryParameters['next']),
        ),
      ),
      GoRoute(path: Routes.cookStock, pageBuilder: (c, s) => _rise(s, const StockScreen(cook: true))),
      GoRoute(path: Routes.cookRation, pageBuilder: (c, s) => _rise(s, const CookRationScreen())),
      GoRoute(path: Routes.cook, pageBuilder: (c, s) => _rise(s, const CookTicketsScreen())),
      GoRoute(
        path: Routes.cookTicketPattern,
        pageBuilder: (c, s) => _rise(s, CookTicketScreen(ticketId: s.pathParameters['ticketId']!)),
      ),
      GoRoute(
        path: Routes.cookRecipePattern,
        pageBuilder: (c, s) => _rise(
          s,
          CookRecipeScreen(ticketId: s.pathParameters['ticketId']!, recipeId: s.pathParameters['recipeId']!),
        ),
      ),
      GoRoute(
        path: Routes.cookThreadPattern,
        pageBuilder: (c, s) => _rise(s, TicketThreadScreen(ticketId: s.pathParameters['ticketId']!, cook: true)),
      ),
      // Internal design-system sign-off screen: debug builds only.
      if (kDebugMode) GoRoute(path: Routes.gallery, pageBuilder: (c, s) => _rise(s, const GalleryScreen())),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The prototype's `.enter` animation: rise 18px + fade over 450 ms,
/// cubic(.2,.8,.2,1). Reduce-motion makes it instant.
CustomTransitionPage<void> _rise(GoRouterState s, Widget child) => CustomTransitionPage<void>(
  key: s.pageKey,
  child: child,
  transitionDuration: Motion.rise,
  reverseTransitionDuration: Motion.rise,
  transitionsBuilder: (context, animation, secondary, child) {
    if (Motion.reduce(context)) return child;
    final a = CurvedAnimation(parent: animation, curve: Motion.easeOut);
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, Motion.riseOffset * (1 - a.value)), child: child),
      ),
    );
  },
);

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
  key: s.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 200),
  transitionsBuilder: (context, animation, secondary, child) =>
      Motion.reduce(context) ? child : FadeTransition(opacity: animation, child: child),
);
