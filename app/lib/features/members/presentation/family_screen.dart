import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/router/startup_gate.dart' show onboardingProvider;
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../labels/labels.dart';
import '../../../ui/ui.dart';
import '../application/members_controller.dart';

/// S2 — "Ghar mein kaun kaun hai?" (prototype "FAMILY", step 1 of 2).
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(membersProvider);
    final status = ref.watch(membersStatusProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Haldi header with rounded bottom (scrolls with the list so
                // large text never squeezes the members out).
                Container(
                  padding: EdgeInsets.fromLTRB(20, 20 + topInset, 20, 22),
                  decoration: const BoxDecoration(
                    color: BColors.haldi,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(BRadii.header)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StepPills(step: 1, label: l.stepOneOfTwo),
                      const SizedBox(height: 14),
                      Semantics(
                        header: true,
                        child: Text(l.familyTitle, style: BText.display(BType.h1Family, height: 1.05)),
                      ),
                      const SizedBox(height: 6),
                      Text(l.familyBody, style: BText.body(BType.body, color: BColors.ink2)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (members.isEmpty && status.loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator(color: BColors.green)),
                        )
                      else if (members.isEmpty && status.error != null) ...[
                        Text(
                          l.membersLoadError,
                          textAlign: TextAlign.center,
                          style: BText.body(BType.body, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: BChip(
                            key: const ValueKey('members-retry'),
                            label: l.retry,
                            onTap: () => ref.read(membersProvider.notifier).refresh(),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else if (members.isEmpty) ...[
                        Text(
                          l.membersEmpty,
                          key: const ValueKey('members-empty'),
                          style: BText.body(BType.body, color: BColors.ink3),
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (var i = 0; i < members.length; i++) ...[
                        MemberTile(
                          key: ValueKey(members[i].id),
                          index: i,
                          name: members[i].name,
                          initial: members[i].initial,
                          color: members[i].color,
                          dietLabel: l.diet(members[i].diet),
                          summary: l.memberSummary(members[i]),
                          onTap: () => context.push(Routes.prefs(members[i].id)),
                        ),
                        const SizedBox(height: 10),
                      ],
                      BDashedButton(
                        key: const ValueKey('member-add'),
                        label: l.addMember,
                        onPressed: () async {
                          final ctrl = ref.read(membersProvider.notifier);
                          final used = {for (final m in members) m.name};
                          final name = await showAddMemberDialog(
                            context,
                            suggestions: [
                              for (final t in ref.read(membersRepositoryProvider).suggestions)
                                if (!used.contains(t.name)) t.name,
                            ],
                          );
                          if (name == null || !context.mounted) return;
                          try {
                            final m = await ctrl.addMember(name);
                            if (context.mounted) unawaited(context.push(Routes.prefs(m.id)));
                          } catch (_) {
                            if (context.mounted) BToast.show(context, l.memberSaveError);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
            decoration: const BoxDecoration(
              color: BColors.card,
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: BCta(
              label: l.familyCta(members.length),
              onPressed: members.isEmpty
                  ? null
                  : () {
                      ref.read(onboardingProvider.notifier).markDone();
                      context.go(Routes.loading);
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/// Onboarding progress: two 22×6 pills (done = ink, todo = ink 20%) and an
/// eyebrow label (12/800, .08em).
class StepPills extends StatelessWidget {
  const StepPills({super.key, required this.step, required this.label, this.total = 2});

  final int step;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              Container(
                width: 22,
                height: 6,
                decoration: BoxDecoration(
                  color: i <= step ? BColors.ink : BColors.inkA(.2),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const SizedBox(width: 4),
            Text(label, style: BText.eyebrow()),
          ],
        ),
      ),
    );
  }
}

/// "Member jodo": a name field with the prototype's POOL names as one-tap
/// suggestions. Returns the name, or null when cancelled.
Future<String?> showAddMemberDialog(BuildContext context, {required List<String> suggestions}) {
  final l = AppLocalizations.of(context);
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: BColors.card,
        title: Text(l.addMemberTitle, style: BText.display(BType.display22)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('member-name'),
                controller: c,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                },
                decoration: InputDecoration(hintText: l.addMemberHint, counterText: ''),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l.addMemberSuggestions,
                  style: BText.body(BType.caption, weight: FontWeight.w700, color: BColors.ink3),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in suggestions)
                      BChip(
                        key: ValueKey('member-suggest-$n'),
                        label: n,
                        selected: c.text.trim() == n,
                        onTap: () => setState(() => c.text = n),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          TextButton(
            key: const ValueKey('member-add-confirm'),
            onPressed: c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()),
            child: Text(l.addMemberCta),
          ),
        ],
      ),
    ),
  );
}
