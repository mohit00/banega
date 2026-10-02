import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn'),
    Locale('en'),
    Locale('hi'),
  ];

  /// App name
  ///
  /// In hi_Latn, this message translates to:
  /// **'Banega'**
  String get appTitle;

  /// Wordmark text; the green dot is drawn separately
  ///
  /// In hi_Latn, this message translates to:
  /// **'banega'**
  String get wordmark;

  /// Ink badge on splash
  ///
  /// In hi_Latn, this message translates to:
  /// **'AI MAHARAJ'**
  String get aiMaharajBadge;

  /// Accessibility label for the thali illustration
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar ki thali'**
  String get thaliAlt;

  /// Back button accessibility label
  ///
  /// In hi_Latn, this message translates to:
  /// **'Back'**
  String get back;

  /// Splash H1
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj khaane\nmein kya hai?'**
  String get splashTitle;

  /// Splash paragraph
  ///
  /// In hi_Latn, this message translates to:
  /// **'Har ghar ka roz ka sawaal. Ek AI jo aapke poore parivaar ki pasand yaad rakhta hai — aur har meal pe options deta hai.'**
  String get splashBody;

  /// Splash primary CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Apna ghar set karo'**
  String get splashCta;

  /// Splash secondary action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Demo family ke saath dekho'**
  String get splashDemo;

  /// Onboarding progress eyebrow
  ///
  /// In hi_Latn, this message translates to:
  /// **'STEP 1 OF 2'**
  String get stepOneOfTwo;

  /// Family H1
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar mein kaun\nkaun hai?'**
  String get familyTitle;

  /// Family paragraph
  ///
  /// In hi_Latn, this message translates to:
  /// **'Har member ki pasand alag. Tap karke set karo — Maharaj sab yaad rakhega.'**
  String get familyBody;

  /// Dashed add-member button
  ///
  /// In hi_Latn, this message translates to:
  /// **'Member jodo'**
  String get addMember;

  /// Family footer CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} log · Aage badho'**
  String familyCta(int count);

  /// Member summary spice fragment
  ///
  /// In hi_Latn, this message translates to:
  /// **'{spice} mirch'**
  String spiceSummary(String spice);

  /// Prefs header eyebrow
  ///
  /// In hi_Latn, this message translates to:
  /// **'STEP 2 OF 2 · PASAND'**
  String get prefsStep;

  /// Prefs member title
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ki pasand'**
  String prefsTitle(String name);

  /// Prefs subtitle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj isi hisaab se suggest karega'**
  String get prefsSubtitle;

  /// Diet section title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kya khaate hain?'**
  String get prefsDietTitle;

  /// Spice section title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mirch kitni?'**
  String get prefsSpiceTitle;

  /// Needs section title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Koi zaroorat ya parhez?'**
  String get prefsNeedsTitle;

  /// Cuisine section title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Favourite cuisine'**
  String get prefsCuisineTitle;

  /// Prefs footer CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Save · {name}'**
  String prefsSave(String name);

  /// No description provided for @dietVeg.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Veg'**
  String get dietVeg;

  /// No description provided for @dietVegHint.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shakahari'**
  String get dietVegHint;

  /// No description provided for @dietJain.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jain'**
  String get dietJain;

  /// No description provided for @dietJainHint.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bina pyaaz-lahsun'**
  String get dietJainHint;

  /// No description provided for @dietEgg.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Egg'**
  String get dietEgg;

  /// No description provided for @dietEggHint.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Veg + ande'**
  String get dietEggHint;

  /// No description provided for @dietNonveg.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Non-veg'**
  String get dietNonveg;

  /// No description provided for @dietNonvegHint.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab kuch'**
  String get dietNonvegHint;

  /// Detail meta diet label for Jain-safe recipes
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jain-friendly'**
  String get dietJainFriendly;

  /// No description provided for @spiceKam.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kam'**
  String get spiceKam;

  /// No description provided for @spiceMedium.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Medium'**
  String get spiceMedium;

  /// No description provided for @spiceTeekha.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Teekha'**
  String get spiceTeekha;

  /// No description provided for @needLowOil.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Low oil'**
  String get needLowOil;

  /// No description provided for @needLowSugar.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Low sugar'**
  String get needLowSugar;

  /// No description provided for @needHighProtein.
  ///
  /// In hi_Latn, this message translates to:
  /// **'High protein'**
  String get needHighProtein;

  /// No description provided for @needNoMaida.
  ///
  /// In hi_Latn, this message translates to:
  /// **'No maida'**
  String get needNoMaida;

  /// No description provided for @needKidFriendly.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kid-friendly'**
  String get needKidFriendly;

  /// No description provided for @cuisineNorthIndian.
  ///
  /// In hi_Latn, this message translates to:
  /// **'North Indian'**
  String get cuisineNorthIndian;

  /// No description provided for @cuisineSouthIndian.
  ///
  /// In hi_Latn, this message translates to:
  /// **'South Indian'**
  String get cuisineSouthIndian;

  /// No description provided for @cuisineGujarati.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Gujarati'**
  String get cuisineGujarati;

  /// No description provided for @cuisineRajasthani.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rajasthani'**
  String get cuisineRajasthani;

  /// No description provided for @cuisineBengali.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bengali'**
  String get cuisineBengali;

  /// No description provided for @cuisineMaharashtrian.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharashtrian'**
  String get cuisineMaharashtrian;

  /// No description provided for @cuisineIndoChinese.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Indo-Chinese'**
  String get cuisineIndoChinese;

  /// Loading title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj aapke ghar\nko samajh raha hai…'**
  String get loadingTitle;

  /// Constraint line with up to three items
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dhyaan rakha: {items}'**
  String constraintLine(String items);

  /// Constraint line when nothing special
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sabki pasand dhyaan mein hai'**
  String get constraintNone;

  /// No description provided for @constraintJain.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} (Jain)'**
  String constraintJain(String name);

  /// No description provided for @constraintLowSugar.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} (low sugar)'**
  String constraintLowSugar(String name);

  /// No description provided for @constraintKamMirch.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} (kam mirch)'**
  String constraintKamMirch(String name);

  /// Demo household name (from Household.name later)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Purohit Parivaar'**
  String get householdName;

  /// Home header family line
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} log · {items}'**
  String familyLine(int count, String items);

  /// No description provided for @slotBreakfast.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Nashta'**
  String get slotBreakfast;

  /// No description provided for @slotLunch.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Lunch'**
  String get slotLunch;

  /// No description provided for @slotDinner.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dinner'**
  String get slotDinner;

  /// No description provided for @eyebrowBreakfast.
  ///
  /// In hi_Latn, this message translates to:
  /// **'SUBAH KA NASHTA'**
  String get eyebrowBreakfast;

  /// No description provided for @eyebrowLunch.
  ///
  /// In hi_Latn, this message translates to:
  /// **'DOPAHAR KA KHAANA'**
  String get eyebrowLunch;

  /// No description provided for @eyebrowDinner.
  ///
  /// In hi_Latn, this message translates to:
  /// **'RAAT KA KHAANA'**
  String get eyebrowDinner;

  /// Search bar lead word
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pucho'**
  String get searchPrefix;

  /// No description provided for @tickerAsk1.
  ///
  /// In hi_Latn, this message translates to:
  /// **'“15 min mein nashta”'**
  String get tickerAsk1;

  /// No description provided for @tickerAsk2.
  ///
  /// In hi_Latn, this message translates to:
  /// **'“Dadi ke liye Jain dinner”'**
  String get tickerAsk2;

  /// No description provided for @tickerAsk3.
  ///
  /// In hi_Latn, this message translates to:
  /// **'“baarish wala khaana”'**
  String get tickerAsk3;

  /// No description provided for @tickerAsk4.
  ///
  /// In hi_Latn, this message translates to:
  /// **'“Daughter ka tiffin”'**
  String get tickerAsk4;

  /// Hero badge
  ///
  /// In hi_Latn, this message translates to:
  /// **'MAHARAJ KA PICK'**
  String get maharajPick;

  /// Hero meta line
  ///
  /// In hi_Latn, this message translates to:
  /// **'{fitLabel} · {mins} min'**
  String heroMeta(String fitLabel, int mins);

  /// Hero button
  ///
  /// In hi_Latn, this message translates to:
  /// **'Recipe dekho'**
  String get recipeDekho;

  /// No description provided for @quickAsk15Min.
  ///
  /// In hi_Latn, this message translates to:
  /// **'15 min mein kuch'**
  String get quickAsk15Min;

  /// No description provided for @quickAskHalka.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch halka'**
  String get quickAskHalka;

  /// No description provided for @quickAskBaarish.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Baarish special'**
  String get quickAskBaarish;

  /// No description provided for @quickAskTiffin.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Daughter ka tiffin'**
  String get quickAskTiffin;

  /// No description provided for @quickAskMehmaan.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mehmaan aa rahe hain'**
  String get quickAskMehmaan;

  /// No description provided for @quickAskProtein.
  ///
  /// In hi_Latn, this message translates to:
  /// **'High protein'**
  String get quickAskProtein;

  /// Grid section title
  ///
  /// In hi_Latn, this message translates to:
  /// **'{slot} ke options'**
  String slotOptions(String slot);

  /// Grid section aside
  ///
  /// In hi_Latn, this message translates to:
  /// **'sabke hisaab se'**
  String get sabkeHisaab;

  /// Minutes badge on tiles
  ///
  /// In hi_Latn, this message translates to:
  /// **'{mins} MIN'**
  String minBadge(int mins);

  /// No description provided for @addLabel.
  ///
  /// In hi_Latn, this message translates to:
  /// **'ADD'**
  String get addLabel;

  /// No description provided for @addedLabel.
  ///
  /// In hi_Latn, this message translates to:
  /// **'ADDED'**
  String get addedLabel;

  /// Sticky menu bar title
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} dish · Aaj ka menu'**
  String planBarTitle(int count);

  /// Sticky menu bar action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ko bhejo'**
  String get cookKoBhejo;

  /// No description provided for @navGhar.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar'**
  String get navGhar;

  /// No description provided for @navMaharaj.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj se pucho'**
  String get navMaharaj;

  /// No description provided for @navParivaar.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar'**
  String get navParivaar;

  /// Chat header name
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj'**
  String get chatName;

  /// Chat header status
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} logon ki pasand yaad hai'**
  String chatMemory(int count);

  /// Chat header plan pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Menu · {count}'**
  String chatMenuPill(int count);

  /// First bot message
  ///
  /// In hi_Latn, this message translates to:
  /// **'Namaste! Main Maharaj hoon. Ghar ke {count} logon ki pasand mujhe yaad hai.\nBas pucho — aaj kya banaun?'**
  String chatGreeting(int count);

  /// No description provided for @chatChipLunch.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj lunch mein kya?'**
  String get chatChipLunch;

  /// No description provided for @chatChipHalkaDinner.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch halka dinner'**
  String get chatChipHalkaDinner;

  /// No description provided for @chatChipNashta.
  ///
  /// In hi_Latn, this message translates to:
  /// **'15 min mein nashta'**
  String get chatChipNashta;

  /// No description provided for @chatChipMehmaan.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mehmaan aa rahe hain'**
  String get chatChipMehmaan;

  /// Chat input placeholder
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj dinner mein kuch halka…'**
  String get chatPlaceholder;

  /// No description provided for @chatVoice.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Voice'**
  String get chatVoice;

  /// No description provided for @chatSend.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// Typing indicator
  ///
  /// In hi_Latn, this message translates to:
  /// **'rotiyaan sek raha hoon…'**
  String get typing;

  /// No description provided for @voiceToast.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Voice input — real app mein Hinglish mein bol sakte ho'**
  String get voiceToast;

  /// Bot bubble when a chat reply fails (not a connection error)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj abhi jawab nahi de paaye. Phir se pucho.'**
  String get chatError;

  /// Chat input accessibility label
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj se pucho'**
  String get chatInputLabel;

  /// No description provided for @chatNoMatch.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Is combo mein exact match nahi mila. {slot} ke liye ye sabse kareeb hain:'**
  String chatNoMatch(String slot);

  /// No description provided for @chatOptions.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{slot} ke liye {count} options'**
  String chatOptions(String slot, int count);

  /// Options line with reasons appended
  ///
  /// In hi_Latn, this message translates to:
  /// **'{options} — {why}'**
  String chatOptionsWhy(String options, String why);

  /// No description provided for @chatFamilyCan.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{ok} mein poora parivaar kha sakta hai.'**
  String chatFamilyCan(int ok);

  /// No description provided for @whyHalka.
  ///
  /// In hi_Latn, this message translates to:
  /// **'halka'**
  String get whyHalka;

  /// No description provided for @whyProtein.
  ///
  /// In hi_Latn, this message translates to:
  /// **'high protein'**
  String get whyProtein;

  /// No description provided for @whyMehmaan.
  ///
  /// In hi_Latn, this message translates to:
  /// **'mehmaan-worthy'**
  String get whyMehmaan;

  /// No description provided for @whyBaarish.
  ///
  /// In hi_Latn, this message translates to:
  /// **'baarish wala'**
  String get whyBaarish;

  /// No description provided for @whyKid.
  ///
  /// In hi_Latn, this message translates to:
  /// **'bachchon ko pasand'**
  String get whyKid;

  /// No description provided for @why20Min.
  ///
  /// In hi_Latn, this message translates to:
  /// **'20 min ke andar'**
  String get why20Min;

  /// No description provided for @whyPaneer.
  ///
  /// In hi_Latn, this message translates to:
  /// **'paneer wala'**
  String get whyPaneer;

  /// No description provided for @whyMember.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ke hisaab se'**
  String whyMember(String name);

  /// No description provided for @followProteinNashta.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Protein wala nashta'**
  String get followProteinNashta;

  /// No description provided for @followTiffin.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Daughter ka tiffin'**
  String get followTiffin;

  /// No description provided for @followSouth.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch South Indian'**
  String get followSouth;

  /// No description provided for @followHalka.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch halka'**
  String get followHalka;

  /// No description provided for @followBaarish.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Baarish special'**
  String get followBaarish;

  /// No description provided for @followPaneer.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Paneer wala kuch'**
  String get followPaneer;

  /// No description provided for @followDadi.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dadi ke liye kya?'**
  String get followDadi;

  /// No description provided for @fitAllPerfect.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sabke liye perfect'**
  String get fitAllPerfect;

  /// No description provided for @fitAllPerfectShort.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sabke liye'**
  String get fitAllPerfectShort;

  /// No description provided for @fitAllTweak.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sabke liye · {count} tweak'**
  String fitAllTweak(int count);

  /// No description provided for @fitAllTweakShort.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab · {count} tweak'**
  String fitAllTweakShort(int count);

  /// No description provided for @fitPartial.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{can}/{total} ke liye'**
  String fitPartial(int can, int total);

  /// No description provided for @fitNotFor.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{names} ke liye nahi'**
  String fitNotFor(String names);

  /// No description provided for @fitAllHappy.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab khush, koi badlaav nahi'**
  String get fitAllHappy;

  /// No description provided for @fitTweakNote.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name}: {note}'**
  String fitTweakNote(String name, String note);

  /// Engine reason (no)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pyaaz-lahsun hai'**
  String get reasonOnionGarlic;

  /// Engine reason (no)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Isme anda hai'**
  String get reasonEgg;

  /// Engine reason (no)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Non-veg hai'**
  String get reasonNonveg;

  /// Engine reason (no)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maida hai'**
  String get reasonMaida;

  /// Engine reason (tweak)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Unki katori mein kam mirch'**
  String get reasonLessChilli;

  /// Engine reason (tweak)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Upar se laal mirch / achaar'**
  String get reasonExtraChilli;

  /// Engine reason (tweak)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Portion chhota, salad zyada'**
  String get reasonLowSugar;

  /// Engine reason (tweak)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kam tel mein banao'**
  String get reasonLowOil;

  /// Engine reason (tweak)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saath mein dahi/paneer'**
  String get reasonProtein;

  /// Engine reason (tweak)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bachche ke liye alag, halka'**
  String get reasonKid;

  /// Engine reason (fit)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Favourite cuisine bhi'**
  String get reasonFavCuisine;

  /// Engine reason (fit)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bilkul sahi'**
  String get reasonPerfect;

  /// No description provided for @verdictPerfect.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Perfect'**
  String get verdictPerfect;

  /// No description provided for @verdictTweak.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Tweak'**
  String get verdictTweak;

  /// No description provided for @verdictNo.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Nahi'**
  String get verdictNo;

  /// No description provided for @detailMeta.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{diet} · {cuisine} · {mins} min'**
  String detailMeta(String diet, String cuisine, int mins);

  /// No description provided for @kaunKhayega.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun khayega'**
  String get kaunKhayega;

  /// No description provided for @saaman.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman'**
  String get saaman;

  /// No description provided for @kaiseBanega.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaise banega'**
  String get kaiseBanega;

  /// No description provided for @videoRecipe.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Video recipe'**
  String get videoRecipe;

  /// No description provided for @menuMeinDaalo.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Menu mein daalo'**
  String get menuMeinDaalo;

  /// No description provided for @menuMeinHai.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Menu mein hai'**
  String get menuMeinHai;

  /// No description provided for @planTitle.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj ka {slot} menu'**
  String planTitle(String slot);

  /// No description provided for @planSubtitle.
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} logon ke liye · {coverage}'**
  String planSubtitle(int count, String coverage);

  /// No description provided for @planCoverageAll.
  ///
  /// In hi_Latn, this message translates to:
  /// **'har member ke liye kuch na kuch hai'**
  String get planCoverageAll;

  /// No description provided for @planCoverageSome.
  ///
  /// In hi_Latn, this message translates to:
  /// **'kuch members ke liye aur dish chahiye'**
  String get planCoverageSome;

  /// No description provided for @planEmpty.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Menu khaali hai — Ghar se dishes ADD karo.'**
  String get planEmpty;

  /// No description provided for @planSaamanList.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman ki list'**
  String get planSaamanList;

  /// No description provided for @planSendCook.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj / cook ko bhejo'**
  String get planSendCook;

  /// No description provided for @planOrderMissing.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Missing saaman order karo'**
  String get planOrderMissing;

  /// No description provided for @toastSentCook.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Menu + saaman list cook ko WhatsApp par bhej di'**
  String get toastSentCook;

  /// No description provided for @toastMissingCart.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Missing saaman cart mein daal diya'**
  String get toastMissingCart;

  /// Design-system gallery screen title (internal)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Component gallery'**
  String get galleryTitle;

  /// Diet: no onion/garlic (not on the Prefs grid yet)
  ///
  /// In hi_Latn, this message translates to:
  /// **'No pyaaz-lahsun'**
  String get dietNoOnionGarlic;

  /// No description provided for @dietNoOnionGarlicHint.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Veg, bina pyaaz-lahsun'**
  String get dietNoOnionGarlicHint;

  /// Diet: veg + fish
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pescatarian'**
  String get dietPescatarian;

  /// No description provided for @dietPescatarianHint.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Veg + machli'**
  String get dietPescatarianHint;

  /// Engine reason (no): allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'{item} se allergy'**
  String reasonAllergen(String item);

  /// Engine reason (no): Jain + root vegetable
  ///
  /// In hi_Latn, this message translates to:
  /// **'Zameen ke neeche ki sabzi hai'**
  String get reasonRootVeg;

  /// Engine reason (no): meat the member skips
  ///
  /// In hi_Latn, this message translates to:
  /// **'Isme {item} hai'**
  String reasonNonvegItem(String item);

  /// Engine reason (no): no-dairy member
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dairy hai'**
  String get reasonDairy;

  /// Engine reason (no): disliked main ingredient
  ///
  /// In hi_Latn, this message translates to:
  /// **'Unko {item} pasand nahi'**
  String reasonDislikeMain(String item);

  /// Engine reason (tweak): disliked minor ingredient
  ///
  /// In hi_Latn, this message translates to:
  /// **'Unki katori mein {item} mat daalo'**
  String reasonDislikeSkip(String item);

  /// Engine reason (no): fasting day
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj vrat hai'**
  String get reasonVrat;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Moongphali'**
  String get allergenPeanut;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaju-badaam'**
  String get allergenTreeNut;

  /// No description provided for @allergenDairy.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dairy'**
  String get allergenDairy;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Gehun (gluten)'**
  String get allergenGluten;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Anda'**
  String get allergenEgg;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Machhli'**
  String get allergenFish;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Til'**
  String get allergenSesame;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Soya'**
  String get allergenSoy;

  /// Home header pill when showing the local demo sandbox instead of the API
  ///
  /// In hi_Latn, this message translates to:
  /// **'Demo data'**
  String get demoDataPill;

  /// Detail servings stepper value
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} log'**
  String servingsCount(int count);

  /// Servings stepper minus (accessibility)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kam log'**
  String get servingsLess;

  /// Servings stepper plus (accessibility)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Zyada log'**
  String get servingsMore;

  /// Detail note when servings are far above the recipe base
  ///
  /// In hi_Latn, this message translates to:
  /// **'Itne logon ke liye do batch mein pakao'**
  String get batchWarning;

  /// Home error state
  ///
  /// In hi_Latn, this message translates to:
  /// **'Options load nahi hue'**
  String get homeLoadError;

  /// No description provided for @retry.
  ///
  /// In hi_Latn, this message translates to:
  /// **'Phir se try karo'**
  String get retry;

  /// Bottom-nav tab for cook mode (only with a cook role)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rasoi'**
  String get navRasoi;

  /// Optional slot
  ///
  /// In hi_Latn, this message translates to:
  /// **'Tiffin'**
  String get slotTiffin;

  /// Optional slot
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shaam ka nashta'**
  String get slotShaam;

  /// Plan date chip
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj'**
  String get dateToday;

  /// Plan date chip
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kal'**
  String get dateTomorrow;

  /// Plan title for a date other than today
  ///
  /// In hi_Latn, this message translates to:
  /// **'{day} ka {slot} menu'**
  String planTitleOn(String day, String slot);

  /// Plan coverage line naming uncovered eaters
  ///
  /// In hi_Latn, this message translates to:
  /// **'{names} ke liye aur dish chahiye'**
  String planCoverageMissing(String names);

  /// Plan error state
  ///
  /// In hi_Latn, this message translates to:
  /// **'Menu load nahi hua'**
  String get planLoadError;

  /// Plan eaters section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun kha raha hai?'**
  String get planEatersTitle;

  /// Guest counter row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mehmaan · bade'**
  String get planGuestAdults;

  /// Guest counter row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mehmaan · bachche'**
  String get planGuestKids;

  /// Guest diet chips label
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mehmaan kya khaate hain?'**
  String get planGuestDiet;

  /// Plan servings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kitne log'**
  String get planServingsTitle;

  /// Servings readout
  ///
  /// In hi_Latn, this message translates to:
  /// **'{servings} servings'**
  String planServingsValue(String servings);

  /// How servings are counted
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bade 1 · bachche ½ · mehmaan jode'**
  String get planServingsHint;

  /// Plan due-time section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kab tak'**
  String get planDueTitle;

  /// Due-time hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khaana kitne baje tak taiyaar ho'**
  String get planDueHint;

  /// Plan assignee section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun banayega'**
  String get planAssigneeTitle;

  /// No assignee chip
  ///
  /// In hi_Latn, this message translates to:
  /// **'Koi nahi'**
  String get planAssigneeNone;

  /// Cook chip: Ramesh ji (hired)
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ({kind})'**
  String cookChipLabel(String name, String kind);

  /// Cook kind
  ///
  /// In hi_Latn, this message translates to:
  /// **'hired'**
  String get cookKindHired;

  /// Cook kind
  ///
  /// In hi_Latn, this message translates to:
  /// **'family'**
  String get cookKindFamily;

  /// Off-duty suffix on a cook chip
  ///
  /// In hi_Latn, this message translates to:
  /// **'Chhutti'**
  String get cookOffDutyTag;

  /// Plan CTA once sent
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket dekho'**
  String get planViewTicket;

  /// Share-sheet CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'WhatsApp par bhi bhejo'**
  String get planShareWhatsApp;

  /// Remove dish (accessibility)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hatao'**
  String get removeDish;

  /// Confirm toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket bhej diya'**
  String get toastTicketSent;

  /// Missing-saaman stub toast (Phase 6)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman order karna jaldi aa raha hai'**
  String get toastOrderSoon;

  /// Generic error toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch gadbad hui, phir se try karo'**
  String get toastError;

  /// 409 toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket badal gaya tha — naya status dikha rahe hain'**
  String get toastConflict;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hai'**
  String get itemIn;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kam hai'**
  String get itemLow;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khatam'**
  String get itemOut;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pata nahi'**
  String get itemUntracked;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naya'**
  String get statusNew;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kisi ko nahi mila'**
  String get statusUnassigned;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Accept ho gaya'**
  String get statusAccepted;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ban raha hai'**
  String get statusCooking;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Taiyaar'**
  String get statusReady;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ho gaya'**
  String get statusCompleted;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Confirm nahi hua'**
  String get statusNotConfirmed;

  /// Ticket status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cancel'**
  String get statusCancelled;

  /// Ticket screen fallback title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket'**
  String get ticketTitle;

  /// Home ticket card title
  ///
  /// In hi_Latn, this message translates to:
  /// **'{slot} ka ticket'**
  String ticketCardTitle(String slot);

  /// Due time
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kab tak {time}'**
  String dueBy(String time);

  /// Ticket without assignee
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kisi ko assign nahi'**
  String get ticketNoAssignee;

  /// Guests on a ticket
  ///
  /// In hi_Latn, this message translates to:
  /// **'+{count} mehmaan'**
  String ticketGuests(int count);

  /// Ticket section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dishes'**
  String get ticketDishes;

  /// Ticket section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Note'**
  String get ticketNotes;

  /// Notes field hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ke liye note…'**
  String get ticketNotesHint;

  /// Ticket section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kya kya badla'**
  String get ticketChangeLog;

  /// Ticket action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Badlo'**
  String get ticketEdit;

  /// Edit sheet CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Save karo'**
  String get ticketSave;

  /// Edit toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket update ho gaya'**
  String get ticketSavedToast;

  /// Ticket action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cancel karo'**
  String get ticketCancel;

  /// Reason dialog (cooking)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cancel kyun kar rahe ho?'**
  String get ticketCancelReason;

  /// Reason field hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Wajah likho'**
  String get ticketCancelReasonHint;

  /// Cancel confirm
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan, cancel karo'**
  String get ticketCancelConfirm;

  /// Cancel dismiss
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rehne do'**
  String get ticketKeep;

  /// Cancel toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket cancel ho gaya'**
  String get ticketCancelledToast;

  /// Admin completes a ticket
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ho gaya mark karo'**
  String get ticketMarkDone;

  /// Open thread
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook se baat karo'**
  String get ticketAskCook;

  /// Updated tag
  ///
  /// In hi_Latn, this message translates to:
  /// **'Badla gaya'**
  String get ticketUpdatedTag;

  /// Stock issue tag
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman khatam'**
  String get ticketStockIssueTag;

  /// Ticket error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket load nahi hua'**
  String get ticketLoadError;

  /// Not-confirmed prompt
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khaana bana?'**
  String get khanaBanaPrompt;

  /// Not-confirmed prompt body
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ne \'Ban gaya\' nahi dabaya. Bata do, taaki hisaab sahi rahe.'**
  String get khanaBanaHint;

  /// Not-confirmed yes
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan, bana'**
  String get khanaBanaYes;

  /// Not-confirmed no
  ///
  /// In hi_Latn, this message translates to:
  /// **'Nahi bana'**
  String get khanaBanaNo;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket bana'**
  String get logCreated;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Accept kiya'**
  String get logAccepted;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Banana shuru'**
  String get logCooking;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Taiyaar'**
  String get logReady;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ho gaya'**
  String get logCompleted;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cancel kiya'**
  String get logCancelled;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Confirm nahi hua'**
  String get logNotConfirmed;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Badla'**
  String get logUpdated;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman khatam'**
  String get logItemOut;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Claim kiya'**
  String get logClaimed;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dusre cook ko diya'**
  String get logReassigned;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Assign hataya'**
  String get logUnassigned;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Apne aap cancel'**
  String get logAutoCancelled;

  /// Inbox screen / bell
  ///
  /// In hi_Latn, this message translates to:
  /// **'Inbox'**
  String get inboxTitle;

  /// Bell accessibility label
  ///
  /// In hi_Latn, this message translates to:
  /// **'Inbox, {count} naye'**
  String inboxBellUnread(int count);

  /// Inbox empty
  ///
  /// In hi_Latn, this message translates to:
  /// **'Abhi koi khabar nahi'**
  String get inboxEmpty;

  /// Settings stub
  ///
  /// In hi_Latn, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings stub section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Demo: cook role'**
  String get settingsDemoCook;

  /// Settings stub hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook role ho to neeche \'Rasoi\' tab dikhega (cook mode).'**
  String get settingsDemoCookHint;

  /// K1 title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj ke tickets'**
  String get cookTitle;

  /// K1 tab
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj'**
  String get cookTabToday;

  /// K1 tab
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kal'**
  String get cookTabTomorrow;

  /// K1 due
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kab tak {time}'**
  String cookDueBy(String time);

  /// Cook action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Accept karo'**
  String get cookActionAccept;

  /// Cook action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shuru karo'**
  String get cookActionStart;

  /// Cook action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ban gaya'**
  String get cookActionDone;

  /// Cook action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Taiyaar'**
  String get cookActionReady;

  /// K1 empty
  ///
  /// In hi_Latn, this message translates to:
  /// **'Koi ticket nahi'**
  String get cookEmpty;

  /// Duty toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'On duty'**
  String get cookOnDuty;

  /// Duty toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Chhutti'**
  String get cookOffDuty;

  /// Duty toggle with date
  ///
  /// In hi_Latn, this message translates to:
  /// **'{date} tak chhutti'**
  String cookOffDutyUntil(String date);

  /// Off-duty sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kab tak chhutti?'**
  String get cookOffDutyAsk;

  /// Off-duty option
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sirf aaj'**
  String get cookOffDutyToday;

  /// Off-duty option
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kal tak'**
  String get cookOffDutyTomorrow;

  /// Off-duty option
  ///
  /// In hi_Latn, this message translates to:
  /// **'Date chuno'**
  String get cookOffDutyPick;

  /// Switch back to family mode
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar'**
  String get cookFamilyMode;

  /// Offline banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Net nahi hai — purani jaankari dikh rahi hai'**
  String get cookOffline;

  /// Queued write indicator
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bheja nahi gaya'**
  String get cookNotSent;

  /// Queued toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Net aane par bhej denge'**
  String get cookQueued;

  /// K2 section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kya banana hai'**
  String get cookDishes;

  /// K2 section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun khayega'**
  String get cookEaters;

  /// Servings
  ///
  /// In hi_Latn, this message translates to:
  /// **'{servings} logon ke liye'**
  String cookServings(String servings);

  /// Guests
  ///
  /// In hi_Latn, this message translates to:
  /// **'+{count} mehmaan'**
  String cookGuests(int count);

  /// K2 section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Note'**
  String get cookNotes;

  /// K2 section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Zaroori saaman'**
  String get cookItems;

  /// Mark item out
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khatam hai'**
  String get cookItemOut;

  /// Open thread
  ///
  /// In hi_Latn, this message translates to:
  /// **'Family se poochho'**
  String get cookAskFamily;

  /// Open recipe
  ///
  /// In hi_Latn, this message translates to:
  /// **'Recipe'**
  String get cookOpenRecipe;

  /// K5 section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman'**
  String get cookIngredients;

  /// K5 section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaise banana hai'**
  String get cookSteps;

  /// Step play
  ///
  /// In hi_Latn, this message translates to:
  /// **'Suno'**
  String get cookPlay;

  /// Step pause
  ///
  /// In hi_Latn, this message translates to:
  /// **'Roko'**
  String get cookPause;

  /// K5 speed
  ///
  /// In hi_Latn, this message translates to:
  /// **'Awaaz ki speed'**
  String get cookSpeed;

  /// 0.8x
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dheere'**
  String get cookSpeedSlow;

  /// 1.0x
  ///
  /// In hi_Latn, this message translates to:
  /// **'Normal'**
  String get cookSpeedNormal;

  /// 1.2x
  ///
  /// In hi_Latn, this message translates to:
  /// **'Tez'**
  String get cookSpeedFast;

  /// K6 title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar se baat'**
  String get cookThread;

  /// K6 input
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sandesh likho…'**
  String get cookThreadHint;

  /// K6 send
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bhejo'**
  String get cookSend;

  /// K6 empty
  ///
  /// In hi_Latn, this message translates to:
  /// **'Abhi koi baat nahi'**
  String get cookThreadEmpty;

  /// 409 toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket badal gaya — naya status dikha rahe hain'**
  String get cookConflict;

  /// Cook error toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch gadbad hui'**
  String get cookError;

  /// Cook load error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Load nahi hua — phir se try karo'**
  String get cookLoadError;

  /// S15 title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rasoi stock'**
  String get stockTitle;

  /// S15 subtitle
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} cheezein · {low} kam ya khatam'**
  String stockSubtitle(int count, int low);

  /// S15 search
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dhoondho: dahi, pyaaz…'**
  String get stockSearchHint;

  /// S15 filter
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab'**
  String get stockFilterAll;

  /// S15 filter
  ///
  /// In hi_Latn, this message translates to:
  /// **'Low + Out'**
  String get stockFilterLowOut;

  /// S15 bulk action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab In'**
  String get stockAllIn;

  /// S15 toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab stock mein'**
  String get stockAllInDone;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'In'**
  String get stockLevelIn;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Low'**
  String get stockLevelLow;

  /// Stock pill
  ///
  /// In hi_Latn, this message translates to:
  /// **'Out'**
  String get stockLevelOut;

  /// S15 empty
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch nahi mila'**
  String get stockEmpty;

  /// S15 error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Stock load nahi hua'**
  String get stockLoadError;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sabzi'**
  String get stockCatSabzi;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Doodh-dahi'**
  String get stockCatDairy;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dal'**
  String get stockCatDal;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aata-chawal'**
  String get stockCatAnaaj;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Masale'**
  String get stockCatMasale;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Tel-ghee'**
  String get stockCatTelGhee;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dry fruits'**
  String get stockCatDryFruits;

  /// Stock category
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aur'**
  String get stockCatOther;

  /// S13 title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ration'**
  String get rationTitle;

  /// S13 tab
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pending'**
  String get rationTabPending;

  /// S13 tab
  ///
  /// In hi_Latn, this message translates to:
  /// **'Approved'**
  String get rationTabApproved;

  /// S13 tab
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kharida'**
  String get rationTabBought;

  /// S13 empty
  ///
  /// In hi_Latn, this message translates to:
  /// **'Koi request nahi'**
  String get rationEmpty;

  /// S13 row
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ne maanga'**
  String rationRaisedBy(String name);

  /// S13 row
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} cheezein'**
  String rationItems(int count);

  /// S13 action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Approve karo'**
  String get rationApprove;

  /// S13 action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mana karo'**
  String get rationReject;

  /// Decide note
  ///
  /// In hi_Latn, this message translates to:
  /// **'Note (optional)'**
  String get rationNoteHint;

  /// S13 action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kharid liya'**
  String get rationBought;

  /// Ration status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pending'**
  String get rationStatusPending;

  /// Ration status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Approved'**
  String get rationStatusApproved;

  /// Ration status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mana hua'**
  String get rationStatusRejected;

  /// Ration status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aa gaya'**
  String get rationStatusBought;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Approve ho gaya'**
  String get rationApprovedToast;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mana kar diya'**
  String get rationRejectedToast;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman stock mein aa gaya'**
  String get rationBoughtToast;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ration request bhej di'**
  String get rationSentToast;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sab saaman hai — kuch order nahi karna'**
  String get rationNothingMissing;

  /// Ration tag
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khud approve'**
  String get rationSelfApproved;

  /// K1 stock button
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rasoi'**
  String get cookRasoi;

  /// K2 action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ration maango'**
  String get cookRationAsk;

  /// Cook ration list
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mera ration'**
  String get cookRationTitle;

  /// Ration sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kya chahiye?'**
  String get cookRationSheetTitle;

  /// Ration sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aur kuch? Likho'**
  String get cookRationFreeHint;

  /// Ration sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jodo'**
  String get cookRationAdd;

  /// Ration sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bhejo'**
  String get cookRationSend;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maang bhej di'**
  String get cookRationSent;

  /// Cook ration list
  ///
  /// In hi_Latn, this message translates to:
  /// **'Nayi maang'**
  String get cookRationNew;

  /// Ladder title
  ///
  /// In hi_Latn, this message translates to:
  /// **'{item} khatam hai'**
  String ladderTitle(String item);

  /// Ladder step 1
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bina {item} ke bana lo?'**
  String ladderSkipAsk(String item);

  /// Ladder step 1
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan, bina iske'**
  String get ladderSkipYes;

  /// Ladder next
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aur raaste'**
  String get ladderMoreWays;

  /// Ladder step 2
  ///
  /// In hi_Latn, this message translates to:
  /// **'Iski jagah kya daalein?'**
  String get ladderSwapTitle;

  /// Ladder step 2
  ///
  /// In hi_Latn, this message translates to:
  /// **'Badal do'**
  String get ladderSwapDo;

  /// Ladder step 2
  ///
  /// In hi_Latn, this message translates to:
  /// **'Koi safe badli nahi mili'**
  String get ladderNoSwap;

  /// Ladder step 3
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dish badlo'**
  String get ladderChangeDish;

  /// Ladder step 3
  ///
  /// In hi_Latn, this message translates to:
  /// **'Inme se kya banayein?'**
  String get ladderDishTitle;

  /// Ladder step 3
  ///
  /// In hi_Latn, this message translates to:
  /// **'Yeh banao'**
  String get ladderDishPick;

  /// Ladder step 3
  ///
  /// In hi_Latn, this message translates to:
  /// **'Koi aur dish stock mein nahi'**
  String get ladderNoDish;

  /// Ladder pending
  ///
  /// In hi_Latn, this message translates to:
  /// **'Family se poochh rahe hain…'**
  String get ladderPending;

  /// Ladder pending
  ///
  /// In hi_Latn, this message translates to:
  /// **'{mins} min mein jawab nahi aaya to admin ko alert jayega'**
  String ladderPendingHint(int mins);

  /// Ladder timeout
  ///
  /// In hi_Latn, this message translates to:
  /// **'Time out — admin ko alert gaya'**
  String get ladderTimeout;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ho gaya — ticket badal gaya'**
  String get ladderDone;

  /// Ladder rejected
  ///
  /// In hi_Latn, this message translates to:
  /// **'Family ne mana kiya — doosra raasta chuno'**
  String get ladderRejected;

  /// K2 action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Raasta dekho'**
  String get ladderOpen;

  /// Sheet close
  ///
  /// In hi_Latn, this message translates to:
  /// **'Band karo'**
  String get ladderClose;

  /// Approval sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aapki haan chahiye'**
  String get approvalTitle;

  /// Approval
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman badlo: {detail}'**
  String approvalSwap(String detail);

  /// Approval
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dish badlo: {detail}'**
  String approvalChangeDish(String detail);

  /// Approval
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ne poochha'**
  String approvalAskedBy(String name);

  /// Approval
  ///
  /// In hi_Latn, this message translates to:
  /// **'{time} tak jawab do'**
  String approvalExpires(String time);

  /// Approval
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan'**
  String get approvalYes;

  /// Approval
  ///
  /// In hi_Latn, this message translates to:
  /// **'Nahi'**
  String get approvalNo;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ko bata diya: haan'**
  String get approvalApprovedToast;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ko bata diya: nahi'**
  String get approvalRejectedToast;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Yeh sawaal ab khula nahi hai'**
  String get approvalGone;

  /// Stock banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook raasta chun raha hai'**
  String get ticketIssueChoosing;

  /// Stock banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ne poochha: {detail}'**
  String ticketIssuePending(String detail);

  /// Rate action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaisa bana?'**
  String get ticketRate;

  /// Rated tag
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rating di — shukriya!'**
  String get ticketRated;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bina saaman ke banaya'**
  String get logSkip;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman badla'**
  String get logSwap;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dish badli'**
  String get logChangeDish;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Family se poochha'**
  String get logApprovalRequested;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Family ne haan kaha'**
  String get logApproved;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Family ne mana kiya'**
  String get logRejected;

  /// Change log
  ///
  /// In hi_Latn, this message translates to:
  /// **'Time out — admin ko alert'**
  String get logTimeout;

  /// Rate sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'{slot} kaisa bana?'**
  String rateTitle(String slot);

  /// Rate sheet, family cook
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ne banaya — shukriya bolo!'**
  String rateThanksFamily(String name);

  /// Rate sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Har khaane wale ke liye ek tap'**
  String get rateHint;

  /// Score 1
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bura'**
  String get rateBura;

  /// Score 2
  ///
  /// In hi_Latn, this message translates to:
  /// **'Theek'**
  String get rateTheek;

  /// Score 3
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bahut accha'**
  String get rateBahutAccha;

  /// Proxy tag
  ///
  /// In hi_Latn, this message translates to:
  /// **'Unki taraf se'**
  String get rateProxy;

  /// Rate note
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch kehna hai? (optional)'**
  String get rateNoteHint;

  /// Rate note, family cook
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kya badlein agli baar?'**
  String get rateNoteHintFamily;

  /// Rate submit
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rating bhejo'**
  String get rateSubmit;

  /// Rate submit, family cook
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shukriya bhejo'**
  String get rateSubmitFamily;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shukriya! Maharaj yaad rakhega'**
  String get rateDone;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kam se kam ek rating do'**
  String get rateNeedOne;

  /// Recipe detail
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar ki rating'**
  String get recipeHomeRating;

  /// Recipe detail
  ///
  /// In hi_Latn, this message translates to:
  /// **'{avg}/3 · {count} rating'**
  String recipeRatingValue(String avg, int count);

  /// Home banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Free trial · {days} din baaki'**
  String trialBanner(int days);

  /// Home banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Payment atki hai — 3 din mein theek karo'**
  String get graceBanner;

  /// Home banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan band hai — sirf dekh sakte ho'**
  String get expiredBanner;

  /// Read-only sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan band hai'**
  String get planBandTitle;

  /// Read-only sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naya menu, Maharaj chat aur cook ticket ke liye ₹50/hafta wala plan chalu karo. Aaj aur kal ke tickets cook bana sakta hai.'**
  String get planBandBody;

  /// Read-only sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan dekho'**
  String get planBandCta;

  /// Weekly card
  ///
  /// In hi_Latn, this message translates to:
  /// **'Is hafte'**
  String get weeklyTitle;

  /// Weekly card
  ///
  /// In hi_Latn, this message translates to:
  /// **'Top: {name}'**
  String weeklyTop(String name);

  /// Weekly card
  ///
  /// In hi_Latn, this message translates to:
  /// **'{pct}% time par'**
  String weeklyOnTime(String pct);

  /// Weekly card
  ///
  /// In hi_Latn, this message translates to:
  /// **'{pct}% sabke liye'**
  String weeklyCoverage(String pct);

  /// Weekly card
  ///
  /// In hi_Latn, this message translates to:
  /// **'{count} meal bane'**
  String weeklyMeals(int count);

  /// S10 title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Banega plan'**
  String get paywallTitle;

  /// S10 price
  ///
  /// In hi_Latn, this message translates to:
  /// **'₹50/hafta'**
  String get paywallPrice;

  /// S10 body
  ///
  /// In hi_Latn, this message translates to:
  /// **'Poore ghar ke liye sab kuch, ek hi plan mein.'**
  String get paywallBody;

  /// S10 feature
  ///
  /// In hi_Latn, this message translates to:
  /// **'Har meal pe sabke hisaab se options'**
  String get paywallFeature1;

  /// S10 feature
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ko ticket, stock aur ration'**
  String get paywallFeature2;

  /// S10 feature
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ratings se Maharaj seekhta hai'**
  String get paywallFeature3;

  /// S10 CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'₹50/hafta · Chalu karo'**
  String get paywallSubscribe;

  /// S10 restore
  ///
  /// In hi_Latn, this message translates to:
  /// **'Purchase restore karo'**
  String get paywallRestore;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan status update ho gaya'**
  String get paywallRestored;

  /// S10 status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan chalu hai'**
  String get paywallActive;

  /// S10 status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Agla renewal {date}'**
  String paywallRenews(String date);

  /// S10 status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Free trial: {days} din baaki'**
  String paywallTrial(int days);

  /// S10 status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Payment atki hai — store mein theek karo'**
  String get paywallGrace;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan chalu! Shukriya'**
  String get paywallSubscribed;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Store billing jald aa raha hai'**
  String get paywallStoreSoon;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Payment pending hai. Poora hote hi plan chalu ho jayega.'**
  String get paywallPending;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Purchase cancel ho gaya'**
  String get paywallCancelled;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Is Play account par koi Banega plan nahi mila'**
  String get paywallNothingToRestore;

  /// S10 note
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cancel kabhi bhi Play Store / App Store se'**
  String get paywallCancelNote;

  /// Subscription status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Free trial'**
  String get subStatusTrial;

  /// Subscription status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Chalu'**
  String get subStatusActive;

  /// Subscription status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Payment atki'**
  String get subStatusGrace;

  /// Subscription status
  ///
  /// In hi_Latn, this message translates to:
  /// **'Band'**
  String get subStatusExpired;

  /// Consent title (contract key consent_title)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aapka data, aapka haq'**
  String get consentTitle;

  /// Consent body (contract key consent_body)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Banega aapka phone number login ke liye, aur ghar ke members ki pasand, allergy, vrat ke din aur khaane ka itihaas sirf menu banane, cook ko ticket bhejne aur Maharaj ke sujhav ke liye rakhta hai. Data kabhi becha nahi jaata. Settings se kabhi bhi apna account delete kar sakte ho; ghar ka admin poore ghar ka data export ya delete kar sakta hai.'**
  String get consentBody;

  /// Consent LLM note (contract key consent_llm_note)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maharaj chat ke sawaal ek AI service (Anthropic Claude) ko jaate hain. Phone number aur health needs kabhi nahi jaate; allergy sirf ginti mein, aur family ka naam sirf tab jab aap khud likho.'**
  String get consentLlmNote;

  /// Consent kids line
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bachchon ki profile aap maa-baap ya guardian ki tarah bana rahe ho.'**
  String get consentKids;

  /// Consent CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Maan liya'**
  String get consentAccept;

  /// Consent link
  ///
  /// In hi_Latn, this message translates to:
  /// **'Privacy policy padho'**
  String get consentPrivacy;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar'**
  String get settingsHousehold;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar ka naam'**
  String get settingsHouseholdName;

  /// Settings action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Badlo'**
  String get settingsEdit;

  /// Dialog save
  ///
  /// In hi_Latn, this message translates to:
  /// **'Save karo'**
  String get settingsSave;

  /// Dialog cancel
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rehne do'**
  String get settingsCancel;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Save ho gaya'**
  String get settingsSaved;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar ke members'**
  String get settingsMembers;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook setup'**
  String get settingsCooks;

  /// Cook role
  ///
  /// In hi_Latn, this message translates to:
  /// **'Primary'**
  String get settingsCookPrimary;

  /// Cook role
  ///
  /// In hi_Latn, this message translates to:
  /// **'Backup'**
  String get settingsCookBackup;

  /// Cook action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hatao'**
  String get settingsCookRemove;

  /// Cook remove confirm
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ko hatayein? Unke khule tickets unassigned ho jayenge.'**
  String settingsCookRemoveAsk(String name);

  /// Cook add
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hired cook jodo'**
  String get settingsAddHiredCook;

  /// Cook add field
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naam'**
  String get settingsCookName;

  /// Cook add field
  ///
  /// In hi_Latn, this message translates to:
  /// **'Phone number'**
  String get settingsCookPhone;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} jud gaye'**
  String settingsCookAdded(String name);

  /// Error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ek ghar mein ek hi hired cook ho sakta hai'**
  String get settingsHiredLimit;

  /// Error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Yeh phone kisi aur ghar mein hai'**
  String get settingsPhoneTaken;

  /// Error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sahi phone number daalo'**
  String get settingsInvalidPhone;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bhasha'**
  String get settingsLanguage;

  /// Settings hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook mode Hindi mein khulta hai; cook wahan apni bhasha chun sakte hain'**
  String get settingsLanguageHint;

  /// Language option
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hinglish'**
  String get langHinglish;

  /// Language option
  ///
  /// In hi_Latn, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// Language option
  ///
  /// In hi_Latn, this message translates to:
  /// **'हिंदी'**
  String get langHindi;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Settings hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Zaroori — hamesha on'**
  String get settingsNotifMandatory;

  /// Settings toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ratings'**
  String get settingsRatings;

  /// Settings hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khaane ke baad \'Kaisa bana?\' poochho. Family cook band kar sakti hai.'**
  String get settingsRatingsHint;

  /// Settings toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khaane ke baad stock ghatao'**
  String get settingsAutoDecrement;

  /// Settings hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Taaza saaman (dahi, sabzi) \'Low\' ho jayega'**
  String get settingsAutoDecrementHint;

  /// Settings toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ko rating mein naam dikhao'**
  String get settingsShowNames;

  /// Settings hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Band ho to cook ko sirf average dikhta hai'**
  String get settingsShowNamesHint;

  /// Settings toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook khud swap chun sakta hai'**
  String get settingsCookSwaps;

  /// Settings hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Band ho to har swap pe aapki haan chahiye'**
  String get settingsCookSwapsHint;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rasoi'**
  String get settingsKitchen;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan'**
  String get settingsSubscription;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Privacy aur data'**
  String get settingsPrivacy;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Consent dobara padho'**
  String get settingsConsent;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shikayat ke liye: privacy@banega.app'**
  String get settingsGrievance;

  /// Settings row: opens the public privacy policy page
  ///
  /// In hi_Latn, this message translates to:
  /// **'Privacy policy dekho'**
  String get settingsPrivacyPolicy;

  /// Settings row: opens the public terms of service page
  ///
  /// In hi_Latn, this message translates to:
  /// **'Terms aur shartein'**
  String get settingsTerms;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mera data export karo'**
  String get settingsExport;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Inbox mein link aayega'**
  String get settingsExportToast;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar delete karo'**
  String get settingsDeleteHousehold;

  /// Delete confirm
  ///
  /// In hi_Latn, this message translates to:
  /// **'Poore ghar ka data (members, menu, tickets, ratings, stock) 7 din baad hamesha ke liye mit jayega. 7 din tak \'Wapas lao\' se undo kar sakte ho. Store subscription alag se cancel karna hoga.'**
  String get settingsDeleteHouseholdAsk;

  /// Delete confirm
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan, delete karo'**
  String get settingsDeleteConfirm;

  /// Deletion banner
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar {date} ko delete hoga'**
  String settingsDeletePending(String date);

  /// Deletion undo
  ///
  /// In hi_Latn, this message translates to:
  /// **'Wapas lao'**
  String get settingsRestore;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar wapas aa gaya'**
  String get settingsRestored;

  /// Settings row
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mera account delete karo'**
  String get settingsDeleteMe;

  /// Delete me confirm
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aapka login hat jayega; ghar aur baaki members rahenge. 7 din tak undo ho sakta hai.'**
  String get settingsDeleteMeAsk;

  /// Toast
  ///
  /// In hi_Latn, this message translates to:
  /// **'Account delete ho gaya — 7 din mein wapas aa sakte ho'**
  String get settingsDeletedMe;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naya ticket'**
  String get eventTicketCreated;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket accept hua'**
  String get eventTicketAccepted;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket badla'**
  String get eventTicketUpdated;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khaana ban gaya'**
  String get eventTicketCompleted;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'\'Khaana bana?\' sawaal'**
  String get eventNotConfirmed;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook chhutti par'**
  String get eventCookOffDuty;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ne accept nahi kiya'**
  String get eventNoShow;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Stock kam'**
  String get eventStockLow;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ration ki maang'**
  String get eventRationRequest;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ration ka jawab'**
  String get eventRationDecided;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman khatam'**
  String get eventStockIssue;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan/nahi sawaal'**
  String get eventApprovalRequest;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan/nahi jawab'**
  String get eventApprovalDecided;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jawab ka time out'**
  String get eventStockTimeout;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rating do'**
  String get eventRatePrompt;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Plan reminder'**
  String get eventExpiry;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hafte ki report'**
  String get eventWeekly;

  /// Event
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kal ke tickets'**
  String get eventTomorrow;

  /// Offline banner on Home / Plan / Chat / cook mode
  ///
  /// In hi_Latn, this message translates to:
  /// **'Internet nahi hai. Jo pehle aaya tha wahi dikh raha hai.'**
  String get offlineBanner;

  /// Offline banner retry button
  ///
  /// In hi_Latn, this message translates to:
  /// **'Phir se'**
  String get offlineRetry;

  /// Phone login title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Apna number'**
  String get authPhoneTitle;

  /// Phone login body
  ///
  /// In hi_Latn, this message translates to:
  /// **'OTP se login hoga. Number sirf login ke liye hai.'**
  String get authPhoneBody;

  /// Phone field hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'10 digit mobile number'**
  String get authPhoneHint;

  /// Phone screen CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'OTP bhejo'**
  String get authSendOtp;

  /// Phone validation
  ///
  /// In hi_Latn, this message translates to:
  /// **'10 digit ka sahi number daalo'**
  String get authPhoneInvalid;

  /// OTP screen title
  ///
  /// In hi_Latn, this message translates to:
  /// **'OTP daalo'**
  String get authOtpTitle;

  /// OTP screen body
  ///
  /// In hi_Latn, this message translates to:
  /// **'{phone} par 6 digit ka code bheja hai'**
  String authOtpBody(String phone);

  /// Resend countdown
  ///
  /// In hi_Latn, this message translates to:
  /// **'{seconds} sec mein dobara bhej sakte ho'**
  String authOtpResendIn(int seconds);

  /// Resend OTP button
  ///
  /// In hi_Latn, this message translates to:
  /// **'OTP dobara bhejo'**
  String get authOtpResend;

  /// Debug builds: code returned by a dev backend
  ///
  /// In hi_Latn, this message translates to:
  /// **'Dev code: {code}'**
  String authOtpDevCode(String code);

  /// Wrong OTP
  ///
  /// In hi_Latn, this message translates to:
  /// **'Code galat hai, phir se daalo'**
  String get authOtpWrong;

  /// Semantics for an OTP box
  ///
  /// In hi_Latn, this message translates to:
  /// **'OTP ka {index} number'**
  String authOtpDigit(int index);

  /// OTP verify CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aage badho'**
  String get authVerify;

  /// Back to phone entry
  ///
  /// In hi_Latn, this message translates to:
  /// **'Number badlo'**
  String get authChangeNumber;

  /// Create household title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar ka naam'**
  String get householdCreateTitle;

  /// Create household body
  ///
  /// In hi_Latn, this message translates to:
  /// **'Yeh naam parivaar aur cook, sabko dikhega.'**
  String get householdCreateBody;

  /// Default household name suffix (typed surname goes before it)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar'**
  String get householdCreateSuffix;

  /// Create household CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar banao'**
  String get householdCreateCta;

  /// Household name validation
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar ka naam likho'**
  String get householdNameRequired;

  /// Unknown route
  ///
  /// In hi_Latn, this message translates to:
  /// **'Yeh page nahi mila'**
  String get notFoundTitle;

  /// Unknown route: back to the app
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar par jao'**
  String get notFoundHome;

  /// Add member dialog title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naya member'**
  String get addMemberTitle;

  /// Add member name field
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naam likho'**
  String get addMemberHint;

  /// Name suggestions label
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ya inme se chuno'**
  String get addMemberSuggestions;

  /// Add member confirm
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jodo'**
  String get addMemberCta;

  /// Dialog cancel
  ///
  /// In hi_Latn, this message translates to:
  /// **'Rehne do'**
  String get commonCancel;

  /// Prefs: archive the member
  ///
  /// In hi_Latn, this message translates to:
  /// **'Member hatao'**
  String get removeMember;

  /// Archive confirm title
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ko parivaar se hatayein?'**
  String removeMemberConfirm(String name);

  /// Archive confirm body
  ///
  /// In hi_Latn, this message translates to:
  /// **'Unki pasand ab menu mein nahi gini jayegi.'**
  String get removeMemberBody;

  /// Archive confirm button
  ///
  /// In hi_Latn, this message translates to:
  /// **'Haan, hatao'**
  String get removeMemberYes;

  /// Family list failed
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar load nahi hua'**
  String get membersLoadError;

  /// Family list empty
  ///
  /// In hi_Latn, this message translates to:
  /// **'Abhi koi member nahi. Pehla member jodo.'**
  String get membersEmpty;

  /// Member write failed (rolled back)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Save nahi hua, phir se try karo'**
  String get memberSaveError;

  /// Kid toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bachcha hai'**
  String get prefsKidTitle;

  /// Kid toggle hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aadhi serving gini jayegi'**
  String get prefsKidHint;

  /// Allergen section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Allergy (bilkul nahi)'**
  String get prefsAllergensTitle;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Doodh'**
  String get allergenMilk;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jhinga'**
  String get allergenShellfish;

  /// Allergen
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sarson'**
  String get allergenMustard;

  /// Dislikes section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pasand nahi'**
  String get prefsDislikesTitle;

  /// Dislike input hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jaise baingan, karela'**
  String get prefsDislikesHint;

  /// Add a dislike
  ///
  /// In hi_Latn, this message translates to:
  /// **'Jodo'**
  String get prefsDislikeAdd;

  /// Semantics: remove a dislike
  ///
  /// In hi_Latn, this message translates to:
  /// **'{item} hatao'**
  String prefsDislikeRemove(String item);

  /// Vrat weekdays section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Vrat ke din'**
  String get prefsVratTitle;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Som'**
  String get weekdayMon;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Mangal'**
  String get weekdayTue;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Budh'**
  String get weekdayWed;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Guru'**
  String get weekdayThu;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shukra'**
  String get weekdayFri;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Shani'**
  String get weekdaySat;

  /// Weekday short
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ravi'**
  String get weekdaySun;

  /// Non-veg exclusions
  ///
  /// In hi_Latn, this message translates to:
  /// **'Non-veg mein kya nahi'**
  String get prefsNonvegTitle;

  /// Non-veg exclusion
  ///
  /// In hi_Latn, this message translates to:
  /// **'Beef nahi'**
  String get nonvegNoBeef;

  /// Non-veg exclusion
  ///
  /// In hi_Latn, this message translates to:
  /// **'Pork nahi'**
  String get nonvegNoPork;

  /// Non-veg exclusion
  ///
  /// In hi_Latn, this message translates to:
  /// **'Sirf halal'**
  String get nonvegHalalOnly;

  /// No dairy toggle
  ///
  /// In hi_Latn, this message translates to:
  /// **'Doodh-dahi nahi'**
  String get prefsNoDairyTitle;

  /// No dairy hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Paneer, ghee, dahi sab hataye jayenge'**
  String get prefsNoDairyHint;

  /// Privacy toggle (F-5.3-05)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Home par health dikhao'**
  String get prefsShowOnHomeTitle;

  /// Privacy toggle hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Band ho to sirf diet dikhegi'**
  String get prefsShowOnHomeHint;

  /// Offline queue: a replayed write was rejected (409/412/422)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kuch badlav bheje nahi ja sake — ticket pehle hi badal gaya tha'**
  String get cookSyncDropped;

  /// Settings: sign out (API mode)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Log out karo'**
  String get settingsLogout;

  /// Ticket status this app version does not know (no actions)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Update karo'**
  String get statusUnknown;

  /// K5: no hi-IN TTS voice and no server audio
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hindi awaaz install karein'**
  String get cookHindiVoiceMissing;

  /// K5: where to install the voice
  ///
  /// In hi_Latn, this message translates to:
  /// **'Phone Settings → Bhasha → Text-to-speech mein Hindi chuno.'**
  String get cookHindiVoiceHint;

  /// K5: open TTS settings
  ///
  /// In hi_Latn, this message translates to:
  /// **'Settings kholo'**
  String get cookOpenSettings;

  /// K5: TTS / audio error
  ///
  /// In hi_Latn, this message translates to:
  /// **'Awaaz nahi chal payi'**
  String get cookAudioError;

  /// Subscription status could not be read
  ///
  /// In hi_Latn, this message translates to:
  /// **'Status pata nahi chala'**
  String get subStatusUnknown;

  /// Detail: launching the video link failed
  ///
  /// In hi_Latn, this message translates to:
  /// **'Video nahi khul paya'**
  String get videoOpenFailed;

  /// Settings section
  ///
  /// In hi_Latn, this message translates to:
  /// **'Display'**
  String get settingsDisplay;

  /// Settings: keep the thali still
  ///
  /// In hi_Latn, this message translates to:
  /// **'Halki animation'**
  String get settingsLightAnimations;

  /// Settings: light animations hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Purane ya dheeme phone ke liye: thali ghoomegi nahi'**
  String get settingsLightAnimationsHint;

  /// Semantics: cook-mode language switch
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook mode ki bhasha'**
  String get cookLanguage;

  /// Settings section: adults with their own login
  ///
  /// In hi_Latn, this message translates to:
  /// **'Banega par parivaar'**
  String get settingsFamilyOnBanega;

  /// Settings: family-on-Banega hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar ke bade apne phone se Banega chala sakte hain.'**
  String get invitesHint;

  /// Settings: no pending invites
  ///
  /// In hi_Latn, this message translates to:
  /// **'Abhi koi invite pending nahi'**
  String get invitesEmpty;

  /// Settings: open the invite sheet
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar ke kisi ko bulao'**
  String get inviteCta;

  /// Pending invite row: masked phone and expiry date
  ///
  /// In hi_Latn, this message translates to:
  /// **'{phone} · {date} tak'**
  String invitePendingRow(String phone, String date);

  /// Pending invite: linked member
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ke liye'**
  String inviteFor(String name);

  /// Revoke a pending invite
  ///
  /// In hi_Latn, this message translates to:
  /// **'Hatao'**
  String get inviteRevoke;

  /// Revoke confirmation
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye invite band kar dein? Purana code kaam nahi karega.'**
  String get inviteRevokeAsk;

  /// Toast after revoke
  ///
  /// In hi_Latn, this message translates to:
  /// **'Invite band kar diya'**
  String get inviteRevoked;

  /// Invite sheet: pick the member to link
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun hain?'**
  String get inviteWho;

  /// Invite sheet: create a new member
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naya member'**
  String get inviteNewMember;

  /// Invite sheet: new member's name
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naam'**
  String get inviteNewName;

  /// Invite sheet: phone field label
  ///
  /// In hi_Latn, this message translates to:
  /// **'Unka phone number'**
  String get invitePhone;

  /// Invite sheet: what the role allows
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bade member ki tarah judenge: menu dekh aur badal sakte hain, cook ko bhej sakte hain.'**
  String get inviteRoleNote;

  /// Invite sheet CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Invite banao'**
  String get inviteCreate;

  /// Invite sheet: name missing
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naam likho'**
  String get inviteNameRequired;

  /// Invite created: title above the code
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye code bhejo'**
  String get inviteCodeTitle;

  /// Invite created: how the invitee uses the code
  ///
  /// In hi_Latn, this message translates to:
  /// **'{phone} se login karke \"Code se judiye\" chunein aur ye code daalein.'**
  String inviteCodeBody(String phone);

  /// Invite created: expiry
  ///
  /// In hi_Latn, this message translates to:
  /// **'{date} tak chalega'**
  String inviteCodeExpires(String date);

  /// Semantics: the invite code
  ///
  /// In hi_Latn, this message translates to:
  /// **'Invite code {code}'**
  String inviteCodeLabel(String code);

  /// Invite created: share
  ///
  /// In hi_Latn, this message translates to:
  /// **'WhatsApp par bhejo'**
  String get inviteShareWhatsApp;

  /// Invite created: copy
  ///
  /// In hi_Latn, this message translates to:
  /// **'Code copy karo'**
  String get inviteCopy;

  /// Toast after copy
  ///
  /// In hi_Latn, this message translates to:
  /// **'Code copy ho gaya'**
  String get inviteCopied;

  /// Invite created: close
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ho gaya'**
  String get inviteDone;

  /// Invite error: phone_in_other_household
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye number kisi aur ghar mein cook hai.'**
  String get inviteErrPhoneTaken;

  /// Create household: divider between create and join
  ///
  /// In hi_Latn, this message translates to:
  /// **'ya'**
  String get householdOr;

  /// Create household: join an existing family (must match the invite message)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Code se judiye'**
  String get householdJoinOption;

  /// Create household: join hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ghar walon ne Banega par bulaya hai? Unka bheja code daaliye.'**
  String get householdJoinHint;

  /// Join screen title
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar se judiye'**
  String get joinTitle;

  /// Join screen body
  ///
  /// In hi_Latn, this message translates to:
  /// **'WhatsApp par aaya 6 akshar ka code daaliye.'**
  String get joinBody;

  /// Join screen CTA
  ///
  /// In hi_Latn, this message translates to:
  /// **'Judiye'**
  String get joinCta;

  /// Semantics: one code box
  ///
  /// In hi_Latn, this message translates to:
  /// **'Code ka akshar {n}'**
  String joinCodeBox(int n);

  /// Join screen: back to create
  ///
  /// In hi_Latn, this message translates to:
  /// **'Naya ghar banao'**
  String get joinCreateInstead;

  /// Join error: invite_code_invalid
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye code sahi nahi hai. Message dekh kar dobara daaliye.'**
  String get joinErrInvalid;

  /// Join error: invite_expired
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye code purana ho gaya. Ghar ke admin se naya code maangiye.'**
  String get joinErrExpired;

  /// Join error: invite_phone_mismatch
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye code kisi aur number ke liye hai. Usi number se login kijiye jis par invite aaya.'**
  String get joinErrPhone;

  /// Join error: already_in_household
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aapka number pehle se ek ghar mein hai.'**
  String get joinErrAlready;

  /// Join error: invite_code_locked
  ///
  /// In hi_Latn, this message translates to:
  /// **'Bahut baar galat code. Thodi der baad try kijiye.'**
  String get joinErrLocked;

  /// Ticket: unassigned state
  ///
  /// In hi_Latn, this message translates to:
  /// **'Abhi kisi ko nahi diya'**
  String get ticketUnassignedTitle;

  /// Ticket detail: unassigned hint
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun banayega? Cook chuniye ya khud le lijiye.'**
  String get ticketUnassignedHint;

  /// Home ticket card: unassigned call to action
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kaun banayega? Tap karke chuniye'**
  String get ticketUnassignedCard;

  /// Ticket detail: admin assigns a cook
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kisko dein…'**
  String get ticketAssignTo;

  /// Ticket detail: chef for the day claims the ticket
  ///
  /// In hi_Latn, this message translates to:
  /// **'Main banaunga'**
  String get ticketClaim;

  /// Toast after claim
  ///
  /// In hi_Latn, this message translates to:
  /// **'Aaj ke chef aap! Rasoi tab mein dekhiye.'**
  String get ticketClaimed;

  /// Toast: claim lost (409 already_claimed)
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ye ticket kisi aur ne le liya.'**
  String get ticketAlreadyClaimed;

  /// Toast after assigning
  ///
  /// In hi_Latn, this message translates to:
  /// **'{name} ko de diya'**
  String ticketAssignedToast(String name);

  /// Toast: 422 assignee_required
  ///
  /// In hi_Latn, this message translates to:
  /// **'Chuniye kaun banayega'**
  String get ticketAssigneeRequired;

  /// Ticket detail: no cooks to assign
  ///
  /// In hi_Latn, this message translates to:
  /// **'Abhi koi cook nahi jodi. Settings mein jodiye.'**
  String get ticketNoCooks;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket kisi ko nahi diya'**
  String get eventTicketUnassigned;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ticket cancel hua'**
  String get eventTicketCancelled;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook ka message'**
  String get eventCookMessage;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Parivaar ka message'**
  String get eventFamilyMessage;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Kisi ne aaj banana chuna'**
  String get eventChefClaimed;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Cook wapas on duty'**
  String get eventCookOnDuty;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Ration kharid liya'**
  String get eventRationBought;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Saaman ki dikkat suljhi'**
  String get eventStockIssueResolved;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Data export taiyaar'**
  String get eventExportReady;

  /// Notification event name on the Settings toggles
  ///
  /// In hi_Latn, this message translates to:
  /// **'Khaana late ho sakta hai'**
  String get eventAtRisk;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'hi':
      {
        switch (locale.scriptCode) {
          case 'Latn':
            return AppLocalizationsHiLatn();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
