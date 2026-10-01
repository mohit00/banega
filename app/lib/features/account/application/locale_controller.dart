import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../kitchen/application/kitchen_providers.dart' show keyValueStoreProvider;

/// Hinglish (hi-Latn), the template locale.
const Locale hinglish = Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn');

/// Family-side UI languages (FRD §10; F-10-05).
enum AppLanguage {
  hinglish('hi_Latn', Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn')),
  english('en', Locale('en')),
  hindi('hi', Locale('hi'));

  const AppLanguage(this.key, this.locale);

  /// Stored preference / `User.language` value.
  final String key;
  final Locale locale;

  static AppLanguage? fromKey(String? k) {
    for (final l in values) {
      if (l.key == k) return l;
    }
    return null;
  }

  static AppLanguage of(Locale l) => l.languageCode == 'en'
      ? english
      : l.scriptCode == 'Latn'
      ? hinglish
      : hindi;
}

/// F-10-05: Hinglish when the device is hi-IN, English otherwise (Hindi
/// script stays a choice in Settings).
AppLanguage defaultLanguageFor(Locale device) =>
    device.languageCode == 'hi' && (device.countryCode == null || device.countryCode == 'IN')
    ? AppLanguage.hinglish
    : AppLanguage.english;

/// The device locale; tests override it.
final deviceLocaleProvider = Provider<Locale>((ref) => PlatformDispatcher.instance.locale);

/// The family-side locale: the saved choice, else the device default.
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  static const storeKey = 'app.language';
  bool _chosen = false;

  @override
  Locale build() {
    Future.microtask(_load);
    return defaultLanguageFor(ref.watch(deviceLocaleProvider)).locale;
  }

  AppLanguage get language => AppLanguage.of(state);

  Future<void> _load() async {
    try {
      final saved = AppLanguage.fromKey(await ref.read(keyValueStoreProvider).get(storeKey));
      if (saved != null && ref.mounted && !_chosen) state = saved.locale;
    } catch (_) {
      // No storage (tests / first run): keep the device default.
    }
  }

  Future<void> set(AppLanguage l) async {
    _chosen = true;
    state = l.locale;
    try {
      await ref.read(keyValueStoreProvider).set(storeKey, l.key);
    } catch (_) {}
  }
}
