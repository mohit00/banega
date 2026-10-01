import 'dart:convert';
import 'dart:io';

import 'package:banega/core/router/routes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// English values that may equal the Hinglish template: proper nouns, dish
/// and cuisine names, words Indian English uses as-is, and pure formats.
const _sameInEnglish = {
  'addLabel', 'addedLabel', 'aiMaharajBadge', 'allergenDairy', 'appTitle', 'authOtpDevCode', 'back', //
  'chatMenuPill', 'chatName', 'chatOptionsWhy', 'chatSend', 'chatVoice', 'constraintJain', 'constraintLowSugar',
  'cookChipLabel', 'cookKindFamily', 'cookKindHired', 'cookNotes', 'cookOnDuty', 'cookOpenRecipe',
  'cookSpeedNormal', 'cuisineBengali', 'cuisineGujarati', 'cuisineIndoChinese', 'cuisineMaharashtrian',
  'cuisineNorthIndian', 'cuisineRajasthani', 'cuisineSouthIndian', 'demoDataPill', 'detailMeta', 'dietEgg',
  'dietJain', 'dietJainFriendly', 'dietNonveg', 'dietPescatarian', 'dietVeg', 'eventExpiry', 'fitTweakNote',
  'galleryTitle', 'heroMeta', 'inboxTitle', 'langEnglish', 'langHindi', 'langHinglish', 'minBadge',
  'needHighProtein', 'needKidFriendly', 'needLowOil', 'needLowSugar', 'needNoMaida', 'paywallTitle',
  'planServingsValue', 'prefsSave', 'quickAskProtein', 'rationNoteHint', 'rationStatusApproved',
  'rationStatusPending', 'rationTabApproved', 'rationTabPending', 'rationTitle', 'settingsCookBackup',
  'settingsCookPhone', 'settingsCookPrimary', 'settingsDemoCook', 'settingsNotifications', 'settingsRatings',
  'settingsTitle', 'slotDinner', 'slotLunch', 'slotTiffin', 'spiceMedium', 'stepOneOfTwo', 'stockCatDryFruits',
  'stockFilterLowOut', 'stockLevelIn', 'stockLevelLow', 'stockLevelOut', 'subStatusTrial', 'ticketDishes',
  'ticketNotes', 'ticketTitle', 'verdictPerfect', 'verdictTweak', 'videoRecipe', 'weeklyTop', 'whyProtein',
  'wordmark', 'settingsDisplay',
};

Map<String, dynamic> _arb(String name) =>
    (jsonDecode(File('lib/core/l10n/arb/$name').readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  test('every English string is translated (or allow-listed)', () {
    final hl = _arb('app_hi_Latn.arb');
    final en = _arb('app_en.arb');
    final untranslated = [
      for (final e in en.entries)
        if (!e.key.startsWith('@') && hl[e.key] == e.value && !_sameInEnglish.contains(e.key)) e.key,
    ];
    expect(untranslated, isEmpty, reason: 'app_en.arb values still in Hinglish');
    final missing = [
      for (final k in hl.keys)
        if (!k.startsWith('@') && !en.containsKey(k)) k,
    ];
    expect(missing, isEmpty);
  });

  testWidgets('an en-US device sees English on Splash', (tester) async {
    await pumpBanega(tester, Routes.splash, device: const Locale('en', 'US'));
    expect(find.text('Set up your home'), findsOneWidget);
    expect(find.text('Try it with a demo family'), findsOneWidget);
    expect(find.text("What's cooking\ntoday?"), findsOneWidget);
    expect(find.text('Apna ghar set karo'), findsNothing);
  });

  testWidgets('an en-US device sees English on Home', (tester) async {
    await pumpBanega(tester, Routes.home, tall: true, device: const Locale('en', 'US'));
    expect(find.text('Options for Lunch'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Family'), findsWidgets);
    expect(find.text('AFTERNOON LUNCH'), findsOneWidget);
    expect(find.textContaining('ke options'), findsNothing);
  });
}
