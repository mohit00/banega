import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// What [CookAudio.play] managed to start.
enum AudioStart {
  /// Speaking / playing; `onDone` or `onError` will follow.
  playing,

  /// No hi-IN voice on the device and no server audio for this step: the
  /// screen asks the cook to install a Hindi voice.
  noHindiVoice,

  /// Could not start at all (engine error).
  failed,
}

/// Per-step read-out for K5. On-device Hindi TTS first (works offline, per
/// F-10-01); the server's `audio.steps_hi` URL when the device has no hi-IN
/// voice or TTS fails.
///
/// Pause: server audio pauses and resumes in place. TTS engines cannot
/// resume mid-sentence on Android, so a paused TTS step restarts from its
/// beginning on resume.
abstract interface class CookAudio {
  /// Plays one step at [rate] (0.8–1.2). Exactly one of [onDone] / [onError]
  /// fires afterwards (also on cancel), so the UI never sticks on "Pause".
  Future<AudioStart> play({
    required String text,
    String? url,
    required double rate,
    required VoidCallback onDone,
    VoidCallback? onError,
  });

  Future<void> pause();

  /// Continues after [pause] (server audio in place; TTS restarts the step).
  Future<void> resume();

  Future<void> stop();
}

final cookAudioProvider = Provider<CookAudio>((ref) {
  final a = DeviceCookAudio();
  ref.onDispose(a.dispose);
  return a;
});

class DeviceCookAudio implements CookAudio {
  DeviceCookAudio({FlutterTts? tts, AudioPlayer Function()? player}) : _newPlayer = player {
    _tts = tts;
  }

  FlutterTts? _tts;
  final AudioPlayer Function()? _newPlayer;
  AudioPlayer? _player;
  StreamSubscription<void>? _done;
  bool? _hindiVoice;

  // The step being read, for resume / callbacks.
  String? _text;
  double _rate = 1;
  VoidCallback? _onDone;
  VoidCallback? _onError;
  bool _usingPlayer = false;
  bool _paused = false;

  FlutterTts get tts => _tts ??= FlutterTts();

  /// flutter_tts rates: 0.5 is normal speech on iOS, 1.0 on Android.
  static double ttsRate(double rate) => defaultTargetPlatform == TargetPlatform.iOS ? rate * .5 : rate;

  static bool _ok(Object? r) => r == null || r == 1 || r == true;

  /// Whether a hi-IN voice is installed (cached).
  Future<bool> hasHindiVoice() async {
    if (_hindiVoice != null) return _hindiVoice!;
    try {
      final v = await tts.isLanguageAvailable('hi-IN');
      _hindiVoice = v == true || v == 1;
    } catch (_) {
      _hindiVoice = false;
    }
    return _hindiVoice!;
  }

  void _finish({bool error = false}) {
    // Stopping the engine to pause fires its cancel handler: the step is
    // not over, keep the callbacks for resume.
    if (_paused) return;
    final cb = error ? (_onError ?? _onDone) : _onDone;
    _onDone = null;
    _onError = null;
    cb?.call();
  }

  Future<bool> _speak() async {
    try {
      final lang = await tts.setLanguage('hi-IN');
      if (!_ok(lang)) return false;
      await tts.setSpeechRate(ttsRate(_rate));
      tts.setCompletionHandler(() => _finish());
      tts.setCancelHandler(() => _finish());
      tts.setErrorHandler((_) => _finish(error: true));
      final r = await tts.speak(_text!);
      return _ok(r);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AudioStart> play({
    required String text,
    String? url,
    required double rate,
    required VoidCallback onDone,
    VoidCallback? onError,
  }) async {
    await stop();
    _text = text;
    _rate = rate;
    _onDone = onDone;
    _onError = onError;
    _paused = false;
    final hindi = await hasHindiVoice();
    if (hindi) {
      _usingPlayer = false;
      if (await _speak()) return AudioStart.playing;
    }
    if (url == null) {
      _onDone = null;
      _onError = null;
      return hindi ? AudioStart.failed : AudioStart.noHindiVoice;
    }
    try {
      _usingPlayer = true;
      final p = _player ??= (_newPlayer?.call() ?? AudioPlayer());
      await _done?.cancel();
      _done = p.onPlayerComplete.listen((_) => _finish());
      await p.setPlaybackRate(rate);
      await p.play(UrlSource(url));
      return AudioStart.playing;
    } catch (_) {
      _onDone = null;
      _onError = null;
      return AudioStart.failed;
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    try {
      if (_usingPlayer) {
        await _player?.pause();
      } else {
        await _tts?.stop();
      }
    } catch (_) {}
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    try {
      if (_usingPlayer) {
        await _player?.resume();
      } else if (_text != null && !await _speak()) {
        _finish(error: true);
      }
    } catch (_) {
      _finish(error: true);
    }
  }

  @override
  Future<void> stop() async {
    _onDone = null;
    _onError = null;
    _paused = false;
    try {
      await _tts?.stop();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    _done?.cancel();
    _player?.dispose();
    _tts?.stop();
  }
}
