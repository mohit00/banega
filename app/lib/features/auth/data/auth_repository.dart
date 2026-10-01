import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';

/// OTP login (docs/openapi.json `auth`).
abstract interface class AuthRepository {
  /// POST /v1/auth/otp `{phone}`.
  Future<OtpChallenge> requestOtp(String phone);

  /// POST /v1/auth/verify `{phone, code}` → tokens.
  Future<AuthTokens> verify(String phone, String code);

  /// POST /v1/auth/refresh `{refresh_token}` → a new pair.
  Future<AuthTokens> refresh(String refreshToken);

  /// POST /v1/auth/logout (best effort).
  Future<void> logout(String accessToken);
}

/// Talks to the auth endpoints through a Dio **without** the auth
/// interceptor (so a refresh never recurses into itself).
class ApiAuthRepository with ApiGuard implements AuthRepository {
  ApiAuthRepository(this.dio);

  final Dio dio;

  @override
  Future<OtpChallenge> requestOtp(String phone) => guard(() async {
    final res = await dio.post<Object?>('/v1/auth/otp', data: {'phone': phone});
    return OtpChallenge.fromJson(phone, json(res.data));
  });

  @override
  Future<AuthTokens> verify(String phone, String code) => guard(() async {
    final res = await dio.post<Object?>('/v1/auth/verify', data: {'phone': phone, 'code': code});
    return AuthTokens.fromJson(json(res.data));
  });

  @override
  Future<AuthTokens> refresh(String refreshToken) => guard(() async {
    final res = await dio.post<Object?>('/v1/auth/refresh', data: {'refresh_token': refreshToken});
    return AuthTokens.fromJson(json(res.data));
  });

  @override
  Future<void> logout(String accessToken) => guard(() async {
    await dio.post<Object?>('/v1/auth/logout', options: Options(headers: {'Authorization': 'Bearer $accessToken'}));
  });
}
