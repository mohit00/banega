import 'package:flutter/widgets.dart' show Locale;

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

  /// Server chips arrive in the request language; an older server (or an
  /// admin-edited config without translations) sends Hinglish. Known
  /// Hinglish chips are shown in the app's language; anything else as is.
  String localizeChip(String chip) {
    final hl = lookupAppLocalizations(const Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn'));
    if (localeName == hl.localeName) return chip;
    final key = chip.trim().toLowerCase();
    final pairs = <(String, String)>[
      (hl.chatChipLunch, chatChipLunch),
      (hl.chatChipHalkaDinner, chatChipHalkaDinner),
      (hl.chatChipNashta, chatChipNashta),
      (hl.chatChipMehmaan, chatChipMehmaan),
      (hl.followProteinNashta, followProteinNashta),
      (hl.followTiffin, followTiffin),
      (hl.followSouth, followSouth),
      (hl.followHalka, followHalka),
      (hl.followBaarish, followBaarish),
      (hl.followPaneer, followPaneer),
      (hl.followDadi, followDadi),
      (hl.quickAsk15Min, quickAsk15Min),
      (hl.quickAskHalka, quickAskHalka),
      (hl.quickAskBaarish, quickAskBaarish),
      (hl.quickAskTiffin, quickAskTiffin),
      (hl.quickAskMehmaan, quickAskMehmaan),
      (hl.quickAskProtein, quickAskProtein),
    ];
    for (final (source, translated) in pairs) {
      if (source.trim().toLowerCase() == key) return translated;
    }
    return chip;
  }

  List<String> chips(ChipSet s) => switch (s) {
    ChipSet.welcome => [chatChipLunch, chatChipHalkaDinner, chatChipNashta, chatChipMehmaan],
    ChipSet.followNashta => [followProteinNashta, followTiffin, followSouth],
    ChipSet.followMeal => [followHalka, followBaarish, followPaneer, followDadi],
  };
}
