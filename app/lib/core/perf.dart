import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/kitchen/application/kitchen_providers.dart' show keyValueStoreProvider;

/// A small / low-resolution screen is our proxy for a low-end phone (RAM is
/// not exposed without a plugin): shorter side under 720 physical pixels.
bool looksLowEnd() {
  try {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return false;
    final s = views.first.physicalSize;
    final shorter = math.min(s.width, s.height);
    return shorter > 0 && shorter < 720;
  } catch (_) {
    return false;
  }
}

/// "Light animations": the painted thali stays still. Defaults to the
/// low-end heuristic; the Settings switch overrides it (stored on device).
final lowEndProvider = NotifierProvider<LowEndController, bool>(LowEndController.new);

class LowEndController extends Notifier<bool> {
  static const storeKey = 'perf.low_end';
  bool _chosen = false;

  @override
  bool build() {
    Future.microtask(_load);
    return looksLowEnd();
  }

  Future<void> _load() async {
    try {
      final v = await ref.read(keyValueStoreProvider).get(storeKey);
      if (v != null && ref.mounted && !_chosen) state = v == '1';
    } catch (_) {}
  }

  Future<void> set(bool v) async {
    _chosen = true;
    state = v;
    try {
      await ref.read(keyValueStoreProvider).set(storeKey, v ? '1' : '0');
    } catch (_) {}
  }
}
