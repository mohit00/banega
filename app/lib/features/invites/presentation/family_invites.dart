import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/network/app_error.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../ui/ui.dart';
import '../../auth/domain/auth_models.dart' show normalizeIndianPhone;
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/presentation/kitchen_widgets.dart';
import '../../members/application/members_controller.dart';
import '../../members/domain/member.dart';
import '../application/invites_providers.dart';
import '../domain/invite_models.dart';

String _day(DateTime? d) => d == null ? '' : '${d.day}/${d.month}';

/// Settings → "Banega par parivaar" (admin): pending invites (masked phone,
/// expiry, revoke) and "Parivaar ke kisi ko bulao".
class FamilyInvitesCard extends ConsumerWidget {
  const FamilyInvitesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final invites = ref.watch(pendingInvitesProvider).value ?? const <Invite>[];
    final members = {for (final m in ref.watch(membersProvider)) m.id: m.name};

    Future<void> revoke(Invite i) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.inviteRevoke),
          content: Text(l.inviteRevokeAsk),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.settingsCancel)),
            TextButton(
              key: const ValueKey('invite-revoke-yes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.inviteRevoke, style: const TextStyle(color: BColors.noFg)),
            ),
          ],
        ),
      );
      if (yes != true) return;
      try {
        await ref.read(inviteActionsProvider).revoke(i.id);
        if (context.mounted) BToast.show(context, l.inviteRevoked);
      } catch (_) {
        if (context.mounted) BToast.show(context, l.toastError);
      }
    }

    return KitchenCard(
      key: const ValueKey('settings-invites'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.invitesHint,
            style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink3),
          ),
          const SizedBox(height: 8),
          if (invites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l.invitesEmpty,
                key: const ValueKey('invites-empty'),
                style: BText.body(BType.chip, weight: FontWeight.w600, color: BColors.ink3),
              ),
            ),
          for (final i in invites)
            Padding(
              key: ValueKey('invite-${i.id}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.invitePendingRow(i.phoneMasked, _day(i.expiresAt)),
                          style: BText.body(BType.body, weight: FontWeight.w700),
                        ),
                        if (members[i.memberId] case final name?)
                          Text(l.inviteFor(name), style: BText.body(BType.caption, color: BColors.ink3)),
                      ],
                    ),
                  ),
                  BChip(
                    key: ValueKey('invite-revoke-${i.id}'),
                    label: l.inviteRevoke,
                    foreground: BColors.noFg,
                    onTap: () => revoke(i),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          BGhostButton(
            key: const ValueKey('settings-invite'),
            label: l.inviteCta,
            leading: BIcons.plus,
            onPressed: () => showInviteSheet(context),
          ),
        ],
      ),
    );
  }
}

Future<void> showInviteSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: BColors.paper,
  builder: (ctx) => const InviteSheet(),
);

/// "Parivaar ke kisi ko bulao": who (an existing profile or a new member),
/// their phone, then the code to share on WhatsApp.
class InviteSheet extends ConsumerStatefulWidget {
  const InviteSheet({super.key});

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  static const _newMember = '__new__';
  final _phone = TextEditingController();
  final _name = TextEditingController();
  String? _who;
  bool _busy = false;
  String? _error;
  CreatedInvite? _created;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  List<Member> _candidates() {
    final me = ref.read(meProvider).value;
    return [
      for (final m in ref.watch(membersProvider))
        if (!m.isKid && m.id != me?.memberId) m,
    ];
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final phone = normalizeIndianPhone(_phone.text);
    if (phone == null) return setState(() => _error = l.authPhoneInvalid);
    final isNew = _who == _newMember;
    if (isNew && _name.text.trim().isEmpty) return setState(() => _error = l.inviteNameRequired);
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var memberId = isNew ? null : _who;
      if (isNew) memberId = (await ref.read(membersProvider.notifier).addMember(_name.text.trim())).id;
      final created = await ref.read(inviteActionsProvider).create(phone: phone, memberId: memberId);
      if (mounted) setState(() => _created = created);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (appErrorCode(e)) {
            'phone_in_other_household' => l.inviteErrPhoneTaken,
            'validation_error' || 'invalid_phone' => l.authPhoneInvalid,
            _ => e is OfflineError ? l.offlineBanner : l.toastError,
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
        child: SingleChildScrollView(child: _created == null ? _form(context) : _code(context, _created!)),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final l = AppLocalizations.of(context);
    final candidates = _candidates();
    _who ??= candidates.isEmpty ? _newMember : candidates.first.id;
    return Column(
      key: const ValueKey('invite-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.inviteCta, style: BText.display(BType.display22)),
        const SizedBox(height: 14),
        Text(l.inviteWho, style: BText.body(BType.chip, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in candidates)
              BChip(
                key: ValueKey('invite-who-${m.id}'),
                label: m.name,
                selected: _who == m.id,
                onTap: () => setState(() => _who = m.id),
              ),
            BChip(
              key: const ValueKey('invite-who-new'),
              label: l.inviteNewMember,
              selected: _who == _newMember,
              onTap: () => setState(() => _who = _newMember),
            ),
          ],
        ),
        if (_who == _newMember) ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('invite-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.inviteNewName),
          ),
        ],
        const SizedBox(height: 14),
        Text(l.invitePhone, style: BText.body(BType.chip, weight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('+91', style: BText.body(BType.cta, weight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('invite-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                style: BText.body(BType.cta, weight: FontWeight.w700),
                decoration: InputDecoration(hintText: l.authPhoneHint),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(l.inviteRoleNote, style: BText.body(BType.caption, color: BColors.ink3)),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const ValueKey('invite-error'),
            style: BText.body(BType.captionL, weight: FontWeight.w700, color: BColors.noFg),
          ),
        ],
        const SizedBox(height: 16),
        BCta(
          key: const ValueKey('invite-create'),
          label: l.inviteCreate,
          trailing: BIcons.arrowRight,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }

  Widget _code(BuildContext context, CreatedInvite inv) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('invite-created'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.inviteCodeTitle, style: BText.display(BType.display22)),
        const SizedBox(height: 14),
        Semantics(
          label: l.inviteCodeLabel(inv.code.split('').join(' ')),
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: BColors.card,
                borderRadius: BorderRadius.circular(BRadii.tile),
                border: Border.all(color: BColors.green, width: 1.5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  inv.code,
                  key: const ValueKey('invite-code'),
                  style: BText.display(40).copyWith(letterSpacing: 8, color: BColors.green),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(l.inviteCodeBody(inv.phoneMasked), style: BText.body(BType.body, color: BColors.ink2)),
        if (inv.expiresAt != null) ...[
          const SizedBox(height: 4),
          Text(
            l.inviteCodeExpires(_day(inv.expiresAt)),
            style: BText.body(BType.caption, weight: FontWeight.w700, color: BColors.ink3),
          ),
        ],
        const SizedBox(height: 16),
        BCta(
          key: const ValueKey('invite-share'),
          label: l.inviteShareWhatsApp,
          trailing: BIcons.share,
          onPressed: () => ref.read(shareTextProvider)(inv.shareText.isEmpty ? inv.code : inv.shareText),
        ),
        const SizedBox(height: 8),
        BGhostButton(
          key: const ValueKey('invite-copy'),
          label: l.inviteCopy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: inv.code));
            if (context.mounted) BToast.show(context, l.inviteCopied);
          },
        ),
        const SizedBox(height: 4),
        BTextButton(key: const ValueKey('invite-done'), label: l.inviteDone, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
