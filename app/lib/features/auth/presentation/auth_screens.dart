import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/network/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../ui/ui.dart';
import '../application/auth_controller.dart';
import '../application/session.dart';
import '../domain/auth_models.dart';

/// The OTP challenge the phone screen started (OTP screen reads it).
final otpChallengeProvider = NotifierProvider<OtpChallengeHolder, OtpChallenge?>(OtpChallengeHolder.new);

class OtpChallengeHolder extends Notifier<OtpChallenge?> {
  @override
  OtpChallenge? build() => null;

  void set(OtpChallenge? c) => state = c;
}

/// Haldi header (rounded bottom, like Family) + body + a bottom CTA bar.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.body,
    required this.children,
    required this.cta,
    this.onBack,
  });

  final String title;
  final String body;
  final List<Widget> children;
  final Widget cta;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, 16 + topInset, 20, 22),
            decoration: const BoxDecoration(
              color: BColors.haldi,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(BRadii.header)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onBack != null) ...[
                  BIconButton(
                    icon: BIcons.chevronLeft,
                    semanticLabel: l.back,
                    background: BColors.card.withValues(alpha: .55),
                    onPressed: onBack,
                  ),
                  const SizedBox(height: 12),
                ],
                Semantics(header: true, child: Text(title, style: BText.display(BType.h1Family, height: 1.05))),
                const SizedBox(height: 6),
                Text(body, style: BText.body(BType.body, color: BColors.ink2)),
              ],
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 22, 16, 18), children: children),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
            decoration: const BoxDecoration(
              color: BColors.card,
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: cta,
          ),
        ],
      ),
    );
  }
}

const _inputBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(BRadii.cta)),
  borderSide: BorderSide(color: BColors.chipBorder, width: 1.5),
);

const _focusBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(BRadii.cta)),
  borderSide: BorderSide(color: BColors.green, width: 1.5),
);

String _errorText(AppLocalizations l, Object e) => switch (e) {
  OfflineError() => l.offlineBanner,
  final AppError a when a.messageEn != null || a.messageHi != null => a.messageEn ?? a.messageHi!,
  _ => l.toastError,
};

// ---------------------------------------------------------------- phone

/// "Apna number": +91 and a 10-digit field, "OTP bhejo".
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final phone = normalizeIndianPhone(_c.text);
    if (phone == null) {
      setState(() => _error = l.authPhoneInvalid);
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ch = await ref.read(authControllerProvider.notifier).requestOtp(phone);
      ref.read(otpChallengeProvider.notifier).set(ch);
      if (mounted) unawaited(context.push(Routes.otp));
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.authPhoneTitle,
      body: l.authPhoneBody,
      onBack: context.canPop() ? () => context.pop() : null,
      cta: BCta(
        key: const ValueKey('auth-send-otp'),
        label: l.authSendOtp,
        trailing: BIcons.arrowRight,
        onPressed: _busy ? null : _send,
      ),
      children: [
        Row(
          children: [
            Container(
              height: BSizes.input + 8,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BColors.card,
                borderRadius: BorderRadius.circular(BRadii.cta),
                border: Border.all(color: BColors.chipBorder, width: 1.5),
              ),
              child: Text('+91', style: BText.body(BType.cta, weight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('auth-phone'),
                controller: _c,
                autofocus: true,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                onSubmitted: (_) => _send(),
                style: BText.body(BType.cta, weight: FontWeight.w700),
                cursorColor: BColors.green,
                decoration: InputDecoration(
                  hintText: l.authPhoneHint,
                  hintStyle: BText.body(BType.body, color: BColors.ink4),
                  filled: true,
                  fillColor: BColors.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  enabledBorder: _inputBorder,
                  focusedBorder: _focusBorder,
                  border: _inputBorder,
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const ValueKey('auth-error'),
            style: BText.body(BType.captionL, weight: FontWeight.w700, color: BColors.noFg),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- otp

/// Six boxes over one hidden field; resend after 30 s. When the backend runs
/// in dev mode it returns the code (`dev_code`) and the screen shows it, in
/// debug and release builds alike: a production backend never sends it, and
/// without it a release APK could not sign in against a dev server (no SMS).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, this.showDevCode = true});

  final bool showDevCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _len = 6;
  final _c = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _left = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer(ref.read(otpChallengeProvider)?.resendAfter ?? 30);
    _c.addListener(() {
      setState(() {});
      if (_c.text.length == _len) _verify();
    });
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _left = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final ch = ref.read(otpChallengeProvider);
    if (ch == null || _busy || _c.text.length != _len) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verify(ch.phone, _c.text);
      final next = await ref.read(sessionProvider.notifier).afterSignIn();
      if (mounted) context.go(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is KitchenError || e is UnauthorizedError ? l.authOtpWrong : _errorText(l, e);
        _c.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final ch = ref.read(otpChallengeProvider);
    if (ch == null || _left > 0) return;
    final l = AppLocalizations.of(context);
    try {
      final next = await ref.read(authControllerProvider.notifier).requestOtp(ch.phone);
      ref.read(otpChallengeProvider.notifier).set(next);
      if (mounted) setState(() => _startTimer(next.resendAfter));
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ch = ref.watch(otpChallengeProvider);
    final digits = _c.text;
    return _AuthScaffold(
      title: l.authOtpTitle,
      body: l.authOtpBody(ch?.phone ?? ''),
      onBack: () => context.canPop() ? context.pop() : context.go(Routes.phone),
      cta: BCta(
        key: const ValueKey('auth-verify'),
        label: l.authVerify,
        trailing: BIcons.arrowRight,
        onPressed: _busy || digits.length != _len ? null : _verify,
      ),
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focus.requestFocus,
          child: Stack(
            children: [
              // The real input: invisible, drives the six boxes.
              Opacity(
                opacity: 0,
                child: SizedBox(
                  height: 56,
                  child: TextField(
                    key: const ValueKey('auth-otp'),
                    controller: _c,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_len)],
                    showCursor: false,
                  ),
                ),
              ),
              IgnorePointer(
                child: Row(
                  children: [
                    for (var i = 0; i < _len; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          label: l.authOtpDigit(i + 1),
                          value: i < digits.length ? digits[i] : '',
                          child: Container(
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: BColors.card,
                              borderRadius: BorderRadius.circular(BRadii.cta),
                              border: Border.all(
                                color: i == digits.length && _focus.hasFocus ? BColors.green : BColors.chipBorder,
                                width: 1.5,
                              ),
                            ),
                            child: Text(i < digits.length ? digits[i] : '', style: BText.display(BType.display22)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const ValueKey('auth-error'),
            style: BText.body(BType.captionL, weight: FontWeight.w700, color: BColors.noFg),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _left > 0
                  ? Text(
                      l.authOtpResendIn(_left),
                      key: const ValueKey('auth-resend-wait'),
                      style: BText.body(BType.captionL, weight: FontWeight.w600, color: BColors.ink3),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: BTextButton(
                        key: const ValueKey('auth-resend'),
                        label: l.authOtpResend,
                        color: BColors.green,
                        onPressed: _resend,
                      ),
                    ),
            ),
            BTextButton(
              label: l.authChangeNumber,
              onPressed: () => context.canPop() ? context.pop() : context.go(Routes.phone),
            ),
          ],
        ),
        if (widget.showDevCode && ch?.devCode != null) ...[
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('auth-dev-code'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: BColors.tweakBg, borderRadius: BorderRadius.circular(BRadii.small)),
            child: Text(
              l.authOtpDevCode(ch!.devCode!),
              style: BText.body(BType.captionL, weight: FontWeight.w800, color: BColors.tweakFg),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- household

/// First login without a household: name it ("… Parivaar"), then Family.
class CreateHouseholdScreen extends ConsumerStatefulWidget {
  const CreateHouseholdScreen({super.key});

  @override
  ConsumerState<CreateHouseholdScreen> createState() => _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends ConsumerState<CreateHouseholdScreen> {
  TextEditingController? _c;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // " Parivaar" with the cursor in front: typing the surname gives
    // "Sharma Parivaar".
    _c ??= TextEditingController.fromValue(
      TextEditingValue(
        text: ' ${AppLocalizations.of(context).householdCreateSuffix}',
        selection: const TextSelection.collapsed(offset: 0),
      ),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final name = _c!.text.trim();
    if (name.isEmpty || name == l.householdCreateSuffix) {
      setState(() => _error = l.householdNameRequired);
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).createHousehold(name);
      if (mounted) context.go(Routes.family);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _AuthScaffold(
      title: l.householdCreateTitle,
      body: l.householdCreateBody,
      cta: BCta(
        key: const ValueKey('household-create'),
        label: l.householdCreateCta,
        trailing: BIcons.arrowRight,
        onPressed: _busy ? null : _create,
      ),
      children: [
        TextField(
          key: const ValueKey('household-name'),
          controller: _c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _create(),
          style: BText.body(BType.cta, weight: FontWeight.w700),
          cursorColor: BColors.green,
          decoration: const InputDecoration(
            filled: true,
            fillColor: BColors.card,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            enabledBorder: _inputBorder,
            focusedBorder: _focusBorder,
            border: _inputBorder,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const ValueKey('auth-error'),
            style: BText.body(BType.captionL, weight: FontWeight.w700, color: BColors.noFg),
          ),
        ],
      ],
    );
  }
}
