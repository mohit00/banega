import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Push is on unless the build passes `--dart-define=FCM=0`. Whether it can
/// work is decided at runtime: Firebase only initialises when the build had
/// `android/app/google-services.json` (the Gradle plugin turns it into
/// resources); without it [FirebasePushMessaging.start] returns false and the
/// app runs without push.
const kFcmEnabled = bool.fromEnvironment('FCM', defaultValue: true);

/// The device push channel (FCM). Faked in tests.
abstract interface class PushMessaging {
  /// Initialise and ask for notification permission (Android 13+). False:
  /// no push on this install (no Firebase config, or permission denied).
  Future<bool> start();

  Future<String?> token();
  Stream<String> get onTokenRefresh;

  /// `data` of notifications the user tapped (including the one that
  /// launched the app).
  Stream<Map<String, String>> get onOpened;

  /// A message received while the app is in the foreground.
  Stream<Map<String, String>> get onForeground;

  Future<void> deleteToken();
}

/// FCM through firebase_messaging.
class FirebasePushMessaging implements PushMessaging {
  final _opened = StreamController<Map<String, String>>.broadcast();
  bool _ready = false;

  static Map<String, String> _data(RemoteMessage m) => {for (final e in m.data.entries) e.key: '${e.value}'};

  @override
  Future<bool> start() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (e) {
      debugPrint('push: Firebase not configured ($e)');
      return false;
    }
    final m = FirebaseMessaging.instance;
    final settings = await m.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return false;
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _opened.add(_data(msg)));
    final initial = await m.getInitialMessage();
    if (initial != null) scheduleMicrotask(() => _opened.add(_data(initial)));
    _ready = true;
    return true;
  }

  @override
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<Map<String, String>> get onOpened => _opened.stream;

  @override
  Stream<Map<String, String>> get onForeground => FirebaseMessaging.onMessage.map(_data);

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();
}

/// Null → no push in this build / platform (web, iOS until configured,
/// `FCM=0`). Tests override it with a fake; unconfigured, [start] is false.
final pushMessagingProvider = Provider<PushMessaging?>((ref) {
  if (!kFcmEnabled || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  return FirebasePushMessaging();
});
