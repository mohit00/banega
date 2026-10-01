import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../labels/kitchen_labels.dart';
import '../../ui/ui.dart';
import '../kitchen/application/kitchen_providers.dart';
import '../kitchen/data/ticket_cache.dart' show QueuedMutation;
import '../kitchen/domain/kitchen_models.dart';
import '../kitchen/presentation/kitchen_widgets.dart';
import 'cook_ui.dart';

/// K6 cook ↔ family thread on a ticket. [cook] true → cook-mode scale and
/// language; the family side opens the same thread from ticket detail.
class TicketThreadScreen extends StatelessWidget {
  const TicketThreadScreen({super.key, required this.ticketId, this.cook = false});

  final String ticketId;
  final bool cook;

  @override
  Widget build(BuildContext context) {
    final body = _Thread(ticketId: ticketId, cook: cook);
    return cook ? CookScope(child: body) : body;
  }
}

class _Thread extends ConsumerStatefulWidget {
  const _Thread({required this.ticketId, required this.cook});

  final String ticketId;
  final bool cook;

  @override
  ConsumerState<_Thread> createState() => _ThreadState();
}

class _ThreadState extends ConsumerState<_Thread> {
  final _input = TextEditingController();
  bool _sending = false;

  /// The draft's Idempotency-Key: kept while the same text is retried, so a
  /// resend after a timeout never posts it twice.
  String? _draftKey;
  String? _draftText;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final actions = widget.cook ? ref.read(cookTicketActionsProvider) : ref.read(familyTicketActionsProvider);
    try {
      if (_draftText != text) {
        _draftText = text;
        _draftKey = ref.read(idempotencyKeyProvider)();
      }
      final sent = await actions.sendMessage(widget.ticketId, text, key: _draftKey);
      _draftKey = null;
      _draftText = null;
      // Cleared only once it is sent or safely queued (kept on failure).
      if (mounted && _input.text.trim() == text) _input.clear();
      if (!sent && mounted) BToast.show(context, l.cookQueued);
    } catch (_) {
      if (mounted) BToast.show(context, widget.cook ? l.cookError : l.toastError);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cook = widget.cook;
    final async = ref.watch(threadProvider((widget.ticketId, cook)));
    final msgs = async.value ?? const <TicketMessage>[];
    final queued = cook
        ? (ref.watch(queuedMessagesProvider(widget.ticketId)).value ?? const [])
        : const <QueuedMutation>[];
    final size = cook ? CookType.body : BType.body;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    void back() => context.canPop()
        ? context.pop()
        : context.go(cook ? Routes.cookTicket(widget.ticketId) : Routes.ticket(widget.ticketId));

    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cook)
            CookHeader(title: l.cookThread, onBack: back)
          else
            KitchenHeader(title: l.ticketAskCook, titleSize: BType.display26, onBack: back),
          Expanded(
            child: msgs.isEmpty && queued.isEmpty
                ? Center(
                    child: Text(
                      async.isLoading ? '' : l.cookThreadEmpty,
                      style: BText.body(size, weight: FontWeight.w600, color: BColors.ink3),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in msgs) _Bubble(text: m.text, meta: _meta(m), mine: m.fromCook == cook, size: size),
                      for (final q in queued)
                        _Bubble(
                          key: ValueKey('queued-${q.key}'),
                          text: q.text ?? '',
                          meta: l.cookNotSent,
                          mine: true,
                          size: size,
                          pending: true,
                        ),
                    ],
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
            decoration: const BoxDecoration(
              color: BColors.card,
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('thread-input'),
                    controller: _input,
                    style: BText.body(size),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: l.cookThreadHint,
                      filled: true,
                      fillColor: BColors.paper,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BRadii.cta),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                BIconButton(
                  key: const ValueKey('thread-send'),
                  icon: BIcons.send,
                  semanticLabel: l.cookSend,
                  size: cook ? 56 : BSizes.iconButton,
                  background: BColors.green,
                  iconColor: BColors.card,
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _meta(TicketMessage m) => [m.author, if (m.at != null) hmAmPm(m.at!)].join(' · ');
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.text,
    required this.meta,
    required this.mine,
    required this.size,
    this.pending = false,
  });

  final String text;
  final String meta;
  final bool mine;
  final double size;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? BColors.ink : BColors.card,
          borderRadius: BorderRadius.circular(BRadii.tile),
          border: mine ? null : Border.all(color: BColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: BText.body(size, weight: FontWeight.w600, color: mine ? BColors.card : BColors.ink),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              pending
                  ? KitchenTag(label: meta, large: size > BType.body)
                  : Text(
                      meta,
                      style: BText.body(
                        size >= CookType.body ? CookType.min : BType.caption,
                        color: mine ? BColors.greenHeroText : BColors.ink4,
                      ),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
