// Design tokens read from the prototype (build-plan §1.2, prototype_styles.css).
// Every value here maps 1:1 to a CSS value in the prototype; do not tweak
// without updating the design reference.
import 'package:flutter/widgets.dart';

/// Colour tokens.
abstract final class BColors {
  // Brand
  static const haldi = Color(0xFFFFCC33);
  static const haldiDeep = Color(0xFFE0A800); // chef button inset shadow
  static const green = Color(0xFF0E7C3A);
  static const greenDark = Color(0xFF0A5E2C);
  static const greenPress = Color(0xFF095A29); // CTA 3D bottom shadow
  static const greenHero = Color(0xFF0E5F31);
  static const greenHeroText = Color(0xFFCFE8D5); // text on green surfaces
  static const addBg = Color(0xFFF4FBF5); // ADD button resting fill

  // Ink
  static const ink = Color(0xFF1B1B18);
  static const ink2 = Color(0xFF3A3A34);
  static const ink3 = Color(0xFF55544E);
  static const ink4 = Color(0xFF6B6A63);

  // Surfaces
  static const paper = Color(0xFFF4F5EF);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6E6DF);
  static const borderSoft = Color(0xFFF0F0EA);
  static const cream = Color(0xFFF7F3E6);
  static const chipBorder = Color(0xFFDEDFD6);
  static const segBg = Color(0xFFE9EAE2);
  static const dashed = Color(0xFFB9BAAF); // "Member jodo" dashed border

  // Fit badges (background / foreground)
  static const fitBg = Color(0xFFE7F4EA);
  static const fitFg = Color(0xFF0A5E2C);
  static const tweakBg = Color(0xFFFFF1C7);
  static const tweakFg = Color(0xFF7A5200);
  static const noBg = Color(0xFFFCE6E2);
  static const noFg = Color(0xFF8B2A17);

  // Diet marks
  static const markVeg = Color(0xFF0E7C3A);
  static const markEgg = Color(0xFFB86A00);
  static const markNonveg = Color(0xFF8B2A17);

  // Spices (orbit + chilli pills)
  static const leaf = Color(0xFF3F8F3A);
  static const chilli = Color(0xFFC4331F);
  static const cumin = Color(0xFFF2B01E);
  static const clove = Color(0xFF6B3D1E);

  // Roti (typing indicator)
  static const rotiLight = Color(0xFFEBC585);
  static const rotiDark = Color(0xFFC18A45);

  // rgba(27,27,24,a) helpers
  static Color inkA(double a) => ink.withValues(alpha: a);
}

/// Corner radii.
abstract final class BRadii {
  static const double header = 24; // header bottom corners
  static const double hero = 20;
  static const double tile = 16; // tiles, cards
  static const double cta = 14; // CTAs, inputs, large chips, segment track
  static const double icon = 12; // icon buttons, toast, search bar
  static const double small = 10; // small buttons, segments
  static const double add = 8; // ADD button, step number
  static const double badge = 6;
  static const double pill = 999;
}

/// Fixed component heights.
abstract final class BSizes {
  static const double cta = 52;
  static const double input = 48;
  static const double chip = 36;
  static const double seg = 40;
  static const double add = 32;
  static const double addMinWidth = 68;
  static const double nav = 68;
  static const double navItem = 56;
  static const double iconButton = 44;
  static const double badge = 22;
  static const double dietMark = 14;
  static const double avatar = 36;
  static const double stepNumber = 26;
  static const double chefButton = 54;
  static const double tileImage = 124;
  static const double miniWidth = 212;
  static const double miniImage = 112;

  /// The prototype's phone frame.
  static const Size frame = Size(390, 844);
}

/// Type scale (px == logical px).
abstract final class BType {
  static const double h1 = 40; // splash
  static const double h1Family = 30;
  static const double h1Alt = 28; // plan / detail
  static const double display26 = 26; // wordmark, prefs title, loading
  static const double display22 = 22; // household name, hero
  static const double section = 19;
  static const double cta = 16;
  static const double ghost = 15;
  static const double sectionLabel = 15; // prefs section titles
  static const double memberName = 16;
  static const double cardTitle = 14;
  static const double body = 14;
  static const double chip = 13;
  static const double captionL = 12.5;
  static const double caption = 12;
  static const double cuisine = 11.5;
  static const double badge = 11;
  static const double nav = 11;

  /// CSS `letter-spacing: -.02em` on display text.
  static const double displayTracking = -0.02;

  /// CSS `letter-spacing: .08em` / `.06em` on eyebrows.
  static const double eyebrowTracking = 0.08;
  static const double slotEyebrowTracking = 0.06;
}

/// Font family names as declared in pubspec.yaml.
abstract final class BFonts {
  static const body = 'Figtree';
  static const display = 'BricolageGrotesque';
  static const devanagari = 'NotoSansDevanagari';
  static const fallback = <String>[devanagari];
}

/// Shadows used by the prototype.
abstract final class BShadows {
  /// `.cta` resting: `0 4px 0 #095A29`.
  static const ctaRest = [BoxShadow(color: BColors.greenPress, offset: Offset(0, 4))];

  /// `.cta:active`: `0 1px 0 #095A29`.
  static const ctaPressed = [BoxShadow(color: BColors.greenPress, offset: Offset(0, 1))];

  /// `.seg.on`: `0 2px 6px rgba(27,27,24,.12)`.
  static const segOn = [BoxShadow(color: Color(0x1F1B1B18), offset: Offset(0, 2), blurRadius: 6)];

  /// Search bar: `0 1px 0 rgba(27,27,24,.08)`.
  static const search = [BoxShadow(color: Color(0x141B1B18), offset: Offset(0, 1))];

  /// Chef button: `0 6px 14px -4px rgba(27,27,24,.35)`.
  static const chef = [BoxShadow(color: Color(0x591B1B18), offset: Offset(0, 6), blurRadius: 14, spreadRadius: -4)];

  /// Sticky menu bar: `0 10px 24px -8px rgba(14,124,58,.6)`.
  static const planBar = [BoxShadow(color: Color(0x990E7C3A), offset: Offset(0, 10), blurRadius: 24, spreadRadius: -8)];

  /// Send button: `0 3px 0 #095A29`.
  static const send = [BoxShadow(color: BColors.greenPress, offset: Offset(0, 3))];
}
