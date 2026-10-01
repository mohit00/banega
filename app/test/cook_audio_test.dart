import 'package:banega/core/router/router.dart';
import 'package:banega/core/router/routes.dart';
import 'package:banega/features/cook_mode/cook_audio.dart';
import 'package:banega/features/kitchen/application/kitchen_providers.dart';
import 'package:banega/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'helpers.dart';

class _FakeTts extends FlutterTts {
  _FakeTts({this.hindi = true, this.languageOk = 1});

  final bool hindi;
  final int languageOk;
  final List<String> calls = [];
  VoidCallback? completion;
  VoidCallback? cancel;

  @override
  Future<dynamic> isLanguageAvailable(String language) async => hindi;

  @override
  Future<dynamic> setLanguage(String language) async => languageOk;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  void setCompletionHandler(VoidCallback callback) => completion = callback;

  @override
  void setCancelHandler(VoidCallback callback) => cancel = callback;

  @override
  void setErrorHandler(ErrorHandler handler) {}

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak:$text');
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
    return 1;
  }
}

/// Records what K5 asks of the audio layer.
class _FakeAudio implements CookAudio {
  _FakeAudio(this.start);

  AudioStart start;
  final List<String> calls = [];
  VoidCallback? done;

  @override
  Future<AudioStart> play({
    required String text,
    String? url,
    required double rate,
    required VoidCallback onDone,
    VoidCallback? onError,
  }) async {
    calls.add('play');
    done = onDone;
    return start;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');
}

Future<String> _openK5(WidgetTester tester, _FakeAudio audio) async {
  final c = await pumpBanega(tester, Routes.home, tall: true, overrides: [cookAudioProvider.overrideWithValue(audio)]);
  final k = c.read(demoKitchenProvider);
  late String id;
  await tester.runAsync(() async {
    var m = await k.putDishes('2026-09-26', 'lunch', ['daltadka']);
    m = await k.patchMenu(m.id, MenuPatch(assigneeCookId: 'c1', assigneeSet: true));
    id = (await k.confirm(m.id, version: m.version, idempotencyKey: 'a')).ticket.id;
  });
  c.read(demoCookRoleProvider.notifier).set('c1');
  c.read(kitchenRevisionProvider.notifier).bump();
  c.read(routerProvider).go(Routes.cookRecipe(id, 'daltadka'));
  await settle(tester);
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceCookAudio', () {
    test('no Hindi voice and no server audio → asks for a Hindi voice', () async {
      final a = DeviceCookAudio(tts: _FakeTts(hindi: false));
      expect(await a.play(text: 'x', rate: 1, onDone: () {}), AudioStart.noHindiVoice);
    });

    test('setLanguage failing is a failure, not silent success', () async {
      final a = DeviceCookAudio(tts: _FakeTts(languageOk: 0));
      expect(await a.play(text: 'x', rate: 1, onDone: () {}), AudioStart.failed);
    });

    test('completion and cancel both end the step (no stuck Pause); pause → resume restarts TTS', () async {
      final tts = _FakeTts();
      final a = DeviceCookAudio(tts: tts);
      var ended = 0;
      expect(await a.play(text: 'Dal dho lo', rate: 1, onDone: () => ended++), AudioStart.playing);
      tts.cancel!();
      expect(ended, 1);
      await a.play(text: 'Tadka lagao', rate: 1, onDone: () => ended++);
      await a.pause();
      tts.cancel?.call(); // the engine's cancel while paused does not end the step
      expect(ended, 1);
      await a.resume();
      expect(tts.calls.where((c) => c == 'speak:Tadka lagao'), hasLength(2));
      tts.completion!();
      expect(ended, 2);
    });
  });

  group('K5', () {
    testWidgets('tap plays, tap again pauses, tap again resumes; backgrounding stops', (tester) async {
      final audio = _FakeAudio(AudioStart.playing);
      await _openK5(tester, audio);
      final step = find.byKey(const ValueKey('step-play-0'));
      await tester.ensureVisible(step);
      await tester.tap(step);
      await tester.pump();
      await tester.tap(step);
      await tester.pump();
      await tester.tap(step);
      await tester.pump();
      expect(audio.calls, ['play', 'pause', 'resume']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(audio.calls.last, 'stop');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('no Hindi voice → install hint with a settings button', (tester) async {
      final audio = _FakeAudio(AudioStart.noHindiVoice);
      await _openK5(tester, audio);
      final step = find.byKey(const ValueKey('step-play-0'));
      await tester.ensureVisible(step);
      await tester.tap(step);
      await settle(tester);
      expect(find.byKey(const ValueKey('cook-no-hindi-voice')), findsOneWidget);
      expect(find.byKey(const ValueKey('cook-open-tts-settings')), findsOneWidget);
    });
  });
}
