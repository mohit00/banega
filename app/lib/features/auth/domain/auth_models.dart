import 'package:flutter/foundation.dart';

import '../../../data/models.dart' show Json;

/// POST /v1/auth/verify and /v1/auth/refresh → `TokenPair`.
@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.userId = '',
    this.accessExpiresAt,
    this.isNewUser = false,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final DateTime? accessExpiresAt;
  final bool isNewUser;

  factory AuthTokens.fromJson(Json j) => AuthTokens(
    accessToken: '${j['access_token']}',
    refreshToken: '${j['refresh_token']}',
    userId: '${j['user_id'] ?? ''}',
    accessExpiresAt: j['access_expires_at'] is String ? DateTime.tryParse(j['access_expires_at'] as String) : null,
    isNewUser: j['is_new_user'] as bool? ?? false,
  );

  Json toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'access_expires_at': accessExpiresAt?.toIso8601String(),
    'is_new_user': isNewUser,
  };

  @override
  bool operator ==(Object other) =>
      other is AuthTokens && other.accessToken == accessToken && other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);
}

/// POST /v1/auth/otp → `OtpRequestOut`. [devCode] only comes back from a
/// backend running with ENV=dev; the OTP screen shows it in debug builds.
@immutable
class OtpChallenge {
  const OtpChallenge({required this.phone, this.expiresIn = 300, this.resendAfter = 30, this.devCode});

  final String phone;
  final int expiresIn;
  final int resendAfter;
  final String? devCode;

  factory OtpChallenge.fromJson(String phone, Json j) {
    final code = j['dev_code'] ?? j['code'];
    return OtpChallenge(
      phone: phone,
      expiresIn: (j['expires_in'] as num?)?.toInt() ?? 300,
      resendAfter: (j['resend_after'] as num?)?.toInt() ?? 30,
      devCode: code is String && code.isNotEmpty ? code : null,
    );
  }
}

/// `+91XXXXXXXXXX` from what the user typed (spaces, dashes, a leading 0 or
/// +91 are fine); null unless it is a 10-digit Indian mobile number.
String? normalizeIndianPhone(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  if (d.length != 10 || !RegExp(r'^[6-9]').hasMatch(d)) return null;
  return '+91$d';
}
