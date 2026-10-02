// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'Banega';

  @override
  String get wordmark => 'banega';

  @override
  String get aiMaharajBadge => 'AI महाराज';

  @override
  String get thaliAlt => 'घर की थाली';

  @override
  String get back => 'वापस';

  @override
  String get splashTitle => 'आज खाने\nमें क्या है?';

  @override
  String get splashBody =>
      'हर घर का रोज़ का सवाल। एक AI जो आपके पूरे परिवार की पसंद याद रखता है — और हर खाने के लिए विकल्प देता है।';

  @override
  String get splashCta => 'अपना घर सेट करो';

  @override
  String get splashDemo => 'डेमो परिवार के साथ देखो';

  @override
  String get stepOneOfTwo => 'चरण 1 / 2';

  @override
  String get familyTitle => 'घर में कौन\nकौन है?';

  @override
  String get familyBody => 'हर सदस्य की पसंद अलग। टैप करके सेट करो — महाराज सब याद रखेगा।';

  @override
  String get addMember => 'सदस्य जोड़ो';

  @override
  String familyCta(int count) {
    return '$count लोग · आगे बढ़ो';
  }

  @override
  String spiceSummary(String spice) {
    return '$spice मिर्च';
  }

  @override
  String get prefsStep => 'चरण 2 / 2 · पसंद';

  @override
  String prefsTitle(String name) {
    return '$name की पसंद';
  }

  @override
  String get prefsSubtitle => 'महाराज इसी हिसाब से सुझाएगा';

  @override
  String get prefsDietTitle => 'क्या खाते हैं?';

  @override
  String get prefsSpiceTitle => 'मिर्च कितनी?';

  @override
  String get prefsNeedsTitle => 'कोई ज़रूरत या परहेज़?';

  @override
  String get prefsCuisineTitle => 'पसंदीदा खाना';

  @override
  String prefsSave(String name) {
    return 'सेव करो · $name';
  }

  @override
  String get dietVeg => 'शाकाहारी';

  @override
  String get dietVegHint => 'सिर्फ़ शाकाहारी';

  @override
  String get dietJain => 'जैन';

  @override
  String get dietJainHint => 'बिना प्याज़-लहसुन';

  @override
  String get dietEgg => 'अंडा';

  @override
  String get dietEggHint => 'शाकाहारी + अंडे';

  @override
  String get dietNonveg => 'मांसाहारी';

  @override
  String get dietNonvegHint => 'सब कुछ';

  @override
  String get dietJainFriendly => 'जैन के लिए ठीक';

  @override
  String get spiceKam => 'कम';

  @override
  String get spiceMedium => 'मध्यम';

  @override
  String get spiceTeekha => 'तीखा';

  @override
  String get needLowOil => 'कम तेल';

  @override
  String get needLowSugar => 'कम चीनी';

  @override
  String get needHighProtein => 'ज़्यादा प्रोटीन';

  @override
  String get needNoMaida => 'बिना मैदा';

  @override
  String get needKidFriendly => 'बच्चों के लिए';

  @override
  String get cuisineNorthIndian => 'उत्तर भारतीय';

  @override
  String get cuisineSouthIndian => 'दक्षिण भारतीय';

  @override
  String get cuisineGujarati => 'गुजराती';

  @override
  String get cuisineRajasthani => 'राजस्थानी';

  @override
  String get cuisineBengali => 'बंगाली';

  @override
  String get cuisineMaharashtrian => 'महाराष्ट्रीयन';

  @override
  String get cuisineIndoChinese => 'इंडो-चाइनीज़';

  @override
  String get loadingTitle => 'महाराज आपके घर\nको समझ रहा है…';

  @override
  String constraintLine(String items) {
    return 'ध्यान रखा: $items';
  }

  @override
  String get constraintNone => 'सबकी पसंद ध्यान में है';

  @override
  String constraintJain(String name) {
    return '$name (जैन)';
  }

  @override
  String constraintLowSugar(String name) {
    return '$name (कम चीनी)';
  }

  @override
  String constraintKamMirch(String name) {
    return '$name (कम मिर्च)';
  }

  @override
  String get householdName => 'पुरोहित परिवार';

  @override
  String familyLine(int count, String items) {
    return '$count लोग · $items';
  }

  @override
  String get slotBreakfast => 'नाश्ता';

  @override
  String get slotLunch => 'दोपहर का खाना';

  @override
  String get slotDinner => 'रात का खाना';

  @override
  String get eyebrowBreakfast => 'सुबह का नाश्ता';

  @override
  String get eyebrowLunch => 'दोपहर का खाना';

  @override
  String get eyebrowDinner => 'रात का खाना';

  @override
  String get searchPrefix => 'पूछो';

  @override
  String get tickerAsk1 => '“15 मिनट में नाश्ता”';

  @override
  String get tickerAsk2 => '“दादी के लिए जैन डिनर”';

  @override
  String get tickerAsk3 => '“बारिश वाला खाना”';

  @override
  String get tickerAsk4 => '“Daughter का टिफ़िन”';

  @override
  String get maharajPick => 'महाराज की पसंद';

  @override
  String heroMeta(String fitLabel, int mins) {
    return '$fitLabel · $mins मिनट';
  }

  @override
  String get recipeDekho => 'रेसिपी देखो';

  @override
  String get quickAsk15Min => '15 मिनट में कुछ';

  @override
  String get quickAskHalka => 'कुछ हल्का';

  @override
  String get quickAskBaarish => 'बारिश स्पेशल';

  @override
  String get quickAskTiffin => 'Daughter का टिफ़िन';

  @override
  String get quickAskMehmaan => 'मेहमान आ रहे हैं';

  @override
  String get quickAskProtein => 'ज़्यादा प्रोटीन';

  @override
  String slotOptions(String slot) {
    return '$slot के विकल्प';
  }

  @override
  String get sabkeHisaab => 'सबके हिसाब से';

  @override
  String minBadge(int mins) {
    return '$mins मिनट';
  }

  @override
  String get addLabel => 'जोड़ो';

  @override
  String get addedLabel => 'जुड़ गया';

  @override
  String planBarTitle(int count) {
    return '$count डिश · आज का मेन्यू';
  }

  @override
  String get cookKoBhejo => 'कुक को भेजो';

  @override
  String get navGhar => 'घर';

  @override
  String get navMaharaj => 'महाराज से पूछो';

  @override
  String get navParivaar => 'परिवार';

  @override
  String get chatName => 'महाराज';

  @override
  String chatMemory(int count) {
    return '$count लोगों की पसंद याद है';
  }

  @override
  String chatMenuPill(int count) {
    return 'मेन्यू · $count';
  }

  @override
  String chatGreeting(int count) {
    return 'नमस्ते! मैं महाराज हूँ। घर के $count लोगों की पसंद मुझे याद है।\nबस पूछो — आज क्या बनाऊँ?';
  }

  @override
  String get chatChipLunch => 'आज दोपहर में क्या?';

  @override
  String get chatChipHalkaDinner => 'रात में कुछ हल्का';

  @override
  String get chatChipNashta => '15 मिनट में नाश्ता';

  @override
  String get chatChipMehmaan => 'मेहमान आ रहे हैं';

  @override
  String get chatPlaceholder => 'आज रात के खाने में कुछ हल्का…';

  @override
  String get chatVoice => 'बोलो';

  @override
  String get chatSend => 'भेजो';

  @override
  String get typing => 'रोटियाँ सेक रहा हूँ…';

  @override
  String get voiceToast => 'बोलकर लिखना — असली ऐप में आप हिंदी में बोल सकते हो';

  @override
  String get chatError => 'महाराज अभी जवाब नहीं दे पाए। फिर से पूछो।';

  @override
  String get chatInputLabel => 'महाराज से पूछो';

  @override
  String chatNoMatch(String slot) {
    return 'इस मेल में बिल्कुल सही कुछ नहीं मिला। $slot के लिए ये सबसे क़रीब हैं:';
  }

  @override
  String chatOptions(String slot, int count) {
    return '$slot के लिए $count विकल्प';
  }

  @override
  String chatOptionsWhy(String options, String why) {
    return '$options — $why';
  }

  @override
  String chatFamilyCan(int ok) {
    return '$ok पूरा परिवार खा सकता है।';
  }

  @override
  String get whyHalka => 'हल्का';

  @override
  String get whyProtein => 'ज़्यादा प्रोटीन';

  @override
  String get whyMehmaan => 'मेहमानों के लायक';

  @override
  String get whyBaarish => 'बारिश वाला';

  @override
  String get whyKid => 'बच्चों को पसंद';

  @override
  String get why20Min => '20 मिनट के अंदर';

  @override
  String get whyPaneer => 'पनीर वाला';

  @override
  String whyMember(String name) {
    return '$name के हिसाब से';
  }

  @override
  String get followProteinNashta => 'प्रोटीन वाला नाश्ता';

  @override
  String get followTiffin => 'Daughter का टिफ़िन';

  @override
  String get followSouth => 'कुछ दक्षिण भारतीय';

  @override
  String get followHalka => 'कुछ हल्का';

  @override
  String get followBaarish => 'बारिश स्पेशल';

  @override
  String get followPaneer => 'पनीर वाला कुछ';

  @override
  String get followDadi => 'दादी के लिए क्या?';

  @override
  String get fitAllPerfect => 'सबके लिए बढ़िया';

  @override
  String get fitAllPerfectShort => 'सबके लिए';

  @override
  String fitAllTweak(int count) {
    return 'सबके लिए · $count बदलाव';
  }

  @override
  String fitAllTweakShort(int count) {
    return 'सब · $count बदलाव';
  }

  @override
  String fitPartial(int can, int total) {
    return '$can/$total के लिए';
  }

  @override
  String fitNotFor(String names) {
    return '$names के लिए नहीं';
  }

  @override
  String get fitAllHappy => 'सब ख़ुश, कोई बदलाव नहीं';

  @override
  String fitTweakNote(String name, String note) {
    return '$name: $note';
  }

  @override
  String get reasonOnionGarlic => 'प्याज़-लहसुन है';

  @override
  String get reasonEgg => 'इसमें अंडा है';

  @override
  String get reasonNonveg => 'मांसाहारी है';

  @override
  String get reasonMaida => 'मैदा है';

  @override
  String get reasonLessChilli => 'उनकी कटोरी में कम मिर्च';

  @override
  String get reasonExtraChilli => 'ऊपर से लाल मिर्च / अचार';

  @override
  String get reasonLowSugar => 'हिस्सा छोटा, सलाद ज़्यादा';

  @override
  String get reasonLowOil => 'कम तेल में बनाओ';

  @override
  String get reasonProtein => 'साथ में दही/पनीर';

  @override
  String get reasonKid => 'बच्चे के लिए अलग, हल्का';

  @override
  String get reasonFavCuisine => 'पसंदीदा खाना भी';

  @override
  String get reasonPerfect => 'बिल्कुल सही';

  @override
  String get verdictPerfect => 'बढ़िया';

  @override
  String get verdictTweak => 'थोड़ा बदलो';

  @override
  String get verdictNo => 'नहीं';

  @override
  String detailMeta(String diet, String cuisine, int mins) {
    return '$diet · $cuisine · $mins मिनट';
  }

  @override
  String get kaunKhayega => 'कौन खाएगा';

  @override
  String get saaman => 'सामान';

  @override
  String get kaiseBanega => 'कैसे बनेगा';

  @override
  String get videoRecipe => 'वीडियो रेसिपी';

  @override
  String get menuMeinDaalo => 'मेन्यू में डालो';

  @override
  String get menuMeinHai => 'मेन्यू में है';

  @override
  String planTitle(String slot) {
    return 'आज का $slot मेन्यू';
  }

  @override
  String planSubtitle(int count, String coverage) {
    return '$count लोगों के लिए · $coverage';
  }

  @override
  String get planCoverageAll => 'हर सदस्य के लिए कुछ न कुछ है';

  @override
  String get planCoverageSome => 'कुछ सदस्यों के लिए और डिश चाहिए';

  @override
  String get planEmpty => 'मेन्यू ख़ाली है — घर से डिश जोड़ो।';

  @override
  String get planSaamanList => 'सामान की लिस्ट';

  @override
  String get planSendCook => 'महाराज / कुक को भेजो';

  @override
  String get planOrderMissing => 'कम सामान ऑर्डर करो';

  @override
  String get toastSentCook => 'मेन्यू + सामान लिस्ट कुक को WhatsApp पर भेज दी';

  @override
  String get toastMissingCart => 'कम सामान कार्ट में डाल दिया';

  @override
  String get galleryTitle => 'कंपोनेंट गैलरी';

  @override
  String get dietNoOnionGarlic => 'बिना प्याज़-लहसुन';

  @override
  String get dietNoOnionGarlicHint => 'शाकाहारी, बिना प्याज़-लहसुन';

  @override
  String get dietPescatarian => 'पेस्केटेरियन';

  @override
  String get dietPescatarianHint => 'शाकाहारी + मछली';

  @override
  String reasonAllergen(String item) {
    return '$item से एलर्जी';
  }

  @override
  String get reasonRootVeg => 'ज़मीन के नीचे की सब्ज़ी है';

  @override
  String reasonNonvegItem(String item) {
    return 'इसमें $item है';
  }

  @override
  String get reasonDairy => 'दूध से बनी चीज़ है';

  @override
  String reasonDislikeMain(String item) {
    return 'उनको $item पसंद नहीं';
  }

  @override
  String reasonDislikeSkip(String item) {
    return 'उनकी कटोरी में $item मत डालो';
  }

  @override
  String get reasonVrat => 'आज व्रत है';

  @override
  String get allergenPeanut => 'मूंगफली';

  @override
  String get allergenTreeNut => 'काजू-बादाम';

  @override
  String get allergenDairy => 'दूध की चीज़ें';

  @override
  String get allergenGluten => 'गेहूं (ग्लूटेन)';

  @override
  String get allergenEgg => 'अंडा';

  @override
  String get allergenFish => 'मछली';

  @override
  String get allergenSesame => 'तिल';

  @override
  String get allergenSoy => 'सोया';

  @override
  String get demoDataPill => 'डेमो डेटा';

  @override
  String servingsCount(int count) {
    return '$count लोग';
  }

  @override
  String get servingsLess => 'कम लोग';

  @override
  String get servingsMore => 'ज़्यादा लोग';

  @override
  String get batchWarning => 'इतने लोगों के लिए दो बार में पकाओ';

  @override
  String get homeLoadError => 'विकल्प लोड नहीं हुए';

  @override
  String get retry => 'फिर से कोशिश करो';

  @override
  String get navRasoi => 'रसोई';

  @override
  String get slotTiffin => 'टिफ़िन';

  @override
  String get slotShaam => 'शाम का नाश्ता';

  @override
  String get dateToday => 'आज';

  @override
  String get dateTomorrow => 'कल';

  @override
  String planTitleOn(String day, String slot) {
    return '$day का $slot मेन्यू';
  }

  @override
  String planCoverageMissing(String names) {
    return '$names के लिए और डिश चाहिए';
  }

  @override
  String get planLoadError => 'मेन्यू लोड नहीं हुआ';

  @override
  String get planEatersTitle => 'कौन खा रहा है?';

  @override
  String get planGuestAdults => 'मेहमान · बड़े';

  @override
  String get planGuestKids => 'मेहमान · बच्चे';

  @override
  String get planGuestDiet => 'मेहमान क्या खाते हैं?';

  @override
  String get planServingsTitle => 'कितने लोग';

  @override
  String planServingsValue(String servings) {
    return '$servings लोगों का';
  }

  @override
  String get planServingsHint => 'बड़े 1 · बच्चे ½ · मेहमान जोड़े';

  @override
  String get planDueTitle => 'कब तक';

  @override
  String get planDueHint => 'खाना कितने बजे तक तैयार हो';

  @override
  String get planAssigneeTitle => 'कौन बनाएगा';

  @override
  String get planAssigneeNone => 'कोई नहीं';

  @override
  String cookChipLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get cookKindHired => 'रखे हुए';

  @override
  String get cookKindFamily => 'परिवार';

  @override
  String get cookOffDutyTag => 'छुट्टी';

  @override
  String get planViewTicket => 'टिकट देखो';

  @override
  String get planShareWhatsApp => 'WhatsApp पर भी भेजो';

  @override
  String get removeDish => 'हटाओ';

  @override
  String get toastTicketSent => 'टिकट भेज दिया';

  @override
  String get toastOrderSoon => 'सामान ऑर्डर करना जल्द आ रहा है';

  @override
  String get toastError => 'कुछ गड़बड़ हुई, फिर से कोशिश करो';

  @override
  String get toastConflict => 'टिकट बदल गया था — नया हाल दिखा रहे हैं';

  @override
  String get itemIn => 'है';

  @override
  String get itemLow => 'कम है';

  @override
  String get itemOut => 'खत्म';

  @override
  String get itemUntracked => 'पता नहीं';

  @override
  String get statusNew => 'नया';

  @override
  String get statusUnassigned => 'किसी को नहीं मिला';

  @override
  String get statusAccepted => 'स्वीकार हुआ';

  @override
  String get statusCooking => 'बन रहा है';

  @override
  String get statusReady => 'तैयार';

  @override
  String get statusCompleted => 'हो गया';

  @override
  String get statusNotConfirmed => 'पक्का नहीं हुआ';

  @override
  String get statusCancelled => 'रद्द';

  @override
  String get ticketTitle => 'टिकट';

  @override
  String ticketCardTitle(String slot) {
    return '$slot का टिकट';
  }

  @override
  String dueBy(String time) {
    return 'कब तक $time';
  }

  @override
  String get ticketNoAssignee => 'किसी को नहीं दिया';

  @override
  String ticketGuests(int count) {
    return '+$count मेहमान';
  }

  @override
  String get ticketDishes => 'डिश';

  @override
  String get ticketNotes => 'नोट';

  @override
  String get ticketNotesHint => 'कुक के लिए नोट…';

  @override
  String get ticketChangeLog => 'क्या क्या बदला';

  @override
  String get ticketEdit => 'बदलो';

  @override
  String get ticketSave => 'सेव करो';

  @override
  String get ticketSavedToast => 'टिकट बदल गया';

  @override
  String get ticketCancel => 'रद्द करो';

  @override
  String get ticketCancelReason => 'रद्द क्यों कर रहे हो?';

  @override
  String get ticketCancelReasonHint => 'वजह लिखो';

  @override
  String get ticketCancelConfirm => 'हाँ, रद्द करो';

  @override
  String get ticketKeep => 'रहने दो';

  @override
  String get ticketCancelledToast => 'टिकट रद्द हो गया';

  @override
  String get ticketMarkDone => 'हो गया मार्क करो';

  @override
  String get ticketAskCook => 'कुक से बात करो';

  @override
  String get ticketUpdatedTag => 'बदला गया';

  @override
  String get ticketStockIssueTag => 'सामान खत्म';

  @override
  String get ticketLoadError => 'टिकट लोड नहीं हुआ';

  @override
  String get khanaBanaPrompt => 'खाना बना?';

  @override
  String get khanaBanaHint => 'कुक ने \'बन गया\' नहीं दबाया। बता दो, ताकि हिसाब सही रहे।';

  @override
  String get khanaBanaYes => 'हाँ, बना';

  @override
  String get khanaBanaNo => 'नहीं बना';

  @override
  String get logCreated => 'टिकट बना';

  @override
  String get logAccepted => 'स्वीकार किया';

  @override
  String get logCooking => 'बनाना शुरू';

  @override
  String get logReady => 'तैयार';

  @override
  String get logCompleted => 'हो गया';

  @override
  String get logCancelled => 'रद्द किया';

  @override
  String get logNotConfirmed => 'पक्का नहीं हुआ';

  @override
  String get logUpdated => 'बदला';

  @override
  String get logItemOut => 'सामान ख़त्म';

  @override
  String get logClaimed => 'अपने नाम किया';

  @override
  String get logReassigned => 'दूसरे कुक को दिया';

  @override
  String get logUnassigned => 'किसी को नहीं दिया';

  @override
  String get logAutoCancelled => 'अपने आप रद्द';

  @override
  String get inboxTitle => 'इनबॉक्स';

  @override
  String inboxBellUnread(int count) {
    return 'इनबॉक्स, $count नए';
  }

  @override
  String get inboxEmpty => 'अभी कोई ख़बर नहीं';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get settingsDemoCook => 'डेमो: कुक का रोल';

  @override
  String get settingsDemoCookHint => 'कुक का रोल हो तो नीचे \'रसोई\' टैब दिखेगा (कुक मोड)।';

  @override
  String get cookTitle => 'आज के टिकट';

  @override
  String get cookTabToday => 'आज';

  @override
  String get cookTabTomorrow => 'कल';

  @override
  String cookDueBy(String time) {
    return 'कब तक $time';
  }

  @override
  String get cookActionAccept => 'स्वीकार करो';

  @override
  String get cookActionStart => 'शुरू करो';

  @override
  String get cookActionDone => 'बन गया';

  @override
  String get cookActionReady => 'तैयार';

  @override
  String get cookEmpty => 'कोई टिकट नहीं';

  @override
  String get cookOnDuty => 'ड्यूटी पर';

  @override
  String get cookOffDuty => 'छुट्टी';

  @override
  String cookOffDutyUntil(String date) {
    return '$date तक छुट्टी';
  }

  @override
  String get cookOffDutyAsk => 'कब तक छुट्टी?';

  @override
  String get cookOffDutyToday => 'सिर्फ़ आज';

  @override
  String get cookOffDutyTomorrow => 'कल तक';

  @override
  String get cookOffDutyPick => 'तारीख़ चुनो';

  @override
  String get cookFamilyMode => 'परिवार';

  @override
  String get cookOffline => 'नेट नहीं है — पुरानी जानकारी दिख रही है';

  @override
  String get cookNotSent => 'भेजा नहीं गया';

  @override
  String get cookQueued => 'नेट आने पर भेज देंगे';

  @override
  String get cookDishes => 'क्या बनाना है';

  @override
  String get cookEaters => 'कौन खाएगा';

  @override
  String cookServings(String servings) {
    return '$servings लोगों के लिए';
  }

  @override
  String cookGuests(int count) {
    return '+$count मेहमान';
  }

  @override
  String get cookNotes => 'नोट';

  @override
  String get cookItems => 'ज़रूरी सामान';

  @override
  String get cookItemOut => 'खत्म है';

  @override
  String get cookAskFamily => 'परिवार से पूछो';

  @override
  String get cookOpenRecipe => 'रेसिपी';

  @override
  String get cookIngredients => 'सामान';

  @override
  String get cookSteps => 'कैसे बनाना है';

  @override
  String get cookPlay => 'सुनो';

  @override
  String get cookPause => 'रोको';

  @override
  String get cookSpeed => 'आवाज़ की रफ़्तार';

  @override
  String get cookSpeedSlow => 'धीरे';

  @override
  String get cookSpeedNormal => 'सामान्य';

  @override
  String get cookSpeedFast => 'तेज़';

  @override
  String get cookThread => 'परिवार से बात';

  @override
  String get cookThreadHint => 'संदेश लिखो…';

  @override
  String get cookSend => 'भेजो';

  @override
  String get cookThreadEmpty => 'अभी कोई बात नहीं';

  @override
  String get cookConflict => 'टिकट बदल गया — नया हाल दिखा रहे हैं';

  @override
  String get cookError => 'कुछ गड़बड़ हुई';

  @override
  String get cookLoadError => 'लोड नहीं हुआ — फिर से कोशिश करो';

  @override
  String get stockTitle => 'रसोई स्टॉक';

  @override
  String stockSubtitle(int count, int low) {
    return '$count चीज़ें · $low कम या खत्म';
  }

  @override
  String get stockSearchHint => 'खोजो: दही, प्याज़…';

  @override
  String get stockFilterAll => 'सब';

  @override
  String get stockFilterLowOut => 'कम + खत्म';

  @override
  String get stockAllIn => 'सब है';

  @override
  String get stockAllInDone => 'सब स्टॉक में';

  @override
  String get stockLevelIn => 'है';

  @override
  String get stockLevelLow => 'कम';

  @override
  String get stockLevelOut => 'खत्म';

  @override
  String get stockEmpty => 'कुछ नहीं मिला';

  @override
  String get stockLoadError => 'स्टॉक लोड नहीं हुआ';

  @override
  String get stockCatSabzi => 'सब्ज़ी';

  @override
  String get stockCatDairy => 'दूध-दही';

  @override
  String get stockCatDal => 'दाल';

  @override
  String get stockCatAnaaj => 'आटा-चावल';

  @override
  String get stockCatMasale => 'मसाले';

  @override
  String get stockCatTelGhee => 'तेल-घी';

  @override
  String get stockCatDryFruits => 'मेवे';

  @override
  String get stockCatOther => 'और';

  @override
  String get rationTitle => 'राशन';

  @override
  String get rationTabPending => 'बाकी';

  @override
  String get rationTabApproved => 'मंज़ूर';

  @override
  String get rationTabBought => 'खरीदा';

  @override
  String get rationEmpty => 'कोई माँग नहीं';

  @override
  String rationRaisedBy(String name) {
    return '$name ने माँगा';
  }

  @override
  String rationItems(int count) {
    return '$count चीज़ें';
  }

  @override
  String get rationApprove => 'मंज़ूर करो';

  @override
  String get rationReject => 'मना करो';

  @override
  String get rationNoteHint => 'नोट (ज़रूरी नहीं)';

  @override
  String get rationBought => 'खरीद लिया';

  @override
  String get rationStatusPending => 'बाकी';

  @override
  String get rationStatusApproved => 'मंज़ूर';

  @override
  String get rationStatusRejected => 'मना हुआ';

  @override
  String get rationStatusBought => 'आ गया';

  @override
  String get rationApprovedToast => 'मंज़ूर हो गया';

  @override
  String get rationRejectedToast => 'मना कर दिया';

  @override
  String get rationBoughtToast => 'सामान स्टॉक में आ गया';

  @override
  String get rationSentToast => 'राशन माँग भेज दी';

  @override
  String get rationNothingMissing => 'सब सामान है — कुछ नहीं मँगाना';

  @override
  String get rationSelfApproved => 'खुद मंज़ूर';

  @override
  String get cookRasoi => 'रसोई';

  @override
  String get cookRationAsk => 'राशन माँगो';

  @override
  String get cookRationTitle => 'मेरा राशन';

  @override
  String get cookRationSheetTitle => 'क्या चाहिए?';

  @override
  String get cookRationFreeHint => 'और कुछ? लिखो';

  @override
  String get cookRationAdd => 'जोड़ो';

  @override
  String get cookRationSend => 'भेजो';

  @override
  String get cookRationSent => 'माँग भेज दी';

  @override
  String get cookRationNew => 'नई माँग';

  @override
  String ladderTitle(String item) {
    return '$item खत्म है';
  }

  @override
  String ladderSkipAsk(String item) {
    return 'बिना $item के बना लो?';
  }

  @override
  String get ladderSkipYes => 'हाँ, बिना इसके';

  @override
  String get ladderMoreWays => 'और रास्ते';

  @override
  String get ladderSwapTitle => 'इसकी जगह क्या डालें?';

  @override
  String get ladderSwapDo => 'बदल दो';

  @override
  String get ladderNoSwap => 'कोई सुरक्षित बदली नहीं मिली';

  @override
  String get ladderChangeDish => 'डिश बदलो';

  @override
  String get ladderDishTitle => 'इनमें से क्या बनाएँ?';

  @override
  String get ladderDishPick => 'यह बनाओ';

  @override
  String get ladderNoDish => 'कोई और डिश स्टॉक में नहीं';

  @override
  String get ladderPending => 'परिवार से पूछ रहे हैं…';

  @override
  String ladderPendingHint(int mins) {
    return '$mins मिनट में जवाब नहीं आया तो एडमिन को अलर्ट जाएगा';
  }

  @override
  String get ladderTimeout => 'समय खत्म — एडमिन को अलर्ट गया';

  @override
  String get ladderDone => 'हो गया — टिकट बदल गया';

  @override
  String get ladderRejected => 'परिवार ने मना किया — दूसरा रास्ता चुनो';

  @override
  String get ladderOpen => 'रास्ता देखो';

  @override
  String get ladderClose => 'बंद करो';

  @override
  String get approvalTitle => 'आपकी हाँ चाहिए';

  @override
  String approvalSwap(String detail) {
    return 'सामान बदलो: $detail';
  }

  @override
  String approvalChangeDish(String detail) {
    return 'डिश बदलो: $detail';
  }

  @override
  String approvalAskedBy(String name) {
    return '$name ने पूछा';
  }

  @override
  String approvalExpires(String time) {
    return '$time तक जवाब दो';
  }

  @override
  String get approvalYes => 'हाँ';

  @override
  String get approvalNo => 'नहीं';

  @override
  String get approvalApprovedToast => 'कुक को बता दिया: हाँ';

  @override
  String get approvalRejectedToast => 'कुक को बता दिया: नहीं';

  @override
  String get approvalGone => 'यह सवाल अब खुला नहीं है';

  @override
  String get ticketIssueChoosing => 'कुक रास्ता चुन रहा है';

  @override
  String ticketIssuePending(String detail) {
    return 'कुक ने पूछा: $detail';
  }

  @override
  String get ticketRate => 'कैसा बना?';

  @override
  String get ticketRated => 'रेटिंग दी — शुक्रिया!';

  @override
  String get logSkip => 'बिना सामान के बनाया';

  @override
  String get logSwap => 'सामान बदला';

  @override
  String get logChangeDish => 'डिश बदली';

  @override
  String get logApprovalRequested => 'परिवार से पूछा';

  @override
  String get logApproved => 'परिवार ने हाँ कहा';

  @override
  String get logRejected => 'परिवार ने मना किया';

  @override
  String get logTimeout => 'समय खत्म — एडमिन को अलर्ट';

  @override
  String rateTitle(String slot) {
    return '$slot कैसा बना?';
  }

  @override
  String rateThanksFamily(String name) {
    return '$name ने बनाया — शुक्रिया बोलो!';
  }

  @override
  String get rateHint => 'हर खाने वाले के लिए एक टैप';

  @override
  String get rateBura => 'बुरा';

  @override
  String get rateTheek => 'ठीक';

  @override
  String get rateBahutAccha => 'बहुत अच्छा';

  @override
  String get rateProxy => 'उनकी तरफ से';

  @override
  String get rateNoteHint => 'कुछ कहना है? (ज़रूरी नहीं)';

  @override
  String get rateNoteHintFamily => 'अगली बार क्या बदलें?';

  @override
  String get rateSubmit => 'रेटिंग भेजो';

  @override
  String get rateSubmitFamily => 'शुक्रिया भेजो';

  @override
  String get rateDone => 'शुक्रिया! महाराज याद रखेगा';

  @override
  String get rateNeedOne => 'कम से कम एक रेटिंग दो';

  @override
  String get recipeHomeRating => 'घर की रेटिंग';

  @override
  String recipeRatingValue(String avg, int count) {
    return '$avg/3 · $count रेटिंग';
  }

  @override
  String trialBanner(int days) {
    return 'फ्री ट्रायल · $days दिन बाकी';
  }

  @override
  String get graceBanner => 'पेमेंट अटकी है — 3 दिन में ठीक करो';

  @override
  String get expiredBanner => 'प्लान बंद है — सिर्फ देख सकते हो';

  @override
  String get planBandTitle => 'प्लान बंद है';

  @override
  String get planBandBody =>
      'नया मेन्यू, महाराज चैट और कुक टिकट के लिए ₹50/हफ्ता वाला प्लान चालू करो। आज और कल के टिकट कुक बना सकता है।';

  @override
  String get planBandCta => 'प्लान देखो';

  @override
  String get weeklyTitle => 'इस हफ्ते';

  @override
  String weeklyTop(String name) {
    return 'टॉप: $name';
  }

  @override
  String weeklyOnTime(String pct) {
    return '$pct% समय पर';
  }

  @override
  String weeklyCoverage(String pct) {
    return '$pct% सबके लिए';
  }

  @override
  String weeklyMeals(int count) {
    return '$count खाने बने';
  }

  @override
  String get paywallTitle => 'बनेगा प्लान';

  @override
  String get paywallPrice => '₹50/हफ्ता';

  @override
  String get paywallBody => 'पूरे घर के लिए सब कुछ, एक ही प्लान में।';

  @override
  String get paywallFeature1 => 'हर खाने पर सबके हिसाब से विकल्प';

  @override
  String get paywallFeature2 => 'कुक को टिकट, स्टॉक और राशन';

  @override
  String get paywallFeature3 => 'रेटिंग से महाराज सीखता है';

  @override
  String get paywallSubscribe => '₹50/हफ्ता · चालू करो';

  @override
  String get paywallRestore => 'खरीद वापस लाओ';

  @override
  String get paywallRestored => 'प्लान स्टेटस अपडेट हो गया';

  @override
  String get paywallActive => 'प्लान चालू है';

  @override
  String paywallRenews(String date) {
    return 'अगला रिन्यूअल $date';
  }

  @override
  String paywallTrial(int days) {
    return 'फ्री ट्रायल: $days दिन बाकी';
  }

  @override
  String get paywallGrace => 'पेमेंट अटकी है — स्टोर में ठीक करो';

  @override
  String get paywallSubscribed => 'प्लान चालू! शुक्रिया';

  @override
  String get paywallStoreSoon => 'स्टोर बिलिंग जल्द आ रही है';

  @override
  String get paywallPending => 'पेमेंट पेंडिंग है। पूरा होते ही प्लान चालू हो जाएगा।';

  @override
  String get paywallCancelled => 'खरीद कैंसल हो गई';

  @override
  String get paywallNothingToRestore => 'इस Play अकाउंट पर कोई बनेगा प्लान नहीं मिला';

  @override
  String get paywallCancelNote => 'कभी भी Play Store / App Store से कैंसल करो';

  @override
  String get subStatusTrial => 'फ्री ट्रायल';

  @override
  String get subStatusActive => 'चालू';

  @override
  String get subStatusGrace => 'पेमेंट अटकी';

  @override
  String get subStatusExpired => 'बंद';

  @override
  String get consentTitle => 'आपका डेटा, आपका हक';

  @override
  String get consentBody =>
      'बनेगा आपका फ़ोन नंबर लॉगिन के लिए, और घर के सदस्यों की पसंद, एलर्जी, व्रत के दिन और खाने का इतिहास सिर्फ मेन्यू बनाने, कुक को टिकट भेजने और महाराज के सुझाव के लिए रखता है। डेटा कभी बेचा नहीं जाता। सेटिंग्स से कभी भी अपना अकाउंट डिलीट कर सकते हो; घर का एडमिन पूरे घर का डेटा एक्सपोर्ट या डिलीट कर सकता है।';

  @override
  String get consentLlmNote =>
      'महाराज चैट के सवाल एक AI सेवा (Anthropic Claude) को जाते हैं। फ़ोन नंबर और सेहत से जुड़ी ज़रूरतें कभी नहीं भेजी जातीं; एलर्जी सिर्फ गिनती में, और परिवार के किसी सदस्य का नाम सिर्फ तब जब आप खुद लिखें।';

  @override
  String get consentKids => 'बच्चों की प्रोफ़ाइल आप माता-पिता या अभिभावक की तरह बना रहे हो।';

  @override
  String get consentAccept => 'मान लिया';

  @override
  String get consentPrivacy => 'प्राइवेसी पॉलिसी पढ़ो';

  @override
  String get settingsHousehold => 'घर';

  @override
  String get settingsHouseholdName => 'घर का नाम';

  @override
  String get settingsEdit => 'बदलो';

  @override
  String get settingsSave => 'सेव करो';

  @override
  String get settingsCancel => 'रहने दो';

  @override
  String get settingsSaved => 'सेव हो गया';

  @override
  String get settingsMembers => 'परिवार के सदस्य';

  @override
  String get settingsCooks => 'कुक सेटअप';

  @override
  String get settingsCookPrimary => 'मुख्य';

  @override
  String get settingsCookBackup => 'बैकअप';

  @override
  String get settingsCookRemove => 'हटाओ';

  @override
  String settingsCookRemoveAsk(String name) {
    return '$name को हटाएँ? उनके खुले टिकट किसी को नहीं रहेंगे।';
  }

  @override
  String get settingsAddHiredCook => 'कुक जोड़ो';

  @override
  String get settingsCookName => 'नाम';

  @override
  String get settingsCookPhone => 'फ़ोन नंबर';

  @override
  String settingsCookAdded(String name) {
    return '$name जुड़ गए';
  }

  @override
  String get settingsHiredLimit => 'एक घर में एक ही कुक रखा जा सकता है';

  @override
  String get settingsPhoneTaken => 'यह फ़ोन किसी और घर में है';

  @override
  String get settingsInvalidPhone => 'सही फ़ोन नंबर डालो';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsLanguageHint => 'कुक मोड हिंदी में खुलता है; कुक वहाँ अपनी भाषा चुन सकते हैं';

  @override
  String get langHinglish => 'Hinglish';

  @override
  String get langEnglish => 'English';

  @override
  String get langHindi => 'हिंदी';

  @override
  String get settingsNotifications => 'सूचनाएँ';

  @override
  String get settingsNotifMandatory => 'ज़रूरी — हमेशा चालू';

  @override
  String get settingsRatings => 'रेटिंग';

  @override
  String get settingsRatingsHint => 'खाने के बाद \'कैसा बना?\' पूछो। घर की कुक इसे बंद कर सकती है।';

  @override
  String get settingsAutoDecrement => 'खाने के बाद स्टॉक घटाओ';

  @override
  String get settingsAutoDecrementHint => 'ताज़ा सामान (दही, सब्ज़ी) \'कम\' हो जाएगा';

  @override
  String get settingsShowNames => 'कुक को रेटिंग में नाम दिखाओ';

  @override
  String get settingsShowNamesHint => 'बंद हो तो कुक को सिर्फ औसत दिखता है';

  @override
  String get settingsCookSwaps => 'कुक खुद बदली चुन सकता है';

  @override
  String get settingsCookSwapsHint => 'बंद हो तो हर बदली पर आपकी हाँ चाहिए';

  @override
  String get settingsKitchen => 'रसोई';

  @override
  String get settingsSubscription => 'प्लान';

  @override
  String get settingsPrivacy => 'प्राइवेसी और डेटा';

  @override
  String get settingsConsent => 'सहमति दोबारा पढ़ो';

  @override
  String get settingsGrievance => 'शिकायत के लिए: privacy@banega.app';

  @override
  String get settingsPrivacyPolicy => 'प्राइवेसी पॉलिसी';

  @override
  String get settingsTerms => 'नियम और शर्तें';

  @override
  String get settingsExport => 'मेरा डेटा एक्सपोर्ट करो';

  @override
  String get settingsExportToast => 'इनबॉक्स में लिंक आएगा';

  @override
  String get settingsDeleteHousehold => 'घर डिलीट करो';

  @override
  String get settingsDeleteHouseholdAsk =>
      'पूरे घर का डेटा (सदस्य, मेन्यू, टिकट, रेटिंग, स्टॉक) 7 दिन बाद हमेशा के लिए मिट जाएगा। 7 दिन तक \'वापस लाओ\' से अनडू कर सकते हो। स्टोर सब्सक्रिप्शन अलग से कैंसल करना होगा।';

  @override
  String get settingsDeleteConfirm => 'हाँ, डिलीट करो';

  @override
  String settingsDeletePending(String date) {
    return 'घर $date को डिलीट होगा';
  }

  @override
  String get settingsRestore => 'वापस लाओ';

  @override
  String get settingsRestored => 'घर वापस आ गया';

  @override
  String get settingsDeleteMe => 'मेरा अकाउंट डिलीट करो';

  @override
  String get settingsDeleteMeAsk => 'आपका लॉगिन हट जाएगा; घर और बाकी सदस्य रहेंगे। 7 दिन तक अनडू हो सकता है।';

  @override
  String get settingsDeletedMe => 'अकाउंट डिलीट हो गया — 7 दिन में वापस आ सकते हो';

  @override
  String get eventTicketCreated => 'नया टिकट';

  @override
  String get eventTicketAccepted => 'टिकट स्वीकार हुआ';

  @override
  String get eventTicketUpdated => 'टिकट बदला';

  @override
  String get eventTicketCompleted => 'खाना बन गया';

  @override
  String get eventNotConfirmed => '\'खाना बना?\' सवाल';

  @override
  String get eventCookOffDuty => 'कुक छुट्टी पर';

  @override
  String get eventNoShow => 'कुक ने स्वीकार नहीं किया';

  @override
  String get eventStockLow => 'स्टॉक कम';

  @override
  String get eventRationRequest => 'राशन की माँग';

  @override
  String get eventRationDecided => 'राशन का जवाब';

  @override
  String get eventStockIssue => 'सामान खत्म';

  @override
  String get eventApprovalRequest => 'हाँ/नहीं सवाल';

  @override
  String get eventApprovalDecided => 'हाँ/नहीं जवाब';

  @override
  String get eventStockTimeout => 'जवाब का समय खत्म';

  @override
  String get eventRatePrompt => 'रेटिंग दो';

  @override
  String get eventExpiry => 'प्लान रिमाइंडर';

  @override
  String get eventWeekly => 'हफ्ते की रिपोर्ट';

  @override
  String get eventTomorrow => 'कल के टिकट';

  @override
  String get offlineBanner => 'इंटरनेट नहीं है। पहले वाली जानकारी दिख रही है।';

  @override
  String get offlineRetry => 'फिर से';

  @override
  String get authPhoneTitle => 'अपना नंबर';

  @override
  String get authPhoneBody => 'OTP से लॉगिन होगा। नंबर सिर्फ़ लॉगिन के लिए है।';

  @override
  String get authPhoneHint => '10 अंकों का मोबाइल नंबर';

  @override
  String get authSendOtp => 'OTP भेजो';

  @override
  String get authPhoneInvalid => '10 अंकों का सही नंबर डालो';

  @override
  String get authOtpTitle => 'OTP डालो';

  @override
  String authOtpBody(String phone) {
    return '$phone पर 6 अंकों का कोड भेजा है';
  }

  @override
  String authOtpResendIn(int seconds) {
    return '$seconds सेकंड में दोबारा भेज सकते हो';
  }

  @override
  String get authOtpResend => 'OTP दोबारा भेजो';

  @override
  String authOtpDevCode(String code) {
    return 'डेव कोड: $code';
  }

  @override
  String get authOtpWrong => 'कोड गलत है, फिर से डालो';

  @override
  String authOtpDigit(int index) {
    return 'OTP का $index अंक';
  }

  @override
  String get authVerify => 'आगे बढ़ो';

  @override
  String get authChangeNumber => 'नंबर बदलो';

  @override
  String get householdCreateTitle => 'घर का नाम';

  @override
  String get householdCreateBody => 'यह नाम परिवार और कुक, सबको दिखेगा।';

  @override
  String get householdCreateSuffix => 'परिवार';

  @override
  String get householdCreateCta => 'घर बनाओ';

  @override
  String get householdNameRequired => 'घर का नाम लिखो';

  @override
  String get notFoundTitle => 'यह पेज नहीं मिला';

  @override
  String get notFoundHome => 'घर पर जाओ';

  @override
  String get addMemberTitle => 'नया सदस्य';

  @override
  String get addMemberHint => 'नाम लिखो';

  @override
  String get addMemberSuggestions => 'या इनमें से चुनो';

  @override
  String get addMemberCta => 'जोड़ो';

  @override
  String get commonCancel => 'रहने दो';

  @override
  String get removeMember => 'सदस्य हटाओ';

  @override
  String removeMemberConfirm(String name) {
    return '$name को परिवार से हटाएँ?';
  }

  @override
  String get removeMemberBody => 'उनकी पसंद अब मेन्यू में नहीं गिनी जाएगी।';

  @override
  String get removeMemberYes => 'हाँ, हटाओ';

  @override
  String get membersLoadError => 'परिवार लोड नहीं हुआ';

  @override
  String get membersEmpty => 'अभी कोई सदस्य नहीं। पहला सदस्य जोड़ो।';

  @override
  String get memberSaveError => 'सेव नहीं हुआ, फिर से कोशिश करो';

  @override
  String get prefsKidTitle => 'बच्चा है';

  @override
  String get prefsKidHint => 'आधी सर्विंग गिनी जाएगी';

  @override
  String get prefsAllergensTitle => 'एलर्जी (बिल्कुल नहीं)';

  @override
  String get allergenMilk => 'दूध';

  @override
  String get allergenShellfish => 'झींगा';

  @override
  String get allergenMustard => 'सरसों';

  @override
  String get prefsDislikesTitle => 'पसंद नहीं';

  @override
  String get prefsDislikesHint => 'जैसे बैंगन, करेला';

  @override
  String get prefsDislikeAdd => 'जोड़ो';

  @override
  String prefsDislikeRemove(String item) {
    return '$item हटाओ';
  }

  @override
  String get prefsVratTitle => 'व्रत के दिन';

  @override
  String get weekdayMon => 'सोम';

  @override
  String get weekdayTue => 'मंगल';

  @override
  String get weekdayWed => 'बुध';

  @override
  String get weekdayThu => 'गुरु';

  @override
  String get weekdayFri => 'शुक्र';

  @override
  String get weekdaySat => 'शनि';

  @override
  String get weekdaySun => 'रवि';

  @override
  String get prefsNonvegTitle => 'नॉन-वेज में क्या नहीं';

  @override
  String get nonvegNoBeef => 'बीफ़ नहीं';

  @override
  String get nonvegNoPork => 'पोर्क नहीं';

  @override
  String get nonvegHalalOnly => 'सिर्फ़ हलाल';

  @override
  String get prefsNoDairyTitle => 'दूध-दही नहीं';

  @override
  String get prefsNoDairyHint => 'पनीर, घी, दही सब हटाए जाएंगे';

  @override
  String get prefsShowOnHomeTitle => 'होम पर हेल्थ दिखाओ';

  @override
  String get prefsShowOnHomeHint => 'बंद हो तो सिर्फ़ डाइट दिखेगी';

  @override
  String get cookSyncDropped => 'कुछ बदलाव भेजे नहीं जा सके — टिकट पहले ही बदल गया था';

  @override
  String get settingsLogout => 'लॉग आउट करो';

  @override
  String get statusUnknown => 'ऐप अपडेट करो';

  @override
  String get cookHindiVoiceMissing => 'हिंदी आवाज़ इंस्टॉल करें';

  @override
  String get cookHindiVoiceHint => 'फ़ोन सेटिंग्स → भाषा → टेक्स्ट-टू-स्पीच में हिंदी चुनें।';

  @override
  String get cookOpenSettings => 'सेटिंग्स खोलो';

  @override
  String get cookAudioError => 'आवाज़ नहीं चल पाई';

  @override
  String get subStatusUnknown => 'स्टेटस पता नहीं चला';

  @override
  String get videoOpenFailed => 'वीडियो नहीं खुल पाया';

  @override
  String get settingsDisplay => 'डिस्प्ले';

  @override
  String get settingsLightAnimations => 'हल्की एनिमेशन';

  @override
  String get settingsLightAnimationsHint => 'पुराने या धीमे फ़ोन के लिए: थाली घूमेगी नहीं';

  @override
  String get cookLanguage => 'कुक मोड की भाषा';

  @override
  String get settingsFamilyOnBanega => 'बनेगा पर परिवार';

  @override
  String get invitesHint => 'घर के बड़े अपने फ़ोन से बनेगा चला सकते हैं।';

  @override
  String get invitesEmpty => 'अभी कोई निमंत्रण बाकी नहीं';

  @override
  String get inviteCta => 'परिवार के किसी सदस्य को बुलाएँ';

  @override
  String invitePendingRow(String phone, String date) {
    return '$phone · $date तक';
  }

  @override
  String inviteFor(String name) {
    return '$name के लिए';
  }

  @override
  String get inviteRevoke => 'रद्द करें';

  @override
  String get inviteRevokeAsk => 'यह निमंत्रण रद्द करें? पुराना कोड काम नहीं करेगा।';

  @override
  String get inviteRevoked => 'निमंत्रण रद्द कर दिया';

  @override
  String get inviteWho => 'कौन हैं?';

  @override
  String get inviteNewMember => 'नया सदस्य';

  @override
  String get inviteNewName => 'नाम';

  @override
  String get invitePhone => 'उनका फ़ोन नंबर';

  @override
  String get inviteRoleNote => 'बड़े सदस्य की तरह जुड़ेंगे: मेन्यू देख और बदल सकते हैं, कुक को भेज सकते हैं।';

  @override
  String get inviteCreate => 'निमंत्रण बनाएँ';

  @override
  String get inviteNameRequired => 'नाम लिखें';

  @override
  String get inviteCodeTitle => 'यह कोड भेजें';

  @override
  String inviteCodeBody(String phone) {
    return '$phone से लॉगिन करके \"कोड से जुड़ें\" चुनें और यह कोड डालें।';
  }

  @override
  String inviteCodeExpires(String date) {
    return '$date तक चलेगा';
  }

  @override
  String inviteCodeLabel(String code) {
    return 'निमंत्रण कोड $code';
  }

  @override
  String get inviteShareWhatsApp => 'WhatsApp पर भेजें';

  @override
  String get inviteCopy => 'कोड कॉपी करें';

  @override
  String get inviteCopied => 'कोड कॉपी हो गया';

  @override
  String get inviteDone => 'हो गया';

  @override
  String get inviteErrPhoneTaken => 'यह नंबर किसी और घर में कुक है।';

  @override
  String get householdOr => 'या';

  @override
  String get householdJoinOption => 'कोड से जुड़ें';

  @override
  String get householdJoinHint => 'घर वालों ने बनेगा पर बुलाया है? उनका भेजा कोड डालें।';

  @override
  String get joinTitle => 'अपने परिवार से जुड़ें';

  @override
  String get joinBody => 'WhatsApp पर आया 6 अक्षर का कोड डालें।';

  @override
  String get joinCta => 'जुड़ें';

  @override
  String joinCodeBox(int n) {
    return 'कोड का अक्षर $n';
  }

  @override
  String get joinCreateInstead => 'नया घर बनाएँ';

  @override
  String get joinErrInvalid => 'यह कोड सही नहीं है। मैसेज देखकर दोबारा डालें।';

  @override
  String get joinErrExpired => 'यह कोड पुराना हो गया। घर के एडमिन से नया कोड माँगें।';

  @override
  String get joinErrPhone => 'यह कोड किसी और नंबर के लिए है। उसी नंबर से लॉगिन करें जिस पर निमंत्रण आया।';

  @override
  String get joinErrAlready => 'आपका नंबर पहले से एक घर में है।';

  @override
  String get joinErrLocked => 'बहुत बार गलत कोड। थोड़ी देर बाद कोशिश करें।';

  @override
  String get ticketUnassignedTitle => 'अभी किसी को नहीं दिया';

  @override
  String get ticketUnassignedHint => 'कौन बनाएगा? कुक चुनें या खुद ले लें।';

  @override
  String get ticketUnassignedCard => 'कौन बनाएगा? टैप करके चुनें';

  @override
  String get ticketAssignTo => 'किसे दें…';

  @override
  String get ticketClaim => 'मैं बनाऊँगा';

  @override
  String get ticketClaimed => 'आज के शेफ़ आप! रसोई टैब में देखें।';

  @override
  String get ticketAlreadyClaimed => 'यह टिकट किसी और ने ले लिया।';

  @override
  String ticketAssignedToast(String name) {
    return '$name को दे दिया';
  }

  @override
  String get ticketAssigneeRequired => 'चुनें कौन बनाएगा';

  @override
  String get ticketNoCooks => 'अभी कोई कुक नहीं जोड़ा। सेटिंग्स में जोड़ें।';

  @override
  String get eventTicketUnassigned => 'टिकट किसी को नहीं दिया';

  @override
  String get eventTicketCancelled => 'टिकट रद्द हुआ';

  @override
  String get eventCookMessage => 'कुक का संदेश';

  @override
  String get eventFamilyMessage => 'परिवार का संदेश';

  @override
  String get eventChefClaimed => 'किसी ने आज बनाना चुना';

  @override
  String get eventCookOnDuty => 'कुक वापस ड्यूटी पर';

  @override
  String get eventRationBought => 'राशन खरीद लिया';

  @override
  String get eventStockIssueResolved => 'सामान की दिक्कत सुलझी';

  @override
  String get eventExportReady => 'डेटा निर्यात तैयार';

  @override
  String get eventAtRisk => 'खाना देर से हो सकता है';
}

/// The translations for Hindi, using the Latin script (`hi_Latn`).
class AppLocalizationsHiLatn extends AppLocalizationsHi {
  AppLocalizationsHiLatn() : super('hi_Latn');

  @override
  String get appTitle => 'Banega';

  @override
  String get wordmark => 'banega';

  @override
  String get aiMaharajBadge => 'AI MAHARAJ';

  @override
  String get thaliAlt => 'Ghar ki thali';

  @override
  String get back => 'Back';

  @override
  String get splashTitle => 'Aaj khaane\nmein kya hai?';

  @override
  String get splashBody =>
      'Har ghar ka roz ka sawaal. Ek AI jo aapke poore parivaar ki pasand yaad rakhta hai — aur har meal pe options deta hai.';

  @override
  String get splashCta => 'Apna ghar set karo';

  @override
  String get splashDemo => 'Demo family ke saath dekho';

  @override
  String get stepOneOfTwo => 'STEP 1 OF 2';

  @override
  String get familyTitle => 'Ghar mein kaun\nkaun hai?';

  @override
  String get familyBody => 'Har member ki pasand alag. Tap karke set karo — Maharaj sab yaad rakhega.';

  @override
  String get addMember => 'Member jodo';

  @override
  String familyCta(int count) {
    return '$count log · Aage badho';
  }

  @override
  String spiceSummary(String spice) {
    return '$spice mirch';
  }

  @override
  String get prefsStep => 'STEP 2 OF 2 · PASAND';

  @override
  String prefsTitle(String name) {
    return '$name ki pasand';
  }

  @override
  String get prefsSubtitle => 'Maharaj isi hisaab se suggest karega';

  @override
  String get prefsDietTitle => 'Kya khaate hain?';

  @override
  String get prefsSpiceTitle => 'Mirch kitni?';

  @override
  String get prefsNeedsTitle => 'Koi zaroorat ya parhez?';

  @override
  String get prefsCuisineTitle => 'Favourite cuisine';

  @override
  String prefsSave(String name) {
    return 'Save · $name';
  }

  @override
  String get dietVeg => 'Veg';

  @override
  String get dietVegHint => 'Shakahari';

  @override
  String get dietJain => 'Jain';

  @override
  String get dietJainHint => 'Bina pyaaz-lahsun';

  @override
  String get dietEgg => 'Egg';

  @override
  String get dietEggHint => 'Veg + ande';

  @override
  String get dietNonveg => 'Non-veg';

  @override
  String get dietNonvegHint => 'Sab kuch';

  @override
  String get dietJainFriendly => 'Jain-friendly';

  @override
  String get spiceKam => 'Kam';

  @override
  String get spiceMedium => 'Medium';

  @override
  String get spiceTeekha => 'Teekha';

  @override
  String get needLowOil => 'Low oil';

  @override
  String get needLowSugar => 'Low sugar';

  @override
  String get needHighProtein => 'High protein';

  @override
  String get needNoMaida => 'No maida';

  @override
  String get needKidFriendly => 'Kid-friendly';

  @override
  String get cuisineNorthIndian => 'North Indian';

  @override
  String get cuisineSouthIndian => 'South Indian';

  @override
  String get cuisineGujarati => 'Gujarati';

  @override
  String get cuisineRajasthani => 'Rajasthani';

  @override
  String get cuisineBengali => 'Bengali';

  @override
  String get cuisineMaharashtrian => 'Maharashtrian';

  @override
  String get cuisineIndoChinese => 'Indo-Chinese';

  @override
  String get loadingTitle => 'Maharaj aapke ghar\nko samajh raha hai…';

  @override
  String constraintLine(String items) {
    return 'Dhyaan rakha: $items';
  }

  @override
  String get constraintNone => 'Sabki pasand dhyaan mein hai';

  @override
  String constraintJain(String name) {
    return '$name (Jain)';
  }

  @override
  String constraintLowSugar(String name) {
    return '$name (low sugar)';
  }

  @override
  String constraintKamMirch(String name) {
    return '$name (kam mirch)';
  }

  @override
  String get householdName => 'Purohit Parivaar';

  @override
  String familyLine(int count, String items) {
    return '$count log · $items';
  }

  @override
  String get slotBreakfast => 'Nashta';

  @override
  String get slotLunch => 'Lunch';

  @override
  String get slotDinner => 'Dinner';

  @override
  String get eyebrowBreakfast => 'SUBAH KA NASHTA';

  @override
  String get eyebrowLunch => 'DOPAHAR KA KHAANA';

  @override
  String get eyebrowDinner => 'RAAT KA KHAANA';

  @override
  String get searchPrefix => 'Pucho';

  @override
  String get tickerAsk1 => '“15 min mein nashta”';

  @override
  String get tickerAsk2 => '“Dadi ke liye Jain dinner”';

  @override
  String get tickerAsk3 => '“baarish wala khaana”';

  @override
  String get tickerAsk4 => '“Daughter ka tiffin”';

  @override
  String get maharajPick => 'MAHARAJ KA PICK';

  @override
  String heroMeta(String fitLabel, int mins) {
    return '$fitLabel · $mins min';
  }

  @override
  String get recipeDekho => 'Recipe dekho';

  @override
  String get quickAsk15Min => '15 min mein kuch';

  @override
  String get quickAskHalka => 'Kuch halka';

  @override
  String get quickAskBaarish => 'Baarish special';

  @override
  String get quickAskTiffin => 'Daughter ka tiffin';

  @override
  String get quickAskMehmaan => 'Mehmaan aa rahe hain';

  @override
  String get quickAskProtein => 'High protein';

  @override
  String slotOptions(String slot) {
    return '$slot ke options';
  }

  @override
  String get sabkeHisaab => 'sabke hisaab se';

  @override
  String minBadge(int mins) {
    return '$mins MIN';
  }

  @override
  String get addLabel => 'ADD';

  @override
  String get addedLabel => 'ADDED';

  @override
  String planBarTitle(int count) {
    return '$count dish · Aaj ka menu';
  }

  @override
  String get cookKoBhejo => 'Cook ko bhejo';

  @override
  String get navGhar => 'Ghar';

  @override
  String get navMaharaj => 'Maharaj se pucho';

  @override
  String get navParivaar => 'Parivaar';

  @override
  String get chatName => 'Maharaj';

  @override
  String chatMemory(int count) {
    return '$count logon ki pasand yaad hai';
  }

  @override
  String chatMenuPill(int count) {
    return 'Menu · $count';
  }

  @override
  String chatGreeting(int count) {
    return 'Namaste! Main Maharaj hoon. Ghar ke $count logon ki pasand mujhe yaad hai.\nBas pucho — aaj kya banaun?';
  }

  @override
  String get chatChipLunch => 'Aaj lunch mein kya?';

  @override
  String get chatChipHalkaDinner => 'Kuch halka dinner';

  @override
  String get chatChipNashta => '15 min mein nashta';

  @override
  String get chatChipMehmaan => 'Mehmaan aa rahe hain';

  @override
  String get chatPlaceholder => 'Aaj dinner mein kuch halka…';

  @override
  String get chatVoice => 'Voice';

  @override
  String get chatSend => 'Send';

  @override
  String get typing => 'rotiyaan sek raha hoon…';

  @override
  String get voiceToast => 'Voice input — real app mein Hinglish mein bol sakte ho';

  @override
  String get chatError => 'Maharaj abhi jawab nahi de paaye. Phir se pucho.';

  @override
  String get chatInputLabel => 'Maharaj se pucho';

  @override
  String chatNoMatch(String slot) {
    return 'Is combo mein exact match nahi mila. $slot ke liye ye sabse kareeb hain:';
  }

  @override
  String chatOptions(String slot, int count) {
    return '$slot ke liye $count options';
  }

  @override
  String chatOptionsWhy(String options, String why) {
    return '$options — $why';
  }

  @override
  String chatFamilyCan(int ok) {
    return '$ok mein poora parivaar kha sakta hai.';
  }

  @override
  String get whyHalka => 'halka';

  @override
  String get whyProtein => 'high protein';

  @override
  String get whyMehmaan => 'mehmaan-worthy';

  @override
  String get whyBaarish => 'baarish wala';

  @override
  String get whyKid => 'bachchon ko pasand';

  @override
  String get why20Min => '20 min ke andar';

  @override
  String get whyPaneer => 'paneer wala';

  @override
  String whyMember(String name) {
    return '$name ke hisaab se';
  }

  @override
  String get followProteinNashta => 'Protein wala nashta';

  @override
  String get followTiffin => 'Daughter ka tiffin';

  @override
  String get followSouth => 'Kuch South Indian';

  @override
  String get followHalka => 'Kuch halka';

  @override
  String get followBaarish => 'Baarish special';

  @override
  String get followPaneer => 'Paneer wala kuch';

  @override
  String get followDadi => 'Dadi ke liye kya?';

  @override
  String get fitAllPerfect => 'Sabke liye perfect';

  @override
  String get fitAllPerfectShort => 'Sabke liye';

  @override
  String fitAllTweak(int count) {
    return 'Sabke liye · $count tweak';
  }

  @override
  String fitAllTweakShort(int count) {
    return 'Sab · $count tweak';
  }

  @override
  String fitPartial(int can, int total) {
    return '$can/$total ke liye';
  }

  @override
  String fitNotFor(String names) {
    return '$names ke liye nahi';
  }

  @override
  String get fitAllHappy => 'Sab khush, koi badlaav nahi';

  @override
  String fitTweakNote(String name, String note) {
    return '$name: $note';
  }

  @override
  String get reasonOnionGarlic => 'Pyaaz-lahsun hai';

  @override
  String get reasonEgg => 'Isme anda hai';

  @override
  String get reasonNonveg => 'Non-veg hai';

  @override
  String get reasonMaida => 'Maida hai';

  @override
  String get reasonLessChilli => 'Unki katori mein kam mirch';

  @override
  String get reasonExtraChilli => 'Upar se laal mirch / achaar';

  @override
  String get reasonLowSugar => 'Portion chhota, salad zyada';

  @override
  String get reasonLowOil => 'Kam tel mein banao';

  @override
  String get reasonProtein => 'Saath mein dahi/paneer';

  @override
  String get reasonKid => 'Bachche ke liye alag, halka';

  @override
  String get reasonFavCuisine => 'Favourite cuisine bhi';

  @override
  String get reasonPerfect => 'Bilkul sahi';

  @override
  String get verdictPerfect => 'Perfect';

  @override
  String get verdictTweak => 'Tweak';

  @override
  String get verdictNo => 'Nahi';

  @override
  String detailMeta(String diet, String cuisine, int mins) {
    return '$diet · $cuisine · $mins min';
  }

  @override
  String get kaunKhayega => 'Kaun khayega';

  @override
  String get saaman => 'Saaman';

  @override
  String get kaiseBanega => 'Kaise banega';

  @override
  String get videoRecipe => 'Video recipe';

  @override
  String get menuMeinDaalo => 'Menu mein daalo';

  @override
  String get menuMeinHai => 'Menu mein hai';

  @override
  String planTitle(String slot) {
    return 'Aaj ka $slot menu';
  }

  @override
  String planSubtitle(int count, String coverage) {
    return '$count logon ke liye · $coverage';
  }

  @override
  String get planCoverageAll => 'har member ke liye kuch na kuch hai';

  @override
  String get planCoverageSome => 'kuch members ke liye aur dish chahiye';

  @override
  String get planEmpty => 'Menu khaali hai — Ghar se dishes ADD karo.';

  @override
  String get planSaamanList => 'Saaman ki list';

  @override
  String get planSendCook => 'Maharaj / cook ko bhejo';

  @override
  String get planOrderMissing => 'Missing saaman order karo';

  @override
  String get toastSentCook => 'Menu + saaman list cook ko WhatsApp par bhej di';

  @override
  String get toastMissingCart => 'Missing saaman cart mein daal diya';

  @override
  String get galleryTitle => 'Component gallery';

  @override
  String get dietNoOnionGarlic => 'No pyaaz-lahsun';

  @override
  String get dietNoOnionGarlicHint => 'Veg, bina pyaaz-lahsun';

  @override
  String get dietPescatarian => 'Pescatarian';

  @override
  String get dietPescatarianHint => 'Veg + machli';

  @override
  String reasonAllergen(String item) {
    return '$item se allergy';
  }

  @override
  String get reasonRootVeg => 'Zameen ke neeche ki sabzi hai';

  @override
  String reasonNonvegItem(String item) {
    return 'Isme $item hai';
  }

  @override
  String get reasonDairy => 'Dairy hai';

  @override
  String reasonDislikeMain(String item) {
    return 'Unko $item pasand nahi';
  }

  @override
  String reasonDislikeSkip(String item) {
    return 'Unki katori mein $item mat daalo';
  }

  @override
  String get reasonVrat => 'Aaj vrat hai';

  @override
  String get allergenPeanut => 'Moongphali';

  @override
  String get allergenTreeNut => 'Kaju-badaam';

  @override
  String get allergenDairy => 'Dairy';

  @override
  String get allergenGluten => 'Gehun (gluten)';

  @override
  String get allergenEgg => 'Anda';

  @override
  String get allergenFish => 'Machhli';

  @override
  String get allergenSesame => 'Til';

  @override
  String get allergenSoy => 'Soya';

  @override
  String get demoDataPill => 'Demo data';

  @override
  String servingsCount(int count) {
    return '$count log';
  }

  @override
  String get servingsLess => 'Kam log';

  @override
  String get servingsMore => 'Zyada log';

  @override
  String get batchWarning => 'Itne logon ke liye do batch mein pakao';

  @override
  String get homeLoadError => 'Options load nahi hue';

  @override
  String get retry => 'Phir se try karo';

  @override
  String get navRasoi => 'Rasoi';

  @override
  String get slotTiffin => 'Tiffin';

  @override
  String get slotShaam => 'Shaam ka nashta';

  @override
  String get dateToday => 'Aaj';

  @override
  String get dateTomorrow => 'Kal';

  @override
  String planTitleOn(String day, String slot) {
    return '$day ka $slot menu';
  }

  @override
  String planCoverageMissing(String names) {
    return '$names ke liye aur dish chahiye';
  }

  @override
  String get planLoadError => 'Menu load nahi hua';

  @override
  String get planEatersTitle => 'Kaun kha raha hai?';

  @override
  String get planGuestAdults => 'Mehmaan · bade';

  @override
  String get planGuestKids => 'Mehmaan · bachche';

  @override
  String get planGuestDiet => 'Mehmaan kya khaate hain?';

  @override
  String get planServingsTitle => 'Kitne log';

  @override
  String planServingsValue(String servings) {
    return '$servings servings';
  }

  @override
  String get planServingsHint => 'Bade 1 · bachche ½ · mehmaan jode';

  @override
  String get planDueTitle => 'Kab tak';

  @override
  String get planDueHint => 'Khaana kitne baje tak taiyaar ho';

  @override
  String get planAssigneeTitle => 'Kaun banayega';

  @override
  String get planAssigneeNone => 'Koi nahi';

  @override
  String cookChipLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get cookKindHired => 'hired';

  @override
  String get cookKindFamily => 'family';

  @override
  String get cookOffDutyTag => 'Chhutti';

  @override
  String get planViewTicket => 'Ticket dekho';

  @override
  String get planShareWhatsApp => 'WhatsApp par bhi bhejo';

  @override
  String get removeDish => 'Hatao';

  @override
  String get toastTicketSent => 'Ticket bhej diya';

  @override
  String get toastOrderSoon => 'Saaman order karna jaldi aa raha hai';

  @override
  String get toastError => 'Kuch gadbad hui, phir se try karo';

  @override
  String get toastConflict => 'Ticket badal gaya tha — naya status dikha rahe hain';

  @override
  String get itemIn => 'Hai';

  @override
  String get itemLow => 'Kam hai';

  @override
  String get itemOut => 'Khatam';

  @override
  String get itemUntracked => 'Pata nahi';

  @override
  String get statusNew => 'Naya';

  @override
  String get statusUnassigned => 'Kisi ko nahi mila';

  @override
  String get statusAccepted => 'Accept ho gaya';

  @override
  String get statusCooking => 'Ban raha hai';

  @override
  String get statusReady => 'Taiyaar';

  @override
  String get statusCompleted => 'Ho gaya';

  @override
  String get statusNotConfirmed => 'Confirm nahi hua';

  @override
  String get statusCancelled => 'Cancel';

  @override
  String get ticketTitle => 'Ticket';

  @override
  String ticketCardTitle(String slot) {
    return '$slot ka ticket';
  }

  @override
  String dueBy(String time) {
    return 'Kab tak $time';
  }

  @override
  String get ticketNoAssignee => 'Kisi ko assign nahi';

  @override
  String ticketGuests(int count) {
    return '+$count mehmaan';
  }

  @override
  String get ticketDishes => 'Dishes';

  @override
  String get ticketNotes => 'Note';

  @override
  String get ticketNotesHint => 'Cook ke liye note…';

  @override
  String get ticketChangeLog => 'Kya kya badla';

  @override
  String get ticketEdit => 'Badlo';

  @override
  String get ticketSave => 'Save karo';

  @override
  String get ticketSavedToast => 'Ticket update ho gaya';

  @override
  String get ticketCancel => 'Cancel karo';

  @override
  String get ticketCancelReason => 'Cancel kyun kar rahe ho?';

  @override
  String get ticketCancelReasonHint => 'Wajah likho';

  @override
  String get ticketCancelConfirm => 'Haan, cancel karo';

  @override
  String get ticketKeep => 'Rehne do';

  @override
  String get ticketCancelledToast => 'Ticket cancel ho gaya';

  @override
  String get ticketMarkDone => 'Ho gaya mark karo';

  @override
  String get ticketAskCook => 'Cook se baat karo';

  @override
  String get ticketUpdatedTag => 'Badla gaya';

  @override
  String get ticketStockIssueTag => 'Saaman khatam';

  @override
  String get ticketLoadError => 'Ticket load nahi hua';

  @override
  String get khanaBanaPrompt => 'Khaana bana?';

  @override
  String get khanaBanaHint => 'Cook ne \'Ban gaya\' nahi dabaya. Bata do, taaki hisaab sahi rahe.';

  @override
  String get khanaBanaYes => 'Haan, bana';

  @override
  String get khanaBanaNo => 'Nahi bana';

  @override
  String get logCreated => 'Ticket bana';

  @override
  String get logAccepted => 'Accept kiya';

  @override
  String get logCooking => 'Banana shuru';

  @override
  String get logReady => 'Taiyaar';

  @override
  String get logCompleted => 'Ho gaya';

  @override
  String get logCancelled => 'Cancel kiya';

  @override
  String get logNotConfirmed => 'Confirm nahi hua';

  @override
  String get logUpdated => 'Badla';

  @override
  String get logItemOut => 'Saaman khatam';

  @override
  String get logClaimed => 'Claim kiya';

  @override
  String get logReassigned => 'Dusre cook ko diya';

  @override
  String get logUnassigned => 'Assign hataya';

  @override
  String get logAutoCancelled => 'Apne aap cancel';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String inboxBellUnread(int count) {
    return 'Inbox, $count naye';
  }

  @override
  String get inboxEmpty => 'Abhi koi khabar nahi';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsDemoCook => 'Demo: cook role';

  @override
  String get settingsDemoCookHint => 'Cook role ho to neeche \'Rasoi\' tab dikhega (cook mode).';

  @override
  String get cookTitle => 'Aaj ke tickets';

  @override
  String get cookTabToday => 'Aaj';

  @override
  String get cookTabTomorrow => 'Kal';

  @override
  String cookDueBy(String time) {
    return 'Kab tak $time';
  }

  @override
  String get cookActionAccept => 'Accept karo';

  @override
  String get cookActionStart => 'Shuru karo';

  @override
  String get cookActionDone => 'Ban gaya';

  @override
  String get cookActionReady => 'Taiyaar';

  @override
  String get cookEmpty => 'Koi ticket nahi';

  @override
  String get cookOnDuty => 'On duty';

  @override
  String get cookOffDuty => 'Chhutti';

  @override
  String cookOffDutyUntil(String date) {
    return '$date tak chhutti';
  }

  @override
  String get cookOffDutyAsk => 'Kab tak chhutti?';

  @override
  String get cookOffDutyToday => 'Sirf aaj';

  @override
  String get cookOffDutyTomorrow => 'Kal tak';

  @override
  String get cookOffDutyPick => 'Date chuno';

  @override
  String get cookFamilyMode => 'Parivaar';

  @override
  String get cookOffline => 'Net nahi hai — purani jaankari dikh rahi hai';

  @override
  String get cookNotSent => 'Bheja nahi gaya';

  @override
  String get cookQueued => 'Net aane par bhej denge';

  @override
  String get cookDishes => 'Kya banana hai';

  @override
  String get cookEaters => 'Kaun khayega';

  @override
  String cookServings(String servings) {
    return '$servings logon ke liye';
  }

  @override
  String cookGuests(int count) {
    return '+$count mehmaan';
  }

  @override
  String get cookNotes => 'Note';

  @override
  String get cookItems => 'Zaroori saaman';

  @override
  String get cookItemOut => 'Khatam hai';

  @override
  String get cookAskFamily => 'Family se poochho';

  @override
  String get cookOpenRecipe => 'Recipe';

  @override
  String get cookIngredients => 'Saaman';

  @override
  String get cookSteps => 'Kaise banana hai';

  @override
  String get cookPlay => 'Suno';

  @override
  String get cookPause => 'Roko';

  @override
  String get cookSpeed => 'Awaaz ki speed';

  @override
  String get cookSpeedSlow => 'Dheere';

  @override
  String get cookSpeedNormal => 'Normal';

  @override
  String get cookSpeedFast => 'Tez';

  @override
  String get cookThread => 'Parivaar se baat';

  @override
  String get cookThreadHint => 'Sandesh likho…';

  @override
  String get cookSend => 'Bhejo';

  @override
  String get cookThreadEmpty => 'Abhi koi baat nahi';

  @override
  String get cookConflict => 'Ticket badal gaya — naya status dikha rahe hain';

  @override
  String get cookError => 'Kuch gadbad hui';

  @override
  String get cookLoadError => 'Load nahi hua — phir se try karo';

  @override
  String get stockTitle => 'Rasoi stock';

  @override
  String stockSubtitle(int count, int low) {
    return '$count cheezein · $low kam ya khatam';
  }

  @override
  String get stockSearchHint => 'Dhoondho: dahi, pyaaz…';

  @override
  String get stockFilterAll => 'Sab';

  @override
  String get stockFilterLowOut => 'Low + Out';

  @override
  String get stockAllIn => 'Sab In';

  @override
  String get stockAllInDone => 'Sab stock mein';

  @override
  String get stockLevelIn => 'In';

  @override
  String get stockLevelLow => 'Low';

  @override
  String get stockLevelOut => 'Out';

  @override
  String get stockEmpty => 'Kuch nahi mila';

  @override
  String get stockLoadError => 'Stock load nahi hua';

  @override
  String get stockCatSabzi => 'Sabzi';

  @override
  String get stockCatDairy => 'Doodh-dahi';

  @override
  String get stockCatDal => 'Dal';

  @override
  String get stockCatAnaaj => 'Aata-chawal';

  @override
  String get stockCatMasale => 'Masale';

  @override
  String get stockCatTelGhee => 'Tel-ghee';

  @override
  String get stockCatDryFruits => 'Dry fruits';

  @override
  String get stockCatOther => 'Aur';

  @override
  String get rationTitle => 'Ration';

  @override
  String get rationTabPending => 'Pending';

  @override
  String get rationTabApproved => 'Approved';

  @override
  String get rationTabBought => 'Kharida';

  @override
  String get rationEmpty => 'Koi request nahi';

  @override
  String rationRaisedBy(String name) {
    return '$name ne maanga';
  }

  @override
  String rationItems(int count) {
    return '$count cheezein';
  }

  @override
  String get rationApprove => 'Approve karo';

  @override
  String get rationReject => 'Mana karo';

  @override
  String get rationNoteHint => 'Note (optional)';

  @override
  String get rationBought => 'Kharid liya';

  @override
  String get rationStatusPending => 'Pending';

  @override
  String get rationStatusApproved => 'Approved';

  @override
  String get rationStatusRejected => 'Mana hua';

  @override
  String get rationStatusBought => 'Aa gaya';

  @override
  String get rationApprovedToast => 'Approve ho gaya';

  @override
  String get rationRejectedToast => 'Mana kar diya';

  @override
  String get rationBoughtToast => 'Saaman stock mein aa gaya';

  @override
  String get rationSentToast => 'Ration request bhej di';

  @override
  String get rationNothingMissing => 'Sab saaman hai — kuch order nahi karna';

  @override
  String get rationSelfApproved => 'Khud approve';

  @override
  String get cookRasoi => 'Rasoi';

  @override
  String get cookRationAsk => 'Ration maango';

  @override
  String get cookRationTitle => 'Mera ration';

  @override
  String get cookRationSheetTitle => 'Kya chahiye?';

  @override
  String get cookRationFreeHint => 'Aur kuch? Likho';

  @override
  String get cookRationAdd => 'Jodo';

  @override
  String get cookRationSend => 'Bhejo';

  @override
  String get cookRationSent => 'Maang bhej di';

  @override
  String get cookRationNew => 'Nayi maang';

  @override
  String ladderTitle(String item) {
    return '$item khatam hai';
  }

  @override
  String ladderSkipAsk(String item) {
    return 'Bina $item ke bana lo?';
  }

  @override
  String get ladderSkipYes => 'Haan, bina iske';

  @override
  String get ladderMoreWays => 'Aur raaste';

  @override
  String get ladderSwapTitle => 'Iski jagah kya daalein?';

  @override
  String get ladderSwapDo => 'Badal do';

  @override
  String get ladderNoSwap => 'Koi safe badli nahi mili';

  @override
  String get ladderChangeDish => 'Dish badlo';

  @override
  String get ladderDishTitle => 'Inme se kya banayein?';

  @override
  String get ladderDishPick => 'Yeh banao';

  @override
  String get ladderNoDish => 'Koi aur dish stock mein nahi';

  @override
  String get ladderPending => 'Family se poochh rahe hain…';

  @override
  String ladderPendingHint(int mins) {
    return '$mins min mein jawab nahi aaya to admin ko alert jayega';
  }

  @override
  String get ladderTimeout => 'Time out — admin ko alert gaya';

  @override
  String get ladderDone => 'Ho gaya — ticket badal gaya';

  @override
  String get ladderRejected => 'Family ne mana kiya — doosra raasta chuno';

  @override
  String get ladderOpen => 'Raasta dekho';

  @override
  String get ladderClose => 'Band karo';

  @override
  String get approvalTitle => 'Aapki haan chahiye';

  @override
  String approvalSwap(String detail) {
    return 'Saaman badlo: $detail';
  }

  @override
  String approvalChangeDish(String detail) {
    return 'Dish badlo: $detail';
  }

  @override
  String approvalAskedBy(String name) {
    return '$name ne poochha';
  }

  @override
  String approvalExpires(String time) {
    return '$time tak jawab do';
  }

  @override
  String get approvalYes => 'Haan';

  @override
  String get approvalNo => 'Nahi';

  @override
  String get approvalApprovedToast => 'Cook ko bata diya: haan';

  @override
  String get approvalRejectedToast => 'Cook ko bata diya: nahi';

  @override
  String get approvalGone => 'Yeh sawaal ab khula nahi hai';

  @override
  String get ticketIssueChoosing => 'Cook raasta chun raha hai';

  @override
  String ticketIssuePending(String detail) {
    return 'Cook ne poochha: $detail';
  }

  @override
  String get ticketRate => 'Kaisa bana?';

  @override
  String get ticketRated => 'Rating di — shukriya!';

  @override
  String get logSkip => 'Bina saaman ke banaya';

  @override
  String get logSwap => 'Saaman badla';

  @override
  String get logChangeDish => 'Dish badli';

  @override
  String get logApprovalRequested => 'Family se poochha';

  @override
  String get logApproved => 'Family ne haan kaha';

  @override
  String get logRejected => 'Family ne mana kiya';

  @override
  String get logTimeout => 'Time out — admin ko alert';

  @override
  String rateTitle(String slot) {
    return '$slot kaisa bana?';
  }

  @override
  String rateThanksFamily(String name) {
    return '$name ne banaya — shukriya bolo!';
  }

  @override
  String get rateHint => 'Har khaane wale ke liye ek tap';

  @override
  String get rateBura => 'Bura';

  @override
  String get rateTheek => 'Theek';

  @override
  String get rateBahutAccha => 'Bahut accha';

  @override
  String get rateProxy => 'Unki taraf se';

  @override
  String get rateNoteHint => 'Kuch kehna hai? (optional)';

  @override
  String get rateNoteHintFamily => 'Kya badlein agli baar?';

  @override
  String get rateSubmit => 'Rating bhejo';

  @override
  String get rateSubmitFamily => 'Shukriya bhejo';

  @override
  String get rateDone => 'Shukriya! Maharaj yaad rakhega';

  @override
  String get rateNeedOne => 'Kam se kam ek rating do';

  @override
  String get recipeHomeRating => 'Ghar ki rating';

  @override
  String recipeRatingValue(String avg, int count) {
    return '$avg/3 · $count rating';
  }

  @override
  String trialBanner(int days) {
    return 'Free trial · $days din baaki';
  }

  @override
  String get graceBanner => 'Payment atki hai — 3 din mein theek karo';

  @override
  String get expiredBanner => 'Plan band hai — sirf dekh sakte ho';

  @override
  String get planBandTitle => 'Plan band hai';

  @override
  String get planBandBody =>
      'Naya menu, Maharaj chat aur cook ticket ke liye ₹50/hafta wala plan chalu karo. Aaj aur kal ke tickets cook bana sakta hai.';

  @override
  String get planBandCta => 'Plan dekho';

  @override
  String get weeklyTitle => 'Is hafte';

  @override
  String weeklyTop(String name) {
    return 'Top: $name';
  }

  @override
  String weeklyOnTime(String pct) {
    return '$pct% time par';
  }

  @override
  String weeklyCoverage(String pct) {
    return '$pct% sabke liye';
  }

  @override
  String weeklyMeals(int count) {
    return '$count meal bane';
  }

  @override
  String get paywallTitle => 'Banega plan';

  @override
  String get paywallPrice => '₹50/hafta';

  @override
  String get paywallBody => 'Poore ghar ke liye sab kuch, ek hi plan mein.';

  @override
  String get paywallFeature1 => 'Har meal pe sabke hisaab se options';

  @override
  String get paywallFeature2 => 'Cook ko ticket, stock aur ration';

  @override
  String get paywallFeature3 => 'Ratings se Maharaj seekhta hai';

  @override
  String get paywallSubscribe => '₹50/hafta · Chalu karo';

  @override
  String get paywallRestore => 'Purchase restore karo';

  @override
  String get paywallRestored => 'Plan status update ho gaya';

  @override
  String get paywallActive => 'Plan chalu hai';

  @override
  String paywallRenews(String date) {
    return 'Agla renewal $date';
  }

  @override
  String paywallTrial(int days) {
    return 'Free trial: $days din baaki';
  }

  @override
  String get paywallGrace => 'Payment atki hai — store mein theek karo';

  @override
  String get paywallSubscribed => 'Plan chalu! Shukriya';

  @override
  String get paywallStoreSoon => 'Store billing jald aa raha hai';

  @override
  String get paywallPending => 'Payment pending hai. Poora hote hi plan chalu ho jayega.';

  @override
  String get paywallCancelled => 'Purchase cancel ho gaya';

  @override
  String get paywallNothingToRestore => 'Is Play account par koi Banega plan nahi mila';

  @override
  String get paywallCancelNote => 'Cancel kabhi bhi Play Store / App Store se';

  @override
  String get subStatusTrial => 'Free trial';

  @override
  String get subStatusActive => 'Chalu';

  @override
  String get subStatusGrace => 'Payment atki';

  @override
  String get subStatusExpired => 'Band';

  @override
  String get consentTitle => 'Aapka data, aapka haq';

  @override
  String get consentBody =>
      'Banega aapka phone number login ke liye, aur ghar ke members ki pasand, allergy, vrat ke din aur khaane ka itihaas sirf menu banane, cook ko ticket bhejne aur Maharaj ke sujhav ke liye rakhta hai. Data kabhi becha nahi jaata. Settings se kabhi bhi apna account delete kar sakte ho; ghar ka admin poore ghar ka data export ya delete kar sakta hai.';

  @override
  String get consentLlmNote =>
      'Maharaj chat ke sawaal ek AI service (Anthropic Claude) ko jaate hain. Phone number aur health needs kabhi nahi jaate; allergy sirf ginti mein, aur family ka naam sirf tab jab aap khud likho.';

  @override
  String get consentKids => 'Bachchon ki profile aap maa-baap ya guardian ki tarah bana rahe ho.';

  @override
  String get consentAccept => 'Maan liya';

  @override
  String get consentPrivacy => 'Privacy policy padho';

  @override
  String get settingsHousehold => 'Ghar';

  @override
  String get settingsHouseholdName => 'Ghar ka naam';

  @override
  String get settingsEdit => 'Badlo';

  @override
  String get settingsSave => 'Save karo';

  @override
  String get settingsCancel => 'Rehne do';

  @override
  String get settingsSaved => 'Save ho gaya';

  @override
  String get settingsMembers => 'Parivaar ke members';

  @override
  String get settingsCooks => 'Cook setup';

  @override
  String get settingsCookPrimary => 'Primary';

  @override
  String get settingsCookBackup => 'Backup';

  @override
  String get settingsCookRemove => 'Hatao';

  @override
  String settingsCookRemoveAsk(String name) {
    return '$name ko hatayein? Unke khule tickets unassigned ho jayenge.';
  }

  @override
  String get settingsAddHiredCook => 'Hired cook jodo';

  @override
  String get settingsCookName => 'Naam';

  @override
  String get settingsCookPhone => 'Phone number';

  @override
  String settingsCookAdded(String name) {
    return '$name jud gaye';
  }

  @override
  String get settingsHiredLimit => 'Ek ghar mein ek hi hired cook ho sakta hai';

  @override
  String get settingsPhoneTaken => 'Yeh phone kisi aur ghar mein hai';

  @override
  String get settingsInvalidPhone => 'Sahi phone number daalo';

  @override
  String get settingsLanguage => 'Bhasha';

  @override
  String get settingsLanguageHint => 'Cook mode Hindi mein khulta hai; cook wahan apni bhasha chun sakte hain';

  @override
  String get langHinglish => 'Hinglish';

  @override
  String get langEnglish => 'English';

  @override
  String get langHindi => 'हिंदी';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotifMandatory => 'Zaroori — hamesha on';

  @override
  String get settingsRatings => 'Ratings';

  @override
  String get settingsRatingsHint => 'Khaane ke baad \'Kaisa bana?\' poochho. Family cook band kar sakti hai.';

  @override
  String get settingsAutoDecrement => 'Khaane ke baad stock ghatao';

  @override
  String get settingsAutoDecrementHint => 'Taaza saaman (dahi, sabzi) \'Low\' ho jayega';

  @override
  String get settingsShowNames => 'Cook ko rating mein naam dikhao';

  @override
  String get settingsShowNamesHint => 'Band ho to cook ko sirf average dikhta hai';

  @override
  String get settingsCookSwaps => 'Cook khud swap chun sakta hai';

  @override
  String get settingsCookSwapsHint => 'Band ho to har swap pe aapki haan chahiye';

  @override
  String get settingsKitchen => 'Rasoi';

  @override
  String get settingsSubscription => 'Plan';

  @override
  String get settingsPrivacy => 'Privacy aur data';

  @override
  String get settingsConsent => 'Consent dobara padho';

  @override
  String get settingsGrievance => 'Shikayat ke liye: privacy@banega.app';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy dekho';

  @override
  String get settingsTerms => 'Terms aur shartein';

  @override
  String get settingsExport => 'Mera data export karo';

  @override
  String get settingsExportToast => 'Inbox mein link aayega';

  @override
  String get settingsDeleteHousehold => 'Ghar delete karo';

  @override
  String get settingsDeleteHouseholdAsk =>
      'Poore ghar ka data (members, menu, tickets, ratings, stock) 7 din baad hamesha ke liye mit jayega. 7 din tak \'Wapas lao\' se undo kar sakte ho. Store subscription alag se cancel karna hoga.';

  @override
  String get settingsDeleteConfirm => 'Haan, delete karo';

  @override
  String settingsDeletePending(String date) {
    return 'Ghar $date ko delete hoga';
  }

  @override
  String get settingsRestore => 'Wapas lao';

  @override
  String get settingsRestored => 'Ghar wapas aa gaya';

  @override
  String get settingsDeleteMe => 'Mera account delete karo';

  @override
  String get settingsDeleteMeAsk =>
      'Aapka login hat jayega; ghar aur baaki members rahenge. 7 din tak undo ho sakta hai.';

  @override
  String get settingsDeletedMe => 'Account delete ho gaya — 7 din mein wapas aa sakte ho';

  @override
  String get eventTicketCreated => 'Naya ticket';

  @override
  String get eventTicketAccepted => 'Ticket accept hua';

  @override
  String get eventTicketUpdated => 'Ticket badla';

  @override
  String get eventTicketCompleted => 'Khaana ban gaya';

  @override
  String get eventNotConfirmed => '\'Khaana bana?\' sawaal';

  @override
  String get eventCookOffDuty => 'Cook chhutti par';

  @override
  String get eventNoShow => 'Cook ne accept nahi kiya';

  @override
  String get eventStockLow => 'Stock kam';

  @override
  String get eventRationRequest => 'Ration ki maang';

  @override
  String get eventRationDecided => 'Ration ka jawab';

  @override
  String get eventStockIssue => 'Saaman khatam';

  @override
  String get eventApprovalRequest => 'Haan/nahi sawaal';

  @override
  String get eventApprovalDecided => 'Haan/nahi jawab';

  @override
  String get eventStockTimeout => 'Jawab ka time out';

  @override
  String get eventRatePrompt => 'Rating do';

  @override
  String get eventExpiry => 'Plan reminder';

  @override
  String get eventWeekly => 'Hafte ki report';

  @override
  String get eventTomorrow => 'Kal ke tickets';

  @override
  String get offlineBanner => 'Internet nahi hai. Jo pehle aaya tha wahi dikh raha hai.';

  @override
  String get offlineRetry => 'Phir se';

  @override
  String get authPhoneTitle => 'Apna number';

  @override
  String get authPhoneBody => 'OTP se login hoga. Number sirf login ke liye hai.';

  @override
  String get authPhoneHint => '10 digit mobile number';

  @override
  String get authSendOtp => 'OTP bhejo';

  @override
  String get authPhoneInvalid => '10 digit ka sahi number daalo';

  @override
  String get authOtpTitle => 'OTP daalo';

  @override
  String authOtpBody(String phone) {
    return '$phone par 6 digit ka code bheja hai';
  }

  @override
  String authOtpResendIn(int seconds) {
    return '$seconds sec mein dobara bhej sakte ho';
  }

  @override
  String get authOtpResend => 'OTP dobara bhejo';

  @override
  String authOtpDevCode(String code) {
    return 'Dev code: $code';
  }

  @override
  String get authOtpWrong => 'Code galat hai, phir se daalo';

  @override
  String authOtpDigit(int index) {
    return 'OTP ka $index number';
  }

  @override
  String get authVerify => 'Aage badho';

  @override
  String get authChangeNumber => 'Number badlo';

  @override
  String get householdCreateTitle => 'Ghar ka naam';

  @override
  String get householdCreateBody => 'Yeh naam parivaar aur cook, sabko dikhega.';

  @override
  String get householdCreateSuffix => 'Parivaar';

  @override
  String get householdCreateCta => 'Ghar banao';

  @override
  String get householdNameRequired => 'Ghar ka naam likho';

  @override
  String get notFoundTitle => 'Yeh page nahi mila';

  @override
  String get notFoundHome => 'Ghar par jao';

  @override
  String get addMemberTitle => 'Naya member';

  @override
  String get addMemberHint => 'Naam likho';

  @override
  String get addMemberSuggestions => 'Ya inme se chuno';

  @override
  String get addMemberCta => 'Jodo';

  @override
  String get commonCancel => 'Rehne do';

  @override
  String get removeMember => 'Member hatao';

  @override
  String removeMemberConfirm(String name) {
    return '$name ko parivaar se hatayein?';
  }

  @override
  String get removeMemberBody => 'Unki pasand ab menu mein nahi gini jayegi.';

  @override
  String get removeMemberYes => 'Haan, hatao';

  @override
  String get membersLoadError => 'Parivaar load nahi hua';

  @override
  String get membersEmpty => 'Abhi koi member nahi. Pehla member jodo.';

  @override
  String get memberSaveError => 'Save nahi hua, phir se try karo';

  @override
  String get prefsKidTitle => 'Bachcha hai';

  @override
  String get prefsKidHint => 'Aadhi serving gini jayegi';

  @override
  String get prefsAllergensTitle => 'Allergy (bilkul nahi)';

  @override
  String get allergenMilk => 'Doodh';

  @override
  String get allergenShellfish => 'Jhinga';

  @override
  String get allergenMustard => 'Sarson';

  @override
  String get prefsDislikesTitle => 'Pasand nahi';

  @override
  String get prefsDislikesHint => 'Jaise baingan, karela';

  @override
  String get prefsDislikeAdd => 'Jodo';

  @override
  String prefsDislikeRemove(String item) {
    return '$item hatao';
  }

  @override
  String get prefsVratTitle => 'Vrat ke din';

  @override
  String get weekdayMon => 'Som';

  @override
  String get weekdayTue => 'Mangal';

  @override
  String get weekdayWed => 'Budh';

  @override
  String get weekdayThu => 'Guru';

  @override
  String get weekdayFri => 'Shukra';

  @override
  String get weekdaySat => 'Shani';

  @override
  String get weekdaySun => 'Ravi';

  @override
  String get prefsNonvegTitle => 'Non-veg mein kya nahi';

  @override
  String get nonvegNoBeef => 'Beef nahi';

  @override
  String get nonvegNoPork => 'Pork nahi';

  @override
  String get nonvegHalalOnly => 'Sirf halal';

  @override
  String get prefsNoDairyTitle => 'Doodh-dahi nahi';

  @override
  String get prefsNoDairyHint => 'Paneer, ghee, dahi sab hataye jayenge';

  @override
  String get prefsShowOnHomeTitle => 'Home par health dikhao';

  @override
  String get prefsShowOnHomeHint => 'Band ho to sirf diet dikhegi';

  @override
  String get cookSyncDropped => 'Kuch badlav bheje nahi ja sake — ticket pehle hi badal gaya tha';

  @override
  String get settingsLogout => 'Log out karo';

  @override
  String get statusUnknown => 'Update karo';

  @override
  String get cookHindiVoiceMissing => 'Hindi awaaz install karein';

  @override
  String get cookHindiVoiceHint => 'Phone Settings → Bhasha → Text-to-speech mein Hindi chuno.';

  @override
  String get cookOpenSettings => 'Settings kholo';

  @override
  String get cookAudioError => 'Awaaz nahi chal payi';

  @override
  String get subStatusUnknown => 'Status pata nahi chala';

  @override
  String get videoOpenFailed => 'Video nahi khul paya';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsLightAnimations => 'Halki animation';

  @override
  String get settingsLightAnimationsHint => 'Purane ya dheeme phone ke liye: thali ghoomegi nahi';

  @override
  String get cookLanguage => 'Cook mode ki bhasha';

  @override
  String get settingsFamilyOnBanega => 'Banega par parivaar';

  @override
  String get invitesHint => 'Ghar ke bade apne phone se Banega chala sakte hain.';

  @override
  String get invitesEmpty => 'Abhi koi invite pending nahi';

  @override
  String get inviteCta => 'Parivaar ke kisi ko bulao';

  @override
  String invitePendingRow(String phone, String date) {
    return '$phone · $date tak';
  }

  @override
  String inviteFor(String name) {
    return '$name ke liye';
  }

  @override
  String get inviteRevoke => 'Hatao';

  @override
  String get inviteRevokeAsk => 'Ye invite band kar dein? Purana code kaam nahi karega.';

  @override
  String get inviteRevoked => 'Invite band kar diya';

  @override
  String get inviteWho => 'Kaun hain?';

  @override
  String get inviteNewMember => 'Naya member';

  @override
  String get inviteNewName => 'Naam';

  @override
  String get invitePhone => 'Unka phone number';

  @override
  String get inviteRoleNote => 'Bade member ki tarah judenge: menu dekh aur badal sakte hain, cook ko bhej sakte hain.';

  @override
  String get inviteCreate => 'Invite banao';

  @override
  String get inviteNameRequired => 'Naam likho';

  @override
  String get inviteCodeTitle => 'Ye code bhejo';

  @override
  String inviteCodeBody(String phone) {
    return '$phone se login karke \"Code se judiye\" chunein aur ye code daalein.';
  }

  @override
  String inviteCodeExpires(String date) {
    return '$date tak chalega';
  }

  @override
  String inviteCodeLabel(String code) {
    return 'Invite code $code';
  }

  @override
  String get inviteShareWhatsApp => 'WhatsApp par bhejo';

  @override
  String get inviteCopy => 'Code copy karo';

  @override
  String get inviteCopied => 'Code copy ho gaya';

  @override
  String get inviteDone => 'Ho gaya';

  @override
  String get inviteErrPhoneTaken => 'Ye number kisi aur ghar mein cook hai.';

  @override
  String get householdOr => 'ya';

  @override
  String get householdJoinOption => 'Code se judiye';

  @override
  String get householdJoinHint => 'Ghar walon ne Banega par bulaya hai? Unka bheja code daaliye.';

  @override
  String get joinTitle => 'Parivaar se judiye';

  @override
  String get joinBody => 'WhatsApp par aaya 6 akshar ka code daaliye.';

  @override
  String get joinCta => 'Judiye';

  @override
  String joinCodeBox(int n) {
    return 'Code ka akshar $n';
  }

  @override
  String get joinCreateInstead => 'Naya ghar banao';

  @override
  String get joinErrInvalid => 'Ye code sahi nahi hai. Message dekh kar dobara daaliye.';

  @override
  String get joinErrExpired => 'Ye code purana ho gaya. Ghar ke admin se naya code maangiye.';

  @override
  String get joinErrPhone => 'Ye code kisi aur number ke liye hai. Usi number se login kijiye jis par invite aaya.';

  @override
  String get joinErrAlready => 'Aapka number pehle se ek ghar mein hai.';

  @override
  String get joinErrLocked => 'Bahut baar galat code. Thodi der baad try kijiye.';

  @override
  String get ticketUnassignedTitle => 'Abhi kisi ko nahi diya';

  @override
  String get ticketUnassignedHint => 'Kaun banayega? Cook chuniye ya khud le lijiye.';

  @override
  String get ticketUnassignedCard => 'Kaun banayega? Tap karke chuniye';

  @override
  String get ticketAssignTo => 'Kisko dein…';

  @override
  String get ticketClaim => 'Main banaunga';

  @override
  String get ticketClaimed => 'Aaj ke chef aap! Rasoi tab mein dekhiye.';

  @override
  String get ticketAlreadyClaimed => 'Ye ticket kisi aur ne le liya.';

  @override
  String ticketAssignedToast(String name) {
    return '$name ko de diya';
  }

  @override
  String get ticketAssigneeRequired => 'Chuniye kaun banayega';

  @override
  String get ticketNoCooks => 'Abhi koi cook nahi jodi. Settings mein jodiye.';

  @override
  String get eventTicketUnassigned => 'Ticket kisi ko nahi diya';

  @override
  String get eventTicketCancelled => 'Ticket cancel hua';

  @override
  String get eventCookMessage => 'Cook ka message';

  @override
  String get eventFamilyMessage => 'Parivaar ka message';

  @override
  String get eventChefClaimed => 'Kisi ne aaj banana chuna';

  @override
  String get eventCookOnDuty => 'Cook wapas on duty';

  @override
  String get eventRationBought => 'Ration kharid liya';

  @override
  String get eventStockIssueResolved => 'Saaman ki dikkat suljhi';

  @override
  String get eventExportReady => 'Data export taiyaar';

  @override
  String get eventAtRisk => 'Khaana late ho sakta hai';
}
