import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Text style factory. The bundled fonts are variable fonts, so every style
/// sets both [FontWeight] and the matching `wght` axis value.
abstract final class BText {
  /// Figtree body text (prototype weights 500–800).
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = BColors.ink,
    double? height,
    double? tracking,
  }) {
    return TextStyle(
      fontFamily: BFonts.body,
      fontFamilyFallback: BFonts.fallback,
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      color: color,
      height: height,
      letterSpacing: tracking == null ? null : tracking * size,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// Bricolage Grotesque display text, `letter-spacing: -.02em`.
  /// The optical-size axis follows the font size like CSS
  /// `font-optical-sizing: auto`.
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color color = BColors.ink,
    double? height,
  }) {
    return TextStyle(
      fontFamily: BFonts.display,
      fontFamilyFallback: const [BFonts.body, BFonts.devanagari],
      fontSize: size,
      fontWeight: weight,
      fontVariations: [
        FontVariation.weight(weight.value.toDouble()),
        FontVariation('opsz', size.clamp(12, 96).toDouble()),
      ],
      color: color,
      height: height,
      letterSpacing: BType.displayTracking * size,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// 12/800 uppercase eyebrow with `.08em` tracking.
  static TextStyle eyebrow({Color color = BColors.ink, double tracking = BType.eyebrowTracking}) =>
      body(BType.caption, weight: FontWeight.w800, color: color, tracking: tracking);
}

/// App-wide [ThemeData] built from the tokens.
abstract final class BTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: BFonts.body,
      fontFamilyFallback: BFonts.fallback,
      scaffoldBackgroundColor: BColors.paper,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: const ColorScheme.light(
        primary: BColors.green,
        onPrimary: Colors.white,
        secondary: BColors.haldi,
        onSecondary: BColors.ink,
        surface: BColors.card,
        onSurface: BColors.ink,
        error: BColors.noFg,
        outline: BColors.border,
      ),
    );

    TextStyle d(double s, {double? h}) => BText.display(s, height: h);
    TextStyle b(double s, FontWeight w, {Color c = BColors.ink}) => BText.body(s, weight: w, color: c);

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: d(BType.h1, h: 1.02),
        displayMedium: d(BType.h1Family, h: 1.05),
        displaySmall: d(BType.h1Alt, h: 1.05),
        headlineLarge: d(BType.display26, h: 1.1),
        headlineMedium: d(BType.display22, h: 1.08),
        headlineSmall: d(BType.section),
        titleLarge: b(BType.memberName, FontWeight.w800),
        titleMedium: b(BType.sectionLabel, FontWeight.w800),
        titleSmall: b(BType.cardTitle, FontWeight.w800),
        bodyLarge: b(BType.cta, FontWeight.w500, c: BColors.ink2),
        bodyMedium: b(BType.body, FontWeight.w500),
        bodySmall: b(BType.captionL, FontWeight.w500, c: BColors.ink3),
        labelLarge: b(BType.chip, FontWeight.w600, c: BColors.ink2),
        labelMedium: b(BType.caption, FontWeight.w800),
        labelSmall: b(BType.badge, FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BColors.haldi,
        foregroundColor: BColors.ink,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: BColors.green),
    );
  }
}
