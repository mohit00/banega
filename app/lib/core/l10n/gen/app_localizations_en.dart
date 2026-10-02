// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Banega';

  @override
  String get wordmark => 'banega';

  @override
  String get aiMaharajBadge => 'AI MAHARAJ';

  @override
  String get thaliAlt => 'A home-style thali';

  @override
  String get back => 'Back';

  @override
  String get splashTitle => 'What\'s cooking\ntoday?';

  @override
  String get splashBody =>
      'Every home\'s daily question. An AI that remembers what your whole family likes, and gives options for every meal.';

  @override
  String get splashCta => 'Set up your home';

  @override
  String get splashDemo => 'Try it with a demo family';

  @override
  String get stepOneOfTwo => 'STEP 1 OF 2';

  @override
  String get familyTitle => 'Who\'s in\nyour home?';

  @override
  String get familyBody => 'Everyone likes something different. Tap to set it up; Maharaj will remember.';

  @override
  String get addMember => 'Add member';

  @override
  String familyCta(int count) {
    return '$count people · Continue';
  }

  @override
  String spiceSummary(String spice) {
    return '$spice spice';
  }

  @override
  String get prefsStep => 'STEP 2 OF 2 · PREFERENCES';

  @override
  String prefsTitle(String name) {
    return '$name\'s preferences';
  }

  @override
  String get prefsSubtitle => 'Maharaj will suggest meals to match';

  @override
  String get prefsDietTitle => 'What do they eat?';

  @override
  String get prefsSpiceTitle => 'How spicy?';

  @override
  String get prefsNeedsTitle => 'Any needs or restrictions?';

  @override
  String get prefsCuisineTitle => 'Favourite cuisines';

  @override
  String prefsSave(String name) {
    return 'Save · $name';
  }

  @override
  String get dietVeg => 'Veg';

  @override
  String get dietVegHint => 'Vegetarian';

  @override
  String get dietJain => 'Jain';

  @override
  String get dietJainHint => 'No onion or garlic';

  @override
  String get dietEgg => 'Egg';

  @override
  String get dietEggHint => 'Veg + eggs';

  @override
  String get dietNonveg => 'Non-veg';

  @override
  String get dietNonvegHint => 'Everything';

  @override
  String get dietJainFriendly => 'Jain-friendly';

  @override
  String get spiceKam => 'Mild';

  @override
  String get spiceMedium => 'Medium';

  @override
  String get spiceTeekha => 'Hot';

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
  String get loadingTitle => 'Maharaj is getting to\nknow your home…';

  @override
  String constraintLine(String items) {
    return 'Kept in mind: $items';
  }

  @override
  String get constraintNone => 'Everyone\'s preferences are in mind';

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
    return '$name (mild)';
  }

  @override
  String get householdName => 'Purohit Family';

  @override
  String familyLine(int count, String items) {
    return '$count people · $items';
  }

  @override
  String get slotBreakfast => 'Breakfast';

  @override
  String get slotLunch => 'Lunch';

  @override
  String get slotDinner => 'Dinner';

  @override
  String get eyebrowBreakfast => 'MORNING BREAKFAST';

  @override
  String get eyebrowLunch => 'AFTERNOON LUNCH';

  @override
  String get eyebrowDinner => 'TONIGHT\'S DINNER';

  @override
  String get searchPrefix => 'Ask';

  @override
  String get tickerAsk1 => '“breakfast in 15 min”';

  @override
  String get tickerAsk2 => '“Jain dinner for Dadi”';

  @override
  String get tickerAsk3 => '“rainy-day food”';

  @override
  String get tickerAsk4 => '“Daughter\'s tiffin”';

  @override
  String get maharajPick => 'MAHARAJ\'S PICK';

  @override
  String heroMeta(String fitLabel, int mins) {
    return '$fitLabel · $mins min';
  }

  @override
  String get recipeDekho => 'See recipe';

  @override
  String get quickAsk15Min => 'Something in 15 min';

  @override
  String get quickAskHalka => 'Something light';

  @override
  String get quickAskBaarish => 'Rainy-day special';

  @override
  String get quickAskTiffin => 'Daughter\'s tiffin';

  @override
  String get quickAskMehmaan => 'Guests are coming';

  @override
  String get quickAskProtein => 'High protein';

  @override
  String slotOptions(String slot) {
    return 'Options for $slot';
  }

  @override
  String get sabkeHisaab => 'for everyone';

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
    return '$count dish · Today\'s menu';
  }

  @override
  String get cookKoBhejo => 'Send to cook';

  @override
  String get navGhar => 'Home';

  @override
  String get navMaharaj => 'Ask Maharaj';

  @override
  String get navParivaar => 'Family';

  @override
  String get chatName => 'Maharaj';

  @override
  String chatMemory(int count) {
    return 'Remembers what $count people like';
  }

  @override
  String chatMenuPill(int count) {
    return 'Menu · $count';
  }

  @override
  String chatGreeting(int count) {
    return 'Namaste! I\'m Maharaj. I remember what the $count people in your home like.\nJust ask: what should I make today?';
  }

  @override
  String get chatChipLunch => 'What\'s for lunch today?';

  @override
  String get chatChipHalkaDinner => 'A light dinner';

  @override
  String get chatChipNashta => 'Breakfast in 15 min';

  @override
  String get chatChipMehmaan => 'Guests are coming';

  @override
  String get chatPlaceholder => 'Something light for dinner…';

  @override
  String get chatVoice => 'Voice';

  @override
  String get chatSend => 'Send';

  @override
  String get typing => 'rolling out the rotis…';

  @override
  String get voiceToast => 'Voice input: in the real app you can speak in Hinglish';

  @override
  String get chatError => 'Maharaj couldn\'t answer just now. Ask again.';

  @override
  String get chatInputLabel => 'Ask Maharaj';

  @override
  String chatNoMatch(String slot) {
    return 'No exact match for that combination. These are the closest for $slot:';
  }

  @override
  String chatOptions(String slot, int count) {
    return '$count options for $slot';
  }

  @override
  String chatOptionsWhy(String options, String why) {
    return '$options — $why';
  }

  @override
  String chatFamilyCan(int ok) {
    return 'The whole family can eat $ok.';
  }

  @override
  String get whyHalka => 'light';

  @override
  String get whyProtein => 'high protein';

  @override
  String get whyMehmaan => 'good for guests';

  @override
  String get whyBaarish => 'rainy-day';

  @override
  String get whyKid => 'kids love it';

  @override
  String get why20Min => 'under 20 min';

  @override
  String get whyPaneer => 'with paneer';

  @override
  String whyMember(String name) {
    return 'suits $name';
  }

  @override
  String get followProteinNashta => 'High-protein breakfast';

  @override
  String get followTiffin => 'Daughter\'s tiffin';

  @override
  String get followSouth => 'Something South Indian';

  @override
  String get followHalka => 'Something light';

  @override
  String get followBaarish => 'Rainy-day special';

  @override
  String get followPaneer => 'Something with paneer';

  @override
  String get followDadi => 'What for Dadi?';

  @override
  String get fitAllPerfect => 'Perfect for everyone';

  @override
  String get fitAllPerfectShort => 'For everyone';

  @override
  String fitAllTweak(int count) {
    return 'For everyone · $count tweak';
  }

  @override
  String fitAllTweakShort(int count) {
    return 'All · $count tweak';
  }

  @override
  String fitPartial(int can, int total) {
    return 'For $can/$total';
  }

  @override
  String fitNotFor(String names) {
    return 'Not for $names';
  }

  @override
  String get fitAllHappy => 'Everyone\'s happy, no changes';

  @override
  String fitTweakNote(String name, String note) {
    return '$name: $note';
  }

  @override
  String get reasonOnionGarlic => 'Has onion and garlic';

  @override
  String get reasonEgg => 'Has egg';

  @override
  String get reasonNonveg => 'It\'s non-veg';

  @override
  String get reasonMaida => 'Has maida';

  @override
  String get reasonLessChilli => 'Less chilli in their bowl';

  @override
  String get reasonExtraChilli => 'Red chilli / pickle on top';

  @override
  String get reasonLowSugar => 'Smaller portion, more salad';

  @override
  String get reasonLowOil => 'Cook it with less oil';

  @override
  String get reasonProtein => 'Serve with curd / paneer';

  @override
  String get reasonKid => 'A separate, milder bowl for the child';

  @override
  String get reasonFavCuisine => 'A favourite cuisine too';

  @override
  String get reasonPerfect => 'Just right';

  @override
  String get verdictPerfect => 'Perfect';

  @override
  String get verdictTweak => 'Tweak';

  @override
  String get verdictNo => 'No';

  @override
  String detailMeta(String diet, String cuisine, int mins) {
    return '$diet · $cuisine · $mins min';
  }

  @override
  String get kaunKhayega => 'Who\'s eating';

  @override
  String get saaman => 'Ingredients';

  @override
  String get kaiseBanega => 'How to make it';

  @override
  String get videoRecipe => 'Video recipe';

  @override
  String get menuMeinDaalo => 'Add to menu';

  @override
  String get menuMeinHai => 'On the menu';

  @override
  String planTitle(String slot) {
    return 'Today\'s $slot menu';
  }

  @override
  String planSubtitle(int count, String coverage) {
    return 'For $count people · $coverage';
  }

  @override
  String get planCoverageAll => 'there\'s something for every member';

  @override
  String get planCoverageSome => 'some members need another dish';

  @override
  String get planEmpty => 'The menu is empty. ADD dishes from Home.';

  @override
  String get planSaamanList => 'Shopping list';

  @override
  String get planSendCook => 'Send to Maharaj / cook';

  @override
  String get planOrderMissing => 'Order missing items';

  @override
  String get toastSentCook => 'Menu and shopping list sent to the cook on WhatsApp';

  @override
  String get toastMissingCart => 'Missing items added to the cart';

  @override
  String get galleryTitle => 'Component gallery';

  @override
  String get dietNoOnionGarlic => 'No onion-garlic';

  @override
  String get dietNoOnionGarlicHint => 'Veg, without onion or garlic';

  @override
  String get dietPescatarian => 'Pescatarian';

  @override
  String get dietPescatarianHint => 'Veg + fish';

  @override
  String reasonAllergen(String item) {
    return 'Allergic to $item';
  }

  @override
  String get reasonRootVeg => 'Has root vegetables';

  @override
  String reasonNonvegItem(String item) {
    return 'Has $item';
  }

  @override
  String get reasonDairy => 'Has dairy';

  @override
  String reasonDislikeMain(String item) {
    return 'They don\'t like $item';
  }

  @override
  String reasonDislikeSkip(String item) {
    return 'Leave $item out of their bowl';
  }

  @override
  String get reasonVrat => 'Fasting today';

  @override
  String get allergenPeanut => 'Peanut';

  @override
  String get allergenTreeNut => 'Tree nuts';

  @override
  String get allergenDairy => 'Dairy';

  @override
  String get allergenGluten => 'Wheat (gluten)';

  @override
  String get allergenEgg => 'Egg';

  @override
  String get allergenFish => 'Fish';

  @override
  String get allergenSesame => 'Sesame';

  @override
  String get allergenSoy => 'Soy';

  @override
  String get demoDataPill => 'Demo data';

  @override
  String servingsCount(int count) {
    return '$count people';
  }

  @override
  String get servingsLess => 'Fewer people';

  @override
  String get servingsMore => 'More people';

  @override
  String get batchWarning => 'Cook this in two batches for this many people';

  @override
  String get homeLoadError => 'Couldn\'t load options';

  @override
  String get retry => 'Retry';

  @override
  String get navRasoi => 'Kitchen';

  @override
  String get slotTiffin => 'Tiffin';

  @override
  String get slotShaam => 'Evening snack';

  @override
  String get dateToday => 'Today';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String planTitleOn(String day, String slot) {
    return '$slot menu for $day';
  }

  @override
  String planCoverageMissing(String names) {
    return '$names need another dish';
  }

  @override
  String get planLoadError => 'Couldn\'t load the menu';

  @override
  String get planEatersTitle => 'Who\'s eating?';

  @override
  String get planGuestAdults => 'Guests · adults';

  @override
  String get planGuestKids => 'Guests · kids';

  @override
  String get planGuestDiet => 'Guests\' diet';

  @override
  String get planServingsTitle => 'How many servings';

  @override
  String planServingsValue(String servings) {
    return '$servings servings';
  }

  @override
  String get planServingsHint => 'Adult 1 · kid ½ · guests added';

  @override
  String get planDueTitle => 'Ready by';

  @override
  String get planDueHint => 'When the food should be ready';

  @override
  String get planAssigneeTitle => 'Who\'s cooking';

  @override
  String get planAssigneeNone => 'Nobody';

  @override
  String cookChipLabel(String name, String kind) {
    return '$name ($kind)';
  }

  @override
  String get cookKindHired => 'hired';

  @override
  String get cookKindFamily => 'family';

  @override
  String get cookOffDutyTag => 'Off duty';

  @override
  String get planViewTicket => 'View ticket';

  @override
  String get planShareWhatsApp => 'Also send on WhatsApp';

  @override
  String get removeDish => 'Remove';

  @override
  String get toastTicketSent => 'Ticket sent';

  @override
  String get toastOrderSoon => 'Ordering groceries is coming soon';

  @override
  String get toastError => 'Something went wrong, try again';

  @override
  String get toastConflict => 'The ticket changed — showing the latest';

  @override
  String get itemIn => 'In stock';

  @override
  String get itemLow => 'Low';

  @override
  String get itemOut => 'Out';

  @override
  String get itemUntracked => 'Not tracked';

  @override
  String get statusNew => 'New';

  @override
  String get statusUnassigned => 'Unassigned';

  @override
  String get statusAccepted => 'Accepted';

  @override
  String get statusCooking => 'Cooking';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusCompleted => 'Done';

  @override
  String get statusNotConfirmed => 'Not confirmed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get ticketTitle => 'Ticket';

  @override
  String ticketCardTitle(String slot) {
    return '$slot ticket';
  }

  @override
  String dueBy(String time) {
    return 'Ready by $time';
  }

  @override
  String get ticketNoAssignee => 'Not assigned';

  @override
  String ticketGuests(int count) {
    return '+$count guests';
  }

  @override
  String get ticketDishes => 'Dishes';

  @override
  String get ticketNotes => 'Note';

  @override
  String get ticketNotesHint => 'A note for the cook…';

  @override
  String get ticketChangeLog => 'Change log';

  @override
  String get ticketEdit => 'Edit';

  @override
  String get ticketSave => 'Save';

  @override
  String get ticketSavedToast => 'Ticket updated';

  @override
  String get ticketCancel => 'Cancel ticket';

  @override
  String get ticketCancelReason => 'Why cancel?';

  @override
  String get ticketCancelReasonHint => 'Write a reason';

  @override
  String get ticketCancelConfirm => 'Yes, cancel';

  @override
  String get ticketKeep => 'Keep it';

  @override
  String get ticketCancelledToast => 'Ticket cancelled';

  @override
  String get ticketMarkDone => 'Mark done';

  @override
  String get ticketAskCook => 'Message the cook';

  @override
  String get ticketUpdatedTag => 'Updated';

  @override
  String get ticketStockIssueTag => 'Item out';

  @override
  String get ticketLoadError => 'Couldn\'t load the ticket';

  @override
  String get khanaBanaPrompt => 'Was the meal cooked?';

  @override
  String get khanaBanaHint => 'The cook didn\'t mark it done. Tell us so records stay right.';

  @override
  String get khanaBanaYes => 'Yes, it was';

  @override
  String get khanaBanaNo => 'No';

  @override
  String get logCreated => 'Created';

  @override
  String get logAccepted => 'Accepted';

  @override
  String get logCooking => 'Started cooking';

  @override
  String get logReady => 'Ready';

  @override
  String get logCompleted => 'Done';

  @override
  String get logCancelled => 'Cancelled';

  @override
  String get logNotConfirmed => 'Not confirmed';

  @override
  String get logUpdated => 'Edited';

  @override
  String get logItemOut => 'Item out';

  @override
  String get logClaimed => 'Claimed';

  @override
  String get logReassigned => 'Reassigned';

  @override
  String get logUnassigned => 'Unassigned';

  @override
  String get logAutoCancelled => 'Auto-cancelled';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String inboxBellUnread(int count) {
    return 'Inbox, $count new';
  }

  @override
  String get inboxEmpty => 'Nothing new';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsDemoCook => 'Demo: cook role';

  @override
  String get settingsDemoCookHint => 'With a cook role the \'Rasoi\' tab (cook mode) appears in the bottom bar.';

  @override
  String get cookTitle => 'Today\'s tickets';

  @override
  String get cookTabToday => 'Today';

  @override
  String get cookTabTomorrow => 'Tomorrow';

  @override
  String cookDueBy(String time) {
    return 'Ready by $time';
  }

  @override
  String get cookActionAccept => 'Accept';

  @override
  String get cookActionStart => 'Start cooking';

  @override
  String get cookActionDone => 'Done';

  @override
  String get cookActionReady => 'Ready';

  @override
  String get cookEmpty => 'No tickets';

  @override
  String get cookOnDuty => 'On duty';

  @override
  String get cookOffDuty => 'Off duty';

  @override
  String cookOffDutyUntil(String date) {
    return 'Off until $date';
  }

  @override
  String get cookOffDutyAsk => 'Off until when?';

  @override
  String get cookOffDutyToday => 'Just today';

  @override
  String get cookOffDutyTomorrow => 'Until tomorrow';

  @override
  String get cookOffDutyPick => 'Pick a date';

  @override
  String get cookFamilyMode => 'Family';

  @override
  String get cookOffline => 'Offline — showing saved tickets';

  @override
  String get cookNotSent => 'Not sent yet';

  @override
  String get cookQueued => 'Will send when online';

  @override
  String get cookDishes => 'What to cook';

  @override
  String get cookEaters => 'Who\'s eating';

  @override
  String cookServings(String servings) {
    return 'For $servings';
  }

  @override
  String cookGuests(int count) {
    return '+$count guests';
  }

  @override
  String get cookNotes => 'Note';

  @override
  String get cookItems => 'Needed items';

  @override
  String get cookItemOut => 'It\'s out';

  @override
  String get cookAskFamily => 'Ask the family';

  @override
  String get cookOpenRecipe => 'Recipe';

  @override
  String get cookIngredients => 'Ingredients';

  @override
  String get cookSteps => 'Steps';

  @override
  String get cookPlay => 'Listen';

  @override
  String get cookPause => 'Stop';

  @override
  String get cookSpeed => 'Voice speed';

  @override
  String get cookSpeedSlow => 'Slow';

  @override
  String get cookSpeedNormal => 'Normal';

  @override
  String get cookSpeedFast => 'Fast';

  @override
  String get cookThread => 'Talk to the family';

  @override
  String get cookThreadHint => 'Write a message…';

  @override
  String get cookSend => 'Send';

  @override
  String get cookThreadEmpty => 'No messages yet';

  @override
  String get cookConflict => 'The ticket changed — showing the latest';

  @override
  String get cookError => 'Something went wrong';

  @override
  String get cookLoadError => 'Couldn\'t load — try again';

  @override
  String get stockTitle => 'Kitchen stock';

  @override
  String stockSubtitle(int count, int low) {
    return '$count items · $low low or out';
  }

  @override
  String get stockSearchHint => 'Search: dahi, pyaaz…';

  @override
  String get stockFilterAll => 'All';

  @override
  String get stockFilterLowOut => 'Low + Out';

  @override
  String get stockAllIn => 'Mark all In';

  @override
  String get stockAllInDone => 'All marked In';

  @override
  String get stockLevelIn => 'In';

  @override
  String get stockLevelLow => 'Low';

  @override
  String get stockLevelOut => 'Out';

  @override
  String get stockEmpty => 'Nothing found';

  @override
  String get stockLoadError => 'Couldn\'t load stock';

  @override
  String get stockCatSabzi => 'Vegetables';

  @override
  String get stockCatDairy => 'Dairy';

  @override
  String get stockCatDal => 'Lentils';

  @override
  String get stockCatAnaaj => 'Grains';

  @override
  String get stockCatMasale => 'Spices';

  @override
  String get stockCatTelGhee => 'Oil & ghee';

  @override
  String get stockCatDryFruits => 'Dry fruits';

  @override
  String get stockCatOther => 'Other';

  @override
  String get rationTitle => 'Ration';

  @override
  String get rationTabPending => 'Pending';

  @override
  String get rationTabApproved => 'Approved';

  @override
  String get rationTabBought => 'Bought';

  @override
  String get rationEmpty => 'No requests';

  @override
  String rationRaisedBy(String name) {
    return 'Asked by $name';
  }

  @override
  String rationItems(int count) {
    return '$count items';
  }

  @override
  String get rationApprove => 'Approve';

  @override
  String get rationReject => 'Reject';

  @override
  String get rationNoteHint => 'Note (optional)';

  @override
  String get rationBought => 'Bought';

  @override
  String get rationStatusPending => 'Pending';

  @override
  String get rationStatusApproved => 'Approved';

  @override
  String get rationStatusRejected => 'Rejected';

  @override
  String get rationStatusBought => 'Bought';

  @override
  String get rationApprovedToast => 'Approved';

  @override
  String get rationRejectedToast => 'Rejected';

  @override
  String get rationBoughtToast => 'Items are back in stock';

  @override
  String get rationSentToast => 'Ration request sent';

  @override
  String get rationNothingMissing => 'Everything is in stock';

  @override
  String get rationSelfApproved => 'Self-approved';

  @override
  String get cookRasoi => 'Kitchen';

  @override
  String get cookRationAsk => 'Ask for ration';

  @override
  String get cookRationTitle => 'My ration requests';

  @override
  String get cookRationSheetTitle => 'What do you need?';

  @override
  String get cookRationFreeHint => 'Anything else? Type it';

  @override
  String get cookRationAdd => 'Add';

  @override
  String get cookRationSend => 'Send';

  @override
  String get cookRationSent => 'Request sent';

  @override
  String get cookRationNew => 'New request';

  @override
  String ladderTitle(String item) {
    return '$item is out';
  }

  @override
  String ladderSkipAsk(String item) {
    return 'Make it without $item?';
  }

  @override
  String get ladderSkipYes => 'Yes, without it';

  @override
  String get ladderMoreWays => 'Other options';

  @override
  String get ladderSwapTitle => 'What can replace it?';

  @override
  String get ladderSwapDo => 'Swap it';

  @override
  String get ladderNoSwap => 'No safe swap found';

  @override
  String get ladderChangeDish => 'Change the dish';

  @override
  String get ladderDishTitle => 'Cook one of these instead?';

  @override
  String get ladderDishPick => 'Cook this';

  @override
  String get ladderNoDish => 'No other dish is in stock';

  @override
  String get ladderPending => 'Asking the family…';

  @override
  String ladderPendingHint(int mins) {
    return 'If nobody answers in $mins min, the admin is alerted';
  }

  @override
  String get ladderTimeout => 'Timed out — the admin was alerted';

  @override
  String get ladderDone => 'Done — ticket updated';

  @override
  String get ladderRejected => 'The family said no — pick another option';

  @override
  String get ladderOpen => 'See options';

  @override
  String get ladderClose => 'Close';

  @override
  String get approvalTitle => 'Your approval needed';

  @override
  String approvalSwap(String detail) {
    return 'Swap: $detail';
  }

  @override
  String approvalChangeDish(String detail) {
    return 'Change dish: $detail';
  }

  @override
  String approvalAskedBy(String name) {
    return 'Asked by $name';
  }

  @override
  String approvalExpires(String time) {
    return 'Answer by $time';
  }

  @override
  String get approvalYes => 'Yes';

  @override
  String get approvalNo => 'No';

  @override
  String get approvalApprovedToast => 'Approved — the cook is told';

  @override
  String get approvalRejectedToast => 'Declined — the cook is told';

  @override
  String get approvalGone => 'This request is already closed';

  @override
  String get ticketIssueChoosing => 'The cook is choosing an option';

  @override
  String ticketIssuePending(String detail) {
    return 'The cook asks: $detail';
  }

  @override
  String get ticketRate => 'How was it?';

  @override
  String get ticketRated => 'Rated — thanks!';

  @override
  String get logSkip => 'Made without it';

  @override
  String get logSwap => 'Ingredient swapped';

  @override
  String get logChangeDish => 'Dish changed';

  @override
  String get logApprovalRequested => 'Asked the family';

  @override
  String get logApproved => 'Family approved';

  @override
  String get logRejected => 'Family declined';

  @override
  String get logTimeout => 'Timed out — admin alerted';

  @override
  String rateTitle(String slot) {
    return 'How was $slot?';
  }

  @override
  String rateThanksFamily(String name) {
    return '$name cooked — say thank you!';
  }

  @override
  String get rateHint => 'One tap for each person who ate';

  @override
  String get rateBura => 'Not good';

  @override
  String get rateTheek => 'Okay';

  @override
  String get rateBahutAccha => 'Loved it';

  @override
  String get rateProxy => 'On their behalf';

  @override
  String get rateNoteHint => 'Anything to add? (optional)';

  @override
  String get rateNoteHintFamily => 'Anything to change next time?';

  @override
  String get rateSubmit => 'Send rating';

  @override
  String get rateSubmitFamily => 'Send thanks';

  @override
  String get rateDone => 'Thanks! Maharaj will remember';

  @override
  String get rateNeedOne => 'Rate at least one person';

  @override
  String get recipeHomeRating => 'Family rating';

  @override
  String recipeRatingValue(String avg, int count) {
    return '$avg/3 · $count ratings';
  }

  @override
  String trialBanner(int days) {
    return 'Free trial · $days days left';
  }

  @override
  String get graceBanner => 'Payment failed — fix it within 3 days';

  @override
  String get expiredBanner => 'Plan ended — view only';

  @override
  String get planBandTitle => 'Your plan has ended';

  @override
  String get planBandBody =>
      'Start the ₹50/week plan to plan menus, chat with Maharaj and send tickets. Today\'s and tomorrow\'s tickets still work for the cook.';

  @override
  String get planBandCta => 'See plans';

  @override
  String get weeklyTitle => 'This week';

  @override
  String weeklyTop(String name) {
    return 'Top: $name';
  }

  @override
  String weeklyOnTime(String pct) {
    return '$pct% on time';
  }

  @override
  String weeklyCoverage(String pct) {
    return '$pct% suited everyone';
  }

  @override
  String weeklyMeals(int count) {
    return '$count meals cooked';
  }

  @override
  String get paywallTitle => 'Banega plan';

  @override
  String get paywallPrice => '₹50/week';

  @override
  String get paywallBody => 'Everything for the whole family, one plan.';

  @override
  String get paywallFeature1 => 'Options that suit everyone, every meal';

  @override
  String get paywallFeature2 => 'Tickets, stock and ration for your cook';

  @override
  String get paywallFeature3 => 'Maharaj learns from your ratings';

  @override
  String get paywallSubscribe => 'Start · ₹50/week';

  @override
  String get paywallRestore => 'Restore purchases';

  @override
  String get paywallRestored => 'Purchases restored';

  @override
  String get paywallActive => 'Your plan is active';

  @override
  String paywallRenews(String date) {
    return 'Renews $date';
  }

  @override
  String paywallTrial(int days) {
    return 'Free trial: $days days left';
  }

  @override
  String get paywallGrace => 'Payment failed — update it in the store';

  @override
  String get paywallSubscribed => 'You\'re subscribed — thank you!';

  @override
  String get paywallStoreSoon => 'Store billing is coming soon';

  @override
  String get paywallCancelNote => 'Cancel anytime in Play Store / App Store';

  @override
  String get subStatusTrial => 'Free trial';

  @override
  String get subStatusActive => 'Active';

  @override
  String get subStatusGrace => 'Payment issue';

  @override
  String get subStatusExpired => 'Ended';

  @override
  String get consentTitle => 'Your data, your choice';

  @override
  String get consentBody =>
      'Banega keeps your family\'s preferences, allergies and meal history only to plan menus, send tickets to your cook and power Maharaj\'s suggestions. Your data is never sold. You can export or delete it any time from Settings.';

  @override
  String get consentLlmNote =>
      'Maharaj chat questions are sent to an AI service; names and phone numbers are not sent with them.';

  @override
  String get consentKids => 'You add kids\' profiles as their parent or guardian.';

  @override
  String get consentAccept => 'I agree';

  @override
  String get consentPrivacy => 'Read the privacy policy';

  @override
  String get settingsHousehold => 'Household';

  @override
  String get settingsHouseholdName => 'Household name';

  @override
  String get settingsEdit => 'Edit';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsSaved => 'Saved';

  @override
  String get settingsMembers => 'Family members';

  @override
  String get settingsCooks => 'Cooks';

  @override
  String get settingsCookPrimary => 'Primary';

  @override
  String get settingsCookBackup => 'Backup';

  @override
  String get settingsCookRemove => 'Remove';

  @override
  String settingsCookRemoveAsk(String name) {
    return 'Remove $name? Their open tickets become unassigned.';
  }

  @override
  String get settingsAddHiredCook => 'Add a hired cook';

  @override
  String get settingsCookName => 'Name';

  @override
  String get settingsCookPhone => 'Phone number';

  @override
  String settingsCookAdded(String name) {
    return '$name added';
  }

  @override
  String get settingsHiredLimit => 'Only one hired cook per household';

  @override
  String get settingsPhoneTaken => 'This phone belongs to another household';

  @override
  String get settingsInvalidPhone => 'Enter a valid phone number';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageHint => 'Cook mode opens in Hindi; the cook can change it there';

  @override
  String get langHinglish => 'Hinglish';

  @override
  String get langEnglish => 'English';

  @override
  String get langHindi => 'हिंदी';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotifMandatory => 'Required — always on';

  @override
  String get settingsRatings => 'Ratings';

  @override
  String get settingsRatingsHint => 'Ask \'How was it?\' after meals. A family cook can turn this off.';

  @override
  String get settingsAutoDecrement => 'Lower stock after each meal';

  @override
  String get settingsAutoDecrementHint => 'Fresh items (curd, veg) drop to Low';

  @override
  String get settingsShowNames => 'Show names to the cook in ratings';

  @override
  String get settingsShowNamesHint => 'When off, the cook sees averages only';

  @override
  String get settingsCookSwaps => 'Cook can approve swaps';

  @override
  String get settingsCookSwapsHint => 'When off, every swap needs your approval';

  @override
  String get settingsKitchen => 'Kitchen';

  @override
  String get settingsSubscription => 'Subscription';

  @override
  String get settingsPrivacy => 'Privacy & data';

  @override
  String get settingsConsent => 'Review consent';

  @override
  String get settingsGrievance => 'Grievance contact: privacy@banega.app';

  @override
  String get settingsExport => 'Export my data';

  @override
  String get settingsExportToast => 'A download link will arrive in your inbox';

  @override
  String get settingsDeleteHousehold => 'Delete household';

  @override
  String get settingsDeleteHouseholdAsk =>
      'All household data (members, menus, tickets, ratings, stock) is erased for good after 7 days. You can undo with \'Restore\' until then. Cancel the store subscription separately.';

  @override
  String get settingsDeleteConfirm => 'Yes, delete';

  @override
  String settingsDeletePending(String date) {
    return 'Household will be deleted on $date';
  }

  @override
  String get settingsRestore => 'Restore';

  @override
  String get settingsRestored => 'Household restored';

  @override
  String get settingsDeleteMe => 'Delete my account';

  @override
  String get settingsDeleteMeAsk =>
      'Your login is removed; the household and other members stay. You can undo within 7 days.';

  @override
  String get settingsDeletedMe => 'Account deleted — you can restore it within 7 days';

  @override
  String get eventTicketCreated => 'New ticket';

  @override
  String get eventTicketAccepted => 'Ticket accepted';

  @override
  String get eventTicketUpdated => 'Ticket changed';

  @override
  String get eventTicketCompleted => 'Meal cooked';

  @override
  String get eventNotConfirmed => '\'Was it cooked?\' prompt';

  @override
  String get eventCookOffDuty => 'Cook off duty';

  @override
  String get eventNoShow => 'Cook has not accepted';

  @override
  String get eventStockLow => 'Stock low';

  @override
  String get eventRationRequest => 'Ration request';

  @override
  String get eventRationDecided => 'Ration decision';

  @override
  String get eventStockIssue => 'Ingredient out';

  @override
  String get eventApprovalRequest => 'Approval request';

  @override
  String get eventApprovalDecided => 'Approval decision';

  @override
  String get eventStockTimeout => 'Approval timed out';

  @override
  String get eventRatePrompt => 'Rate a meal';

  @override
  String get eventExpiry => 'Plan reminder';

  @override
  String get eventWeekly => 'Weekly summary';

  @override
  String get eventTomorrow => 'Tomorrow\'s tickets';

  @override
  String get offlineBanner => 'You\'re offline. Showing what was loaded before.';

  @override
  String get offlineRetry => 'Retry';

  @override
  String get authPhoneTitle => 'Your number';

  @override
  String get authPhoneBody => 'We\'ll send a one-time code. Your number is only used to sign in.';

  @override
  String get authPhoneHint => '10-digit mobile number';

  @override
  String get authSendOtp => 'Send OTP';

  @override
  String get authPhoneInvalid => 'Enter a valid 10-digit number';

  @override
  String get authOtpTitle => 'Enter the OTP';

  @override
  String authOtpBody(String phone) {
    return 'We sent a 6-digit code to $phone';
  }

  @override
  String authOtpResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authOtpResend => 'Resend OTP';

  @override
  String authOtpDevCode(String code) {
    return 'Dev code: $code';
  }

  @override
  String get authOtpWrong => 'That code didn\'t work. Try again.';

  @override
  String authOtpDigit(int index) {
    return 'OTP digit $index';
  }

  @override
  String get authVerify => 'Continue';

  @override
  String get authChangeNumber => 'Change number';

  @override
  String get householdCreateTitle => 'Name your home';

  @override
  String get householdCreateBody => 'Everyone in the family, and your cook, will see this name.';

  @override
  String get householdCreateSuffix => 'Family';

  @override
  String get householdCreateCta => 'Create home';

  @override
  String get householdNameRequired => 'Enter a name for your home';

  @override
  String get notFoundTitle => 'We couldn\'t find that page';

  @override
  String get notFoundHome => 'Go home';

  @override
  String get addMemberTitle => 'Add a member';

  @override
  String get addMemberHint => 'Name';

  @override
  String get addMemberSuggestions => 'Or pick one';

  @override
  String get addMemberCta => 'Add';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get removeMember => 'Remove member';

  @override
  String removeMemberConfirm(String name) {
    return 'Remove $name from the family?';
  }

  @override
  String get removeMemberBody => 'Their preferences will no longer count for menus.';

  @override
  String get removeMemberYes => 'Yes, remove';

  @override
  String get membersLoadError => 'Couldn\'t load your family';

  @override
  String get membersEmpty => 'No members yet. Add the first one.';

  @override
  String get memberSaveError => 'Couldn\'t save. Try again.';

  @override
  String get prefsKidTitle => 'This is a child';

  @override
  String get prefsKidHint => 'Counts as half a serving';

  @override
  String get prefsAllergensTitle => 'Allergies (never serve)';

  @override
  String get allergenMilk => 'Milk';

  @override
  String get allergenShellfish => 'Shellfish';

  @override
  String get allergenMustard => 'Mustard';

  @override
  String get prefsDislikesTitle => 'Dislikes';

  @override
  String get prefsDislikesHint => 'e.g. brinjal, bitter gourd';

  @override
  String get prefsDislikeAdd => 'Add';

  @override
  String prefsDislikeRemove(String item) {
    return 'Remove $item';
  }

  @override
  String get prefsVratTitle => 'Fasting days';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get prefsNonvegTitle => 'Non-veg limits';

  @override
  String get nonvegNoBeef => 'No beef';

  @override
  String get nonvegNoPork => 'No pork';

  @override
  String get nonvegHalalOnly => 'Halal only';

  @override
  String get prefsNoDairyTitle => 'No dairy';

  @override
  String get prefsNoDairyHint => 'Paneer, ghee and curd are left out';

  @override
  String get prefsShowOnHomeTitle => 'Show health needs on Home';

  @override
  String get prefsShowOnHomeHint => 'When off, only the diet is shown';

  @override
  String get cookSyncDropped => 'Some changes couldn\'t be sent: the ticket had already changed';

  @override
  String get settingsLogout => 'Log out';

  @override
  String get statusUnknown => 'Update the app';

  @override
  String get cookHindiVoiceMissing => 'Install a Hindi voice';

  @override
  String get cookHindiVoiceHint => 'Phone Settings → Language → Text-to-speech: add Hindi.';

  @override
  String get cookOpenSettings => 'Open settings';

  @override
  String get cookAudioError => 'Couldn\'t play the audio';

  @override
  String get subStatusUnknown => 'Status unavailable';

  @override
  String get videoOpenFailed => 'Couldn\'t open the video';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsLightAnimations => 'Light animations';

  @override
  String get settingsLightAnimationsHint => 'For older or slower phones: the thali stays still';

  @override
  String get cookLanguage => 'Cook mode language';

  @override
  String get settingsFamilyOnBanega => 'Family members on Banega';

  @override
  String get invitesHint => 'Adults at home can use Banega on their own phone.';

  @override
  String get invitesEmpty => 'No pending invites';

  @override
  String get inviteCta => 'Invite a family member';

  @override
  String invitePendingRow(String phone, String date) {
    return '$phone · until $date';
  }

  @override
  String inviteFor(String name) {
    return 'For $name';
  }

  @override
  String get inviteRevoke => 'Revoke';

  @override
  String get inviteRevokeAsk => 'Revoke this invite? The old code will stop working.';

  @override
  String get inviteRevoked => 'Invite revoked';

  @override
  String get inviteWho => 'Who is it?';

  @override
  String get inviteNewMember => 'New member';

  @override
  String get inviteNewName => 'Name';

  @override
  String get invitePhone => 'Their phone number';

  @override
  String get inviteRoleNote => 'Joins as an adult member: can see and change menus and send them to the cook.';

  @override
  String get inviteCreate => 'Create invite';

  @override
  String get inviteNameRequired => 'Enter a name';

  @override
  String get inviteCodeTitle => 'Send them this code';

  @override
  String inviteCodeBody(String phone) {
    return 'They log in with $phone, choose \"Join my family with a code\" and type this code.';
  }

  @override
  String inviteCodeExpires(String date) {
    return 'Valid until $date';
  }

  @override
  String inviteCodeLabel(String code) {
    return 'Invite code $code';
  }

  @override
  String get inviteShareWhatsApp => 'Share on WhatsApp';

  @override
  String get inviteCopy => 'Copy code';

  @override
  String get inviteCopied => 'Code copied';

  @override
  String get inviteDone => 'Done';

  @override
  String get inviteErrPhoneTaken => 'This number is a cook in another household.';

  @override
  String get householdOr => 'or';

  @override
  String get householdJoinOption => 'Join my family with a code';

  @override
  String get householdJoinHint => 'Did your family invite you? Enter the code they sent.';

  @override
  String get joinTitle => 'Join your family';

  @override
  String get joinBody => 'Enter the 6-character code from the WhatsApp message.';

  @override
  String get joinCta => 'Join';

  @override
  String joinCodeBox(int n) {
    return 'Code character $n';
  }

  @override
  String get joinCreateInstead => 'Create a new home instead';

  @override
  String get joinErrInvalid => 'That code isn\'t right. Check the message and try again.';

  @override
  String get joinErrExpired => 'This code has expired. Ask your family admin for a new one.';

  @override
  String get joinErrPhone => 'This code was sent to a different number. Log in with the number that was invited.';

  @override
  String get joinErrAlready => 'Your number already belongs to a household.';

  @override
  String get joinErrLocked => 'Too many wrong codes. Try again later.';

  @override
  String get ticketUnassignedTitle => 'Nobody is cooking this yet';

  @override
  String get ticketUnassignedHint => 'Who\'s cooking? Pick a cook or take it yourself.';

  @override
  String get ticketUnassignedCard => 'Who\'s cooking? Tap to choose';

  @override
  String get ticketAssignTo => 'Assign to…';

  @override
  String get ticketClaim => 'I\'ll cook today';

  @override
  String get ticketClaimed => 'You\'re today\'s chef! Find it in the Rasoi tab.';

  @override
  String get ticketAlreadyClaimed => 'Someone already took this ticket.';

  @override
  String ticketAssignedToast(String name) {
    return 'Assigned to $name';
  }

  @override
  String get ticketAssigneeRequired => 'Choose who will cook';

  @override
  String get ticketNoCooks => 'No cooks added yet. Add one in Settings.';

  @override
  String get eventTicketUnassigned => 'Ticket not assigned';

  @override
  String get eventTicketCancelled => 'Ticket cancelled';

  @override
  String get eventCookMessage => 'Message from the cook';

  @override
  String get eventFamilyMessage => 'Message from the family';

  @override
  String get eventChefClaimed => 'Someone is cooking today';

  @override
  String get eventCookOnDuty => 'Cook back on duty';

  @override
  String get eventRationBought => 'Ration bought';

  @override
  String get eventStockIssueResolved => 'Stock issue resolved';

  @override
  String get eventExportReady => 'Data export ready';

  @override
  String get eventAtRisk => 'Meal may be late';
}
