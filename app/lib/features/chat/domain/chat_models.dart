// Chat view models shared by the demo and API chat repositories.
import 'package:flutter/foundation.dart';

import '../../../data/models.dart';
import '../../members/domain/member.dart';
import '../../recipe/domain/recipe.dart';

/// Wire value (`nashta` / `lunch` / `dinner`, also `b` / `l` / `d`) → [Slot].
Slot? slotFromWire(Object? v) => switch (v) {
  'nashta' || 'breakfast' || 'b' => Slot.breakfast,
  'lunch' || 'l' => Slot.lunch,
  'dinner' || 'd' => Slot.dinner,
  _ => null,
};

/// Why a demo reply picked its recipes (prototype `why[]`), rendered per
/// locale by the chat screen.
enum WhyKind { halka, protein, mehmaan, baarish, kid, quick, paneer, cuisine, member }

@immutable
class WhyTag {
  const WhyTag(this.kind, {this.cuisine, this.name});
  final WhyKind kind;

  /// For [WhyKind.cuisine].
  final Cuisine? cuisine;

  /// For [WhyKind.member].
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is WhyTag && other.kind == kind && other.cuisine == cuisine && other.name == name;

  @override
  int get hashCode => Object.hash(kind, cuisine, name);
}

/// A bot message's text: literal from the API, or a template the app
/// renders per locale (demo replies, the welcome, fallbacks).
sealed class ReplyText {
  const ReplyText();
}

/// Free text from the backend.
class PlainText extends ReplyText {
  const PlainText(this.text);
  final String text;
}

/// "Namaste! Main Maharaj hoon. Ghar ke {n} logon ki pasand…" — the count
/// is read live from the household.
class WelcomeText extends ReplyText {
  const WelcomeText();
}

/// "Is combo mein exact match nahi mila. {slot} ke liye ye sabse kareeb hain:"
class NoMatchText extends ReplyText {
  const NoMatchText(this.slot);
  final Slot slot;
}

/// "{slot} ke liye {n} options — {why}.\n{k} mein poora parivaar kha sakta
/// hai. {constraintLine}."
class OptionsText extends ReplyText {
  const OptionsText({
    required this.slot,
    required this.count,
    this.why = const [],
    required this.allOk,
    required this.members,
  });

  final Slot slot;
  final int count;
  final List<WhyTag> why;

  /// Options the whole family can eat.
  final int allOk;

  /// Household snapshot the constraint line is built from.
  final List<Member> members;
}

/// Shown when the reply failed (not a connection error).
class ErrorText extends ReplyText {
  const ErrorText();
}

/// Localized chip sets (prototype welcome chips and slot follow-ups).
enum ChipSet { welcome, followNashta, followMeal }

/// Prototype follow-ups: nashta gets its own three, lunch/dinner share four.
ChipSet followUpsFor(Slot slot) => slot == Slot.breakfast ? ChipSet.followNashta : ChipSet.followMeal;

/// One step of a bot reply. The API yields cards first ([complete] false,
/// [text] null) and then the finished reply; the demo yields once.
@immutable
class ChatReply {
  const ChatReply({
    this.slot,
    this.cards = const [],
    this.chips = const [],
    this.chipSet,
    this.text,
    this.complete = true,
  });

  final Slot? slot;
  final List<RecipeCard> cards;

  /// Literal follow-up chips (API).
  final List<String> chips;

  /// Localized follow-up chips (demo).
  final ChipSet? chipSet;
  final ReplyText? text;
  final bool complete;
}

enum ChatRole { me, bot }

/// One chat bubble plus its cards and chips.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    this.text,
    this.cards = const [],
    this.chips = const [],
    this.chipSet,
    this.pending = false,
  });

  final int id;
  final ChatRole role;
  final ReplyText? text;
  final List<RecipeCard> cards;
  final List<String> chips;
  final ChipSet? chipSet;

  /// Cards are in, the text is still being written.
  final bool pending;

  bool get isMe => role == ChatRole.me;

  factory ChatMessage.me(int id, String text) => ChatMessage(id: id, role: ChatRole.me, text: PlainText(text));

  factory ChatMessage.fromReply(int id, ChatReply r) => ChatMessage(
    id: id,
    role: ChatRole.bot,
    text: r.text,
    cards: r.cards,
    chips: r.chips,
    chipSet: r.chipSet,
    pending: !r.complete,
  );
}
