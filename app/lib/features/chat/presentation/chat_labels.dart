import '../../../core/l10n/gen/app_localizations.dart';
import '../../../labels/labels.dart';
import '../domain/chat_models.dart';

extension ChatLabels on AppLocalizations {
  String why(WhyTag w) => switch (w.kind) {
    WhyKind.halka => whyHalka,
    WhyKind.protein => whyProtein,
    WhyKind.mehmaan => whyMehmaan,
    WhyKind.baarish => whyBaarish,
    WhyKind.kid => whyKid,
    WhyKind.quick => why20Min,
    WhyKind.paneer => whyPaneer,
    WhyKind.cuisine => w.cuisine == null ? '' : cuisine(w.cuisine!),
    WhyKind.member => whyMember(w.name ?? ''),
  };

  /// A bot message's text; [memberCount] feeds the welcome.
  String replyText(ReplyText t, {required int memberCount}) => switch (t) {
    PlainText(:final text) => text,
    WelcomeText() => chatGreeting(memberCount),
    NoMatchText(:final slot) => chatNoMatch(this.slot(slot)),
    ErrorText() => chatError,
    OptionsText() => _options(t),
  };

  String _options(OptionsText t) {
    final options = chatOptions(slot(t.slot), t.count);
    final head = t.why.isEmpty ? options : chatOptionsWhy(options, t.why.map(why).join(', '));
    return '$head.\n${chatFamilyCan(t.allOk)} ${constraintLineFor(t.members)}.';
  }

  List<String> chips(ChipSet s) => switch (s) {
    ChipSet.welcome => [chatChipLunch, chatChipHalkaDinner, chatChipNashta, chatChipMehmaan],
    ChipSet.followNashta => [followProteinNashta, followTiffin, followSouth],
    ChipSet.followMeal => [followHalka, followBaarish, followPaneer, followDadi],
  };
}
