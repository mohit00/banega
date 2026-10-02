import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/app_error.dart';
import '../domain/invite_models.dart';

/// Invites for a second adult (docs: backend/app/api/invites.py).
abstract interface class InvitesRepository {
  /// GET /v1/invites → pending invites (admin).
  Future<List<Invite>> pending();

  /// POST /v1/invites `{phone, role, member_id?}` → invite + code + share text.
  Future<CreatedInvite> create({required String phone, String? memberId, String role = 'member'});

  /// DELETE /v1/invites/{id}.
  Future<void> revoke(String id);

  /// POST /v1/invites/accept-code `{code}` (the invitee, signed in by OTP on
  /// the invited phone). Errors: 404 `invite_code_invalid`, 410
  /// `invite_expired`, 403 `invite_phone_mismatch`, 409
  /// `already_in_household`, 429 `invite_code_locked`.
  Future<void> acceptCode(String code);
}

class ApiInvitesRepository with ApiGuard implements InvitesRepository {
  ApiInvitesRepository(this.dio);

  final Dio dio;

  @override
  Future<List<Invite>> pending() => guard(() async {
    final res = await dio.get<Object?>('/v1/invites');
    return [for (final j in jsonList(res.data)) Invite.fromJson(j)];
  });

  @override
  Future<CreatedInvite> create({required String phone, String? memberId, String role = 'member'}) => guard(() async {
    final res = await dio.post<Object?>('/v1/invites', data: {'phone': phone, 'role': role, 'member_id': ?memberId});
    return CreatedInvite.fromJson(json(res.data));
  });

  @override
  Future<void> revoke(String id) => guard(() async {
    await dio.delete<Object?>('/v1/invites/${enc(id)}');
  });

  @override
  Future<void> acceptCode(String code) => guard(() async {
    await dio.post<Object?>('/v1/invites/accept-code', data: {'code': normalizeInviteCode(code)});
  });
}

/// Sandbox: invites live in memory (nobody can join a demo family).
class DemoInvitesRepository implements InvitesRepository {
  DemoInvitesRepository({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<Invite> _pending = [];
  int _seq = 0;

  @override
  Future<List<Invite>> pending() async => List.unmodifiable(_pending);

  @override
  Future<CreatedInvite> create({required String phone, String? memberId, String role = 'member'}) async {
    _pending.removeWhere((i) => i.phone == phone);
    final code = [
      for (var i = 0; i < kInviteCodeLength; i++) kInviteCodeAlphabet[_random.nextInt(kInviteCodeAlphabet.length)],
    ].join();
    final now = DateTime.now();
    final invite = CreatedInvite(
      id: 'demo-invite-${_seq++}',
      phone: phone,
      role: role,
      memberId: memberId,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      code: code,
      shareText:
          'Namaste! Aapko Banega par ghar mein joda hai. Banega app kholiye, isi number se login kijiye '
          'aur "Code se judiye" mein ye code daaliye: $code (7 din tak chalega).\n\n'
          'Hi! You\'re invited to the family on Banega. Open the Banega app, log in with this phone '
          'number and choose "Join my family with a code": $code (valid for 7 days).',
    );
    _pending.insert(0, invite);
    return invite;
  }

  @override
  Future<void> revoke(String id) async => _pending.removeWhere((i) => i.id == id);

  @override
  Future<void> acceptCode(String code) async =>
      throw const KitchenError(status: 404, code: 'invite_code_invalid', allowed: []);
}
