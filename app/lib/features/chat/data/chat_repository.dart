import '../../members/domain/member.dart';
import '../../recipe/domain/recipe.dart';
import '../domain/chat_models.dart';

/// Maharaj chat. Two implementations: [DemoChatRepository] (the prototype's
/// rule-based reply() over the seed recipes and the local engine) and
/// [ApiChatRepository] (POST /v1/chat/…); pick one through
/// `chat_controller.dart`'s `chatRepositoryProvider`.
abstract interface class ChatRepository {
  /// Answers [text]. Yields partial replies (cards before text) and ends with
  /// a [ChatReply.complete] one. [slot] is the slot Home is showing; the
  /// reply's `slot` is the one Maharaj answered for. [members] and [date] feed
  /// the local engine in demo mode.
  Stream<ChatReply> ask(String text, {required Slot slot, required List<Member> members, DateTime? date});
}
