import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_models.dart';

/// Where the session tokens live. The app uses [SecureTokenStore]
/// (Keystore / Keychain); tests use [MemoryTokenStore].
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'banega.auth.tokens';

  @override
  Future<AuthTokens?> read() async {
    final raw = await _s.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AuthTokens.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(AuthTokens tokens) => _s.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _s.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens t) async => tokens = t;

  @override
  Future<void> clear() async => tokens = null;
}
