import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models.dart';
import '../../../ui/ui.dart';
import '../../home/home_screen.dart' show recipeCardData;
import '../../members/application/members_controller.dart';
import '../../menu/application/day_menu.dart';
import '../application/chat_controller.dart';
import '../domain/chat_models.dart';
import 'chat_labels.dart';

/// S6 — Maharaj chat (prototype CHAT): haldi header, bubbles with recipe
/// mini-cards and follow-up chips, the "rotiyaan sek raha hoon…" row and the
/// input bar. [initialQuery] (`/chat?q=`) is sent on open.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _draft = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(chatControllerProvider.notifier).send(q);
      });
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? q]) {
    final text = q ?? _draft.text;
    if (text.trim().isEmpty || ref.read(chatControllerProvider).thinking) return;
    if (q == null) _draft.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  static final _inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(BRadii.cta),
    borderSide: const BorderSide(color: BColors.chipBorder, width: 1.5),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final chat = ref.watch(chatControllerProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Newest first: the list is reversed so it sticks to the bottom
    // (the prototype's `flex-direction: column-reverse`).
    final items = <Widget>[
      if (chat.showTyping) const TypingIndicator(key: ValueKey('typing')),
      for (final m in chat.messages.reversed) _MessageView(key: ValueKey('msg-${m.id}'), message: m, onAsk: _send),
    ];
    return Scaffold(
      backgroundColor: BColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ChatHeader(),
          OfflineBanner(onRetry: () => ref.read(chatControllerProvider.notifier).retry()),
          Expanded(
            child: ListView.separated(
              reverse: true,
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, i) => items[i],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 16 + bottomInset),
            decoration: const BoxDecoration(
              color: BColors.card,
              border: Border(top: BorderSide(color: BColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: l.chatInputLabel,
                    child: TextField(
                      controller: _draft,
                      focusNode: _focus,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: BText.body(BType.body),
                      cursorColor: BColors.green,
                      decoration: InputDecoration(
                        hintText: l.chatPlaceholder,
                        hintStyle: BText.body(BType.body, color: BColors.ink4),
                        filled: true,
                        fillColor: BColors.paper,
                        isDense: true,
                        constraints: const BoxConstraints.tightFor(height: BSizes.input),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        enabledBorder: _inputBorder,
                        focusedBorder: _inputBorder,
                        border: _inputBorder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InputButton(
                  label: l.chatVoice,
                  icon: BIcons.mic,
                  color: BColors.paper,
                  iconColor: BColors.ink,
                  onPressed: () => BToast.show(context, l.voiceToast),
                ),
                const SizedBox(width: 8),
                _InputButton(
                  label: l.chatSend,
                  icon: BIcons.arrowRight,
                  color: BColors.green,
                  iconColor: BColors.card,
                  strokeWidth: 2.4,
                  shadow: BShadows.send,
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Haldi header: back → Home, bobbing chef on an ink circle, "Maharaj",
/// "{n} logon ki pasand yaad hai" with a green dot, and "Menu · {n}" → Plan.
class _ChatHeader extends ConsumerWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(membersProvider);
    final menu = ref.watch(activeMenuProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      color: BColors.haldi,
      padding: EdgeInsets.fromLTRB(14, 12 + topInset, 14, 12),
      child: Row(
        children: [
          BIconButton(
            icon: BIcons.chevronLeft,
            semanticLabel: l.back,
            background: BColors.card.withValues(alpha: .55),
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          const SizedBox(width: 10),
          Bob(
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: BColors.ink, shape: BoxShape.circle),
              child: const BIcon(BIcons.chef, size: 22, color: BColors.haldi),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.chatName, style: BText.body(BType.memberName, weight: FontWeight.w800)),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: BColors.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        l.chatMemory(members.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BText.body(BType.caption, weight: FontWeight.w600, color: BColors.ink2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (menu.isNotEmpty) ...[
            const SizedBox(width: 10),
            Pressable(
              onTap: () => context.push(Routes.plan),
              semanticLabel: l.chatMenuPill(menu.length),
              builder: (context, pressed) => PressScale(
                pressed: pressed,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: BColors.green, borderRadius: BorderRadius.circular(BRadii.small)),
                  child: ExcludeSemantics(
                    child: Text(
                      l.chatMenuPill(menu.length),
                      style: BText.body(BType.caption, weight: FontWeight.w800, color: BColors.card),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One message: the bubble (or the typing row while its text is pending),
/// then its recipe mini-cards and follow-up chips. Rises in once.
class _MessageView extends ConsumerWidget {
  const _MessageView({super.key, required this.message, required this.onAsk});

  final ChatMessage message;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final m = message;
    final memberCount = ref.watch(membersProvider.select((ms) => ms.length));
    final text = m.text == null ? null : l.replyText(m.text!, memberCount: memberCount);
    final chips = m.chipSet != null ? l.chips(m.chipSet!) : [for (final c in m.chips) l.localizeChip(c)];
    return Entrance.rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.isMe)
            _MeBubble(text: text ?? '')
          else if (m.pending && text == null)
            const TypingIndicator()
          else if (text != null)
            _BotBubble(text: text),
          if (m.cards.isNotEmpty) ...[const SizedBox(height: 10), _CardRow(cards: m.cards)],
          if (!m.isMe && chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(50, 0, 14, 0),
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    BChip(
                      label: chips[i],
                      height: 34,
                      borderColor: BColors.green,
                      foreground: BColors.greenDark,
                      onTap: () => onAsk(chips[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// User bubble: ink, white 14/600, right-aligned, max 78%, 16/16/4/16.
class _MeBubble extends StatelessWidget {
  const _MeBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: c.maxWidth * .78),
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
            color: BColors.ink,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
            ),
          ),
          child: Text(
            text,
            style: BText.body(BType.body, weight: FontWeight.w600, color: BColors.card, height: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Bot bubble: 28px ink chef avatar + white bordered bubble (max 82%,
/// 16/16/16/4), 14/500, line height 1.45, newlines kept (`pre-line`).
class _BotBubble extends StatelessWidget {
  const _BotBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: BColors.ink, shape: BoxShape.circle),
              child: const BIcon(BIcons.chef, size: 15, color: BColors.haldi, strokeWidth: 2.2),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: c.maxWidth * .82),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: BColors.card,
                  border: Border.all(color: BColors.border),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: Text(text, style: BText.body(BType.body, height: 1.45)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of [RecipeMiniCard]s under a bot reply (padding 2/14/6/50,
/// gap 10). ADD toggles the day menu; tapping a card opens Detail.
class _CardRow extends ConsumerWidget {
  const _CardRow({required this.cards});

  final List<RecipeCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final menu = ref.watch(activeMenuProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(50, 2, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            RecipeMiniCard(
              key: ValueKey('mini-${cards[i].id}'),
              index: i,
              data: recipeCardData(l, cards[i]),
              added: menu.any((e) => e.id == cards[i].id),
              onOpen: () => context.push(Routes.recipe(cards[i].id)),
              onToggle: () => ref.read(dayMenuProvider.notifier).toggle(cards[i].id, cards[i].name),
            ),
          ],
        ],
      ),
    );
  }
}

/// 48px, 14-radius input-bar button: the paper mic, and the green send with
/// its 3px `#095A29` ledge.
class _InputButton extends StatelessWidget {
  const _InputButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onPressed,
    this.strokeWidth,
    this.shadow = const [],
  });

  final String label;
  final BIconData icon;
  final Color color;
  final Color iconColor;
  final double? strokeWidth;
  final List<BoxShadow> shadow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      builder: (context, pressed) => Container(
        width: BSizes.input,
        height: BSizes.input,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(BRadii.cta), boxShadow: shadow),
        child: BIcon(icon, size: 20, color: iconColor, strokeWidth: strokeWidth),
      ),
    );
  }
}
