import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/ui.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../kitchen/domain/kitchen_models.dart';
import '../kitchen/presentation/kitchen_widgets.dart';
import '../recipe/application/recipe_providers.dart' show urlLauncherProvider;
import 'cook_audio.dart';
import 'cook_ui.dart';

/// Android's text-to-speech settings (install a Hindi voice there).
const kTtsSettingsIntent = 'intent:#Intent;action=com.android.settings.TTS_SETTINGS;end';

/// K5 recipe in cook mode: ingredients and steps scaled to the ticket's
/// servings, per-step play/pause read-out (hi-IN) at 0.8×–1.2×.
class CookRecipeScreen extends StatelessWidget {
  const CookRecipeScreen({super.key, required this.ticketId, required this.recipeId});

  final String ticketId;
  final String recipeId;

  @override
  Widget build(BuildContext context) => CookScope(
    child: _K5(ticketId: ticketId, recipeId: recipeId),
  );
}

class _K5 extends ConsumerStatefulWidget {
  const _K5({required this.ticketId, required this.recipeId});

  final String ticketId;
  final String recipeId;

  @override
  ConsumerState<_K5> createState() => _K5State();
}

class _K5State extends ConsumerState<_K5> {
  /// The step being read (playing or paused).
  int? _playing;
  bool _paused = false;
  bool _noHindiVoice = false;
  double _rate = 1.0;
  late final CookAudio _audio = ref.read(cookAudioProvider);
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    // Never keep talking in the background.
    _life = AppLifecycleListener(onPause: _stopAll, onHide: _stopAll);
  }

  void _stopAll() {
    if (_playing == null) return;
    _audio.stop();
    if (mounted) setState(() => _playing = null);
  }

  @override
  void dispose() {
    _life?.dispose();
    if (_playing != null) _audio.stop();
    super.dispose();
  }

  Future<void> _toggle(CookRecipe r, int i) async {
    if (_playing == i) {
      if (_paused) {
        setState(() => _paused = false);
        await _audio.resume();
      } else {
        setState(() => _paused = true);
        await _audio.pause();
      }
      return;
    }
    setState(() {
      _playing = i;
      _paused = false;
    });
    void ended() {
      if (mounted && _playing == i && !_paused) setState(() => _playing = null);
    }

    final started = await _audio.play(
      text: r.spokenStep(i),
      url: r.audioUrl(i),
      rate: _rate,
      onDone: ended,
      onError: () {
        ended();
        if (mounted) BToast.show(context, AppLocalizations.of(context).cookAudioError);
      },
    );
    if (!mounted || started == AudioStart.playing) return;
    setState(() {
      _playing = null;
      _noHindiVoice = started == AudioStart.noHindiVoice;
    });
    if (started == AudioStart.failed) BToast.show(context, AppLocalizations.of(context).cookAudioError);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ticket = ref.watch(cookTicketProvider(widget.ticketId)).value;
    final async = ticket == null
        ? null
        : ref.watch(cookRecipeProvider((widget.ticketId, widget.recipeId, ticket.servingsInt)));
    final r = async?.value;
    void back() => context.canPop() ? context.pop() : context.go(Routes.cookTicket(widget.ticketId));

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CookHeader(
            title: r?.detail.name ?? '',
            subtitle: r == null ? null : l.cookServings('${r.detail.servings}'),
            onBack: back,
          ),
          Expanded(
            child: r == null
                ? Center(
                    child: async?.hasError ?? false
                        ? Text(l.cookLoadError, style: BText.body(CookType.body, weight: FontWeight.w700))
                        : const CircularProgressIndicator(color: BColors.green),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    children: [
                      if (_noHindiVoice) ...[
                        KitchenCard(
                          key: const ValueKey('cook-no-hindi-voice'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(l.cookHindiVoiceMissing, style: BText.body(CookType.body, weight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(
                                l.cookHindiVoiceHint,
                                style: BText.body(CookType.min, weight: FontWeight.w600, color: BColors.ink3),
                              ),
                              const SizedBox(height: 10),
                              CookActionButton(
                                key: const ValueKey('cook-open-tts-settings'),
                                label: l.cookOpenSettings,
                                icon: BIcons.settings,
                                secondary: true,
                                onPressed: () => ref.read(urlLauncherProvider)(Uri.parse(kTtsSettingsIntent)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        l.cookSpeed,
                        style: BText.body(CookType.label, weight: FontWeight.w800, color: BColors.ink3),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (final (i, (rate, label)) in [
                            (0.8, l.cookSpeedSlow),
                            (1.0, l.cookSpeedNormal),
                            (1.2, l.cookSpeedFast),
                          ].indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: BChip(
                                key: ValueKey('speed-$rate'),
                                label: label,
                                height: 48,
                                radius: BRadii.cta,
                                selected: _rate == rate,
                                fill: true,
                                onTap: () => setState(() => _rate = rate),
                                child: Text(label, style: BText.body(CookType.min, weight: FontWeight.w800)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.cookIngredients,
                        style: BText.body(CookType.label, weight: FontWeight.w800, color: BColors.ink3),
                      ),
                      const SizedBox(height: 6),
                      KitchenCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final i in r.detail.ingredients)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  '• ${i.scaledText}',
                                  style: BText.body(CookType.label, weight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.cookSteps,
                        style: BText.body(CookType.label, weight: FontWeight.w800, color: BColors.ink3),
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < r.detail.steps.length; i++) ...[
                        KitchenCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StepNumber(i + 1),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      i < r.stepsHi.length && r.stepsHi[i].isNotEmpty
                                          ? r.stepsHi[i]
                                          : r.detail.steps[i],
                                      style: BText.body(CookType.body, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              CookActionButton(
                                key: ValueKey('step-play-$i'),
                                label: _playing == i && !_paused ? l.cookPause : l.cookPlay,
                                icon: _playing == i && !_paused ? BIcons.pause : BIcons.play,
                                secondary: _playing != i || _paused,
                                onPressed: () => _toggle(r, i),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
