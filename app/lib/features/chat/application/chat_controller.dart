import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../data/data_source.dart';
import '../../home/home_providers.dart';
import '../../members/application/members_controller.dart';
import '../../recipe/domain/recipe.dart';
import '../data/api_chat_repository.dart';
import '../data/chat_repository.dart';
import '../data/demo_chat_repository.dart';
import '../domain/chat_models.dart';

final demoChatRepositoryProvider = Provider<ChatRepository>((ref) => const DemoChatRepository());

/// The API chat client. Kept separate from [chatRepositoryProvider] so its
/// session survives rebuilds of [chatRepositoryProvider].
final apiChatRepositoryProvider = Provider<ApiChatRepository>(
  (ref) => ApiChatRepository(ref.watch(dioProvider), now: ref.watch(clockProvider)),
);

/// The active chat repository: the demo sandbox or the API (never a silent
/// switch between them).
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  if (ref.watch(dataSourceProvider) == DataSource.demo) return ref.watch(demoChatRepositoryProvider);
  return ref.watch(apiChatRepositoryProvider);
});

@immutable
class ChatState {
  const ChatState({required this.messages, this.thinking = false});

  /// Oldest first.
  final List<ChatMessage> messages;

  /// A reply is on its way (prototype `state.thinking`): sending is blocked.
  final bool thinking;

  /// Show the standalone "rotiyaan sek raha hoon…" row: thinking and no
  /// partial reply (cards) has arrived yet.
  bool get showTyping => thinking && !(messages.isNotEmpty && messages.last.pending);

  ChatState copyWith({List<ChatMessage>? messages, bool? thinking}) =>
      ChatState(messages: messages ?? this.messages, thinking: thinking ?? this.thinking);
}

/// Maharaj chat (prototype `messages` / `send()`): starts with the welcome
/// and its four chips, appends the user's bubble, then the bot reply as it
/// streams in, and moves Home's slot to the one Maharaj answered for.
final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  int _seq = 0;

  @override
  ChatState build() => ChatState(
    messages: [ChatMessage(id: _seq++, role: ChatRole.bot, text: const WelcomeText(), chipSet: ChipSet.welcome)],
  );

  Future<void> send(String query) async {
    final text = query.trim();
    if (text.isEmpty || state.thinking) return;
    state = state.copyWith(messages: [...state.messages, ChatMessage.me(_seq++, text)], thinking: true);

    final repo = ref.read(chatRepositoryProvider);
    final botId = _seq++;
    Slot? replySlot;
    try {
      await for (final r in repo.ask(
        text,
        slot: ref.read(slotProvider),
        members: ref.read(membersProvider),
        date: ref.read(planDateProvider),
      )) {
        if (!ref.mounted) return;
        _put(ChatMessage.fromReply(botId, r));
        if (r.complete) replySlot = r.slot;
      }
    } catch (_) {
      if (!ref.mounted) return;
      _put(ChatMessage(id: botId, role: ChatRole.bot, text: const ErrorText()));
    }
    if (!ref.mounted) return;
    // A partial reply whose stream ended early still stops "pending".
    final last = state.messages.last;
    if (last.id == botId && last.pending) {
      _put(ChatMessage(id: botId, role: ChatRole.bot, text: last.text, cards: last.cards, chips: last.chips));
    }
    state = state.copyWith(thinking: false);
    if (replySlot != null) ref.read(slotProvider.notifier).select(replySlot);
  }

  /// Offline banner / error retry: re-asks the last question when its answer
  /// failed.
  Future<void> retry() async {
    final msgs = state.messages;
    if (state.thinking || msgs.length < 2) return;
    final last = msgs.last;
    final ask = msgs[msgs.length - 2];
    if (last.text is! ErrorText || ask.role != ChatRole.me) return;
    final t = ask.text;
    if (t is! PlainText) return;
    final q = t.text;
    state = state.copyWith(messages: msgs.sublist(0, msgs.length - 2));
    await send(q);
  }

  /// Inserts or replaces the bot message [m].
  void _put(ChatMessage m) {
    final msgs = state.messages;
    state = state.copyWith(
      messages: msgs.isNotEmpty && msgs.last.id == m.id ? [...msgs.take(msgs.length - 1), m] : [...msgs, m],
    );
  }
}
