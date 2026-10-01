import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/session.dart';
import '../../features/kitchen/application/kitchen_providers.dart';
import '../../features/kitchen/data/ticket_cache.dart';
import '../../features/members/application/members_controller.dart';
import '../../features/menu/application/day_menu.dart';

/// Wipes what this device keeps about the signed-in household: the cook-mode
/// cache and offline queue (every scope), the cached /v1/me, device-only
/// member fields and the day-menu drafts. Runs on logout, when the refresh
/// token is rejected, and after account deletion.
final purgeLocalDataProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final store = ref.read(keyValueStoreProvider);
    try {
      await TicketCache.purgeAll(store);
      for (final k in await store.keys()) {
        if (k.startsWith('member.local.')) await store.remove(k);
      }
    } catch (_) {}
    await ref.read(sessionProvider.notifier).clear();
    ref.read(dayMenuProvider.notifier).reset();
    ref.invalidate(membersProvider);
    ref.invalidate(meProvider);
  },
);
