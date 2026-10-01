import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/kitchen_labels.dart';
import '../../../ui/ui.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../application/account_providers.dart';
import '../domain/account_models.dart';

/// S14 rate sheet: one prompt per meal (FR-F1), each eater gets bura / theek
/// / bahut accha (+ one optional note); kids are rated on their behalf
/// (proxy). A family cook's meal leads with thanks and asks "Kya badlein
/// agli baar?" (appreciation-first). Posts one rating per dish per eater.
Future<bool> showRateSheet(BuildContext context, WidgetRef ref, Ticket t) async {
  final l = AppLocalizations.of(context);
  final ratings = await showModalBottomSheet<List<RatingInput>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BColors.paper,
    builder: (ctx) => _RateSheet(ticket: t),
  );
  if (ratings == null || ratings.isEmpty || !context.mounted) return false;
  try {
    await ref.read(accountActionsProvider).rate(t.id, ratings);
    if (context.mounted) BToast.show(context, l.rateDone);
    return true;
  } on KitchenError catch (e) {
    if (context.mounted) BToast.show(context, e.isConflict ? l.toastConflict : l.toastError);
  } catch (_) {
    if (context.mounted) BToast.show(context, l.toastError);
  }
  return false;
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.ticket});

  final Ticket ticket;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  final Map<String, RatingScore> _scores = {};
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _familyCook => widget.ticket.assignee?.kind == CookKind.family;

  List<RatingInput> _inputs() => [
    for (final e in widget.ticket.eaters)
      if (_scores[e.memberId] case final s?)
        for (final d in widget.ticket.dishes)
          RatingInput(recipeId: d.recipeId, memberId: e.memberId, score: s, note: _note.text),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = widget.ticket;
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    // Appreciation first for a family cook: the happy choice leads.
    final order = _familyCook ? RatingScore.values.reversed.toList() : RatingScore.values;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_familyCook && t.assignee != null) ...[
                Text(
                  l.rateThanksFamily(t.assignee!.name),
                  key: const ValueKey('rate-thanks'),
                  style: BText.display(BType.section),
                ),
                const SizedBox(height: 4),
                Text(l.rateTitle(l.slotKey(t.slot)), style: BText.body(BType.body, weight: FontWeight.w700)),
              ] else
                Text(l.rateTitle(l.slotKey(t.slot)), style: BText.display(BType.section)),
              const SizedBox(height: 4),
              Text(
                [t.dishes.map((d) => d.name).join(', '), l.rateHint].join(' · '),
                style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink3),
              ),
              const SizedBox(height: 12),
              for (final e in t.eaters) ...[
                Row(
                  children: [
                    BAvatar(
                      initial: e.name.isEmpty ? '?' : e.name.characters.first.toUpperCase(),
                      color: e.colour,
                      size: 30,
                      fontSize: 12,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.name, style: BText.body(BType.body, weight: FontWeight.w800)),
                    ),
                    if (e.isKid) BBadge(key: ValueKey('rate-proxy-${e.memberId}'), label: l.rateProxy),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final (i, s) in order.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _Choice(
                          key: ValueKey('rate-${e.memberId}-${s.value}'),
                          score: s,
                          label: l.ratingScore(s),
                          selected: _scores[e.memberId] == s,
                          onTap: () => setState(
                            () => _scores[e.memberId] == s ? _scores.remove(e.memberId) : _scores[e.memberId] = s,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const ValueKey('rate-note'),
                controller: _note,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _familyCook ? l.rateNoteHintFamily : l.rateNoteHint,
                  filled: true,
                  fillColor: BColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(BRadii.cta)),
                ),
              ),
              const SizedBox(height: 14),
              BCta(
                key: const ValueKey('rate-submit'),
                label: _familyCook ? l.rateSubmitFamily : l.rateSubmit,
                onPressed: () {
                  final inputs = _inputs();
                  if (inputs.isEmpty) {
                    BToast.show(context, l.rateNeedOne);
                    return;
                  }
                  Navigator.pop(context, inputs);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the three faces.
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.score, required this.label, required this.selected, required this.onTap});

  final RatingScore score;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (score) {
      RatingScore.bura => (BColors.noBg, BColors.noFg),
      RatingScore.theek => (BColors.tweakBg, BColors.tweakFg),
      RatingScore.bahutAccha => (BColors.fitBg, BColors.fitFg),
    };
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? bg : BColors.card,
          borderRadius: BorderRadius.circular(BRadii.cta),
          border: Border.all(color: selected ? fg : BColors.chipBorder, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 26, height: 26, child: CustomPaint(painter: _FacePainter(score, fg))),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: BText.body(BType.caption, weight: FontWeight.w800, color: selected ? fg : BColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple face: frown / flat / smile.
class _FacePainter extends CustomPainter {
  _FacePainter(this.score, this.color);

  final RatingScore score;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1.5;
    canvas.drawCircle(c, r, p);
    final eye = Paint()..color = color;
    canvas.drawCircle(c + Offset(-r * .38, -r * .25), 1.8, eye);
    canvas.drawCircle(c + Offset(r * .38, -r * .25), 1.8, eye);
    final y = c.dy + r * .38;
    final path = Path()..moveTo(c.dx - r * .42, y);
    switch (score) {
      case RatingScore.bura:
        path.quadraticBezierTo(c.dx, y - r * .35, c.dx + r * .42, y);
      case RatingScore.theek:
        path.lineTo(c.dx + r * .42, y);
      case RatingScore.bahutAccha:
        path.quadraticBezierTo(c.dx, y + r * .4, c.dx + r * .42, y);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.score != score || old.color != color;
}
