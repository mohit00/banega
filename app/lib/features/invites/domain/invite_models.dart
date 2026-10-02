import 'package:flutter/foundation.dart';

import '../../../data/models.dart' show Json;

/// A pending invite (`GET /v1/invites`): bound to one phone, single use,
/// 7-day expiry, revocable.
@immutable
class Invite {
  const Invite({
    required this.id,
    required this.phone,
    this.role = 'member',
    this.memberId,
    this.expiresAt,
    this.createdAt,
  });

  final String id;

  /// E.164 (`+919876543210`); shown masked ([phoneMasked]).
  final String phone;

  /// `member` (adult family member) or `cook`.
  final String role;
  final String? memberId;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  String get phoneMasked => maskPhone(phone);

  factory Invite.fromJson(Json j) => Invite(
    id: '${j['id']}',
    phone: '${j['phone'] ?? ''}',
    role: j['role'] as String? ?? 'member',
    memberId: j['member_id'] as String?,
    expiresAt: _date(j['expires_at']),
    createdAt: _date(j['created_at']),
  );
}

/// `POST /v1/invites` → the invite plus the one-time secrets: the short
/// [code] the invitee types, the share text (Hinglish + English) and link.
@immutable
class CreatedInvite extends Invite {
  const CreatedInvite({
    required super.id,
    required super.phone,
    super.role,
    super.memberId,
    super.expiresAt,
    super.createdAt,
    required this.code,
    this.shareText = '',
    this.link = '',
  });

  final String code;
  final String shareText;
  final String link;

  factory CreatedInvite.fromJson(Json j) {
    final base = Invite.fromJson(j);
    return CreatedInvite(
      id: base.id,
      phone: base.phone,
      role: base.role,
      memberId: base.memberId,
      expiresAt: base.expiresAt,
      createdAt: base.createdAt,
      code: '${j['code'] ?? ''}',
      shareText: '${j['share_text'] ?? ''}',
      link: '${j['link'] ?? ''}',
    );
  }
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// `+91******3210`: country code and the last four digits.
String maskPhone(String phone) {
  if (phone.length <= 7) return '*' * phone.length;
  final head = phone.startsWith('+') ? phone.substring(0, 3) : '';
  return '$head${'*' * (phone.length - head.length - 4)}${phone.substring(phone.length - 4)}';
}

/// Invite codes: 6 characters from an alphabet without 0/O/1/I.
const kInviteCodeLength = 6;
const kInviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Upper case, separators dropped (`k7q-4mx` → `K7Q4MX`).
String normalizeInviteCode(String raw) => raw.replaceAll(RegExp(r'[\s\-_.]'), '').toUpperCase();
