import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/network/network_status.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'pressable.dart';

/// Thin ink strip shown while the backend cannot be reached: the screen keeps
/// what it has, and [onRetry] re-reads. Hidden when online. API mode never
/// switches to demo data instead.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, this.onRetry, this.force = false, this.message, this.textStyle});

  final VoidCallback? onRetry;

  /// Show even when [networkOfflineProvider] is false (e.g. cook mode reading
  /// its cache).
  final bool force;
  final String? message;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!force && !ref.watch(networkOfflineProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('offline-banner'),
        color: BColors.ink,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message ?? l.offlineBanner,
                style: textStyle ?? BText.body(BType.caption, weight: FontWeight.w700, color: BColors.card),
              ),
            ),
            if (onRetry != null)
              Pressable(
                key: const ValueKey('offline-retry'),
                onTap: onRetry,
                semanticLabel: l.offlineRetry,
                builder: (context, _) => Container(
                  constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l.offlineRetry,
                    style: BText.body(BType.caption, weight: FontWeight.w800, color: BColors.haldi),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
