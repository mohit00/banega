import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/network/app_error.dart';
import '../../../data/data_source.dart';
import '../../auth/application/session.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../data/invites_repository.dart';
import '../domain/invite_models.dart';

final invitesRepositoryProvider = Provider<InvitesRepository>((ref) {
  if (ref.watch(dataSourceProvider) == DataSource.demo) return DemoInvitesRepository();
  return ApiInvitesRepository(ref.watch(dioProvider));
});

/// Pending invites (admin): Settings → "Banega par parivaar".
final pendingInvitesProvider = FutureProvider<List<Invite>>((ref) {
  ref.watch(kitchenRevisionProvider);
  return ref.watch(invitesRepositoryProvider).pending();
}, retry: (_, _) => null);

class InviteActions {
  InviteActions(this.ref);

  final Ref ref;

  InvitesRepository get _repo => ref.read(invitesRepositoryProvider);

  void _changed() => ref.read(kitchenRevisionProvider.notifier).bump();

  Future<CreatedInvite> create({required String phone, String? memberId}) async {
    final invite = await _repo.create(phone: phone, memberId: memberId);
    _changed();
    return invite;
  }

  Future<void> revoke(String id) async {
    await _repo.revoke(id);
    _changed();
  }

  /// The invitee joins with the code, then /v1/me is refetched (household,
  /// modes) so the startup gate moves on to Home.
  Future<void> join(String code) async {
    await _repo.acceptCode(code);
    await ref.read(sessionProvider.notifier).refreshMe();
  }
}

final inviteActionsProvider = Provider<InviteActions>(InviteActions.new);

/// The server's error code, whatever the status family.
String? appErrorCode(Object e) => switch (e) {
  KitchenError(:final code) => code,
  ServerError(:final code) => code,
  UnauthorizedError(:final code) => code,
  _ => null,
};

/// Friendly copy for a failed "Code se judiye".
String joinErrorText(AppLocalizations l, Object e) {
  if (e is OfflineError) return l.offlineBanner;
  return switch (appErrorCode(e)) {
    'invite_code_invalid' || 'invite_not_found' || 'not_found' || 'validation_error' => l.joinErrInvalid,
    'invite_expired' || 'gone' => l.joinErrExpired,
    'invite_phone_mismatch' => l.joinErrPhone,
    'already_in_household' => l.joinErrAlready,
    'invite_code_locked' || 'rate_limited' => l.joinErrLocked,
    _ => l.toastError,
  };
}
