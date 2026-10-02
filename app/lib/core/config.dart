import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Backend base URL (e.g. `http://10.0.2.2:8000` for the Android emulator
/// talking to the compose stack). Leave null to run on the in-memory demo
/// sandbox. Can also be set at build time:
/// `flutter run --dart-define=BANEGA_API_BASE_URL=http://10.0.2.2:8000`.
const String? kApiBaseUrl = null;

const _fromEnv = String.fromEnvironment('BANEGA_API_BASE_URL');

/// Public legal pages (docs/legal/site), opened from Settings and the consent
/// screen. Play requires the privacy policy at a public URL. Override per
/// build: `--dart-define=BANEGA_PRIVACY_URL=https://...` /
/// `--dart-define=BANEGA_TERMS_URL=https://...`.
const kPrivacyPolicyUrl = String.fromEnvironment(
  'BANEGA_PRIVACY_URL',
  defaultValue: 'https://banega.kornea.in/privacy',
);
const kTermsUrl = String.fromEnvironment('BANEGA_TERMS_URL', defaultValue: 'https://banega.kornea.in/terms');

@immutable
class AppConfig {
  const AppConfig({this.apiBaseUrl, this.connectTimeout = const Duration(seconds: 4)});

  /// Null → demo data only.
  final String? apiBaseUrl;
  final Duration connectTimeout;

  bool get hasApi => apiBaseUrl != null && apiBaseUrl!.isNotEmpty;
}

/// Override in tests to point at a fake backend.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig(apiBaseUrl: _fromEnv.isNotEmpty ? _fromEnv : kApiBaseUrl),
);

/// Transport override for the API clients (tests plug a fake adapter in
/// here; null → Dio's default).
final httpClientAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// The date Home plans for and the clock that picks the default slot.
/// Override in tests for deterministic slots.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
