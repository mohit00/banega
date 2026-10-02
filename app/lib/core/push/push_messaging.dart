import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

/// Android channel for every Banega alert: high importance, so it rings and
/// pops up. The server targets it by id (`ANDROID_CHANNEL_ID` in
/// backend/app/services/notifications.py) and the manifest makes it FCM's
/// default for background messages.
const kAlertsChannel = AndroidNotificationChannel(
  'banega_alerts',
  'Banega alerts',
  description: 'Tickets, messages and kitchen updates',
  importance: Importance.high,
);

/// FCM through firebase_messaging. In the foreground FCM shows nothing on
/// Android, so messages are posted as local notifications (sound + heads-up)
/// on [kAlertsChannel]; tapping one opens it like a background notification.
class FirebasePushMessaging implements PushMessaging {
  final _opened = StreamController<Map<String, String>>.broadcast();
  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static Map<String, String> _data(RemoteMessage m) => {for (final e in m.data.entries) e.key: '${e.value}'};

  Future<void> _startLocal() async {
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        final decoded = jsonDecode(payload);
        if (decoded is Map) _opened.add({for (final e in decoded.entries) '${e.key}': '${e.value}'});
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(kAlertsChannel);
    final launch = await _local.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        scheduleMicrotask(() => _opened.add({for (final e in decoded.entries) '${e.key}': '${e.value}'}));
      }
    }
  }

  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    await _local.show(
      id: m.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kAlertsChannel.id,
          kAlertsChannel.name,
          channelDescription: kAlertsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          styleInformation: BigTextStyleInformation(n.body ?? ''),
        ),
      ),
      payload: jsonEncode(_data(m)),
    );
  }

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
    try {
      await _startLocal();
      FirebaseMessaging.onMessage.listen((msg) => unawaited(_showForeground(msg)));
    } catch (e) {
      debugPrint('push: local notifications unavailable ($e)');
    }
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
