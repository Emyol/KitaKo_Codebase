import 'package:flutter/material.dart';

/// KitaKo App Color Constants — v2 design token system
class AppColors {
  AppColors._();

  // ── Dark mode tokens ────────────────────────────────────────────────────────
  static const Color darkBg         = Color(0xFF0E1116);
  static const Color darkBgDeep     = Color(0xFF070A0E);
  static const Color darkSurface    = Color(0xFF161B22);
  static const Color darkSurfaceAlt = Color(0xFF1A2030);
  static const Color darkSurfaceHigh= Color(0xFF222A36);
  static const Color darkBorder     = Color(0xFF1F2733);
  static const Color darkHairline   = Color(0x1F60A5FA); // rgba(96,165,250,0.12)
  static const Color darkText       = Color(0xFFFFFFFF);
  static const Color darkTextDim    = Color(0xC7FFFFFF); // rgba(255,255,255,0.78)
  static const Color darkTextMore   = Color(0x8CFFFFFF); // rgba(255,255,255,0.55)
  static const Color darkTextFaint  = Color(0x61FFFFFF); // rgba(255,255,255,0.38)
  static const Color darkTitle      = Color(0xFF60A5FA);
  static const Color darkBlue       = Color(0xFF3B82F6);
  static const Color darkBlueDeep   = Color(0xFF1D4ED8);
  static const Color darkBlueSoft   = Color(0x2E3B82F6); // rgba(59,130,246,0.18)
  static const Color darkBlueGlow   = Color(0x593B82F6); // rgba(59,130,246,0.35)
  static const Color darkAmber      = Color(0xFFF59E0B);
  static const Color darkRed        = Color(0xFFEF4444);
  static const Color darkGreen      = Color(0xFF10B981);
  static const Color darkChipBg     = Color(0x243B82F6); // rgba(59,130,246,0.14)
  static const Color darkChipText   = Color(0xFF93C5FD);

  // ── Light mode tokens ───────────────────────────────────────────────────────
  static const Color lightBg         = Color(0xFFF4F7FB);
  static const Color lightBgDeep     = Color(0xFFE8EEF6);
  static const Color lightSurface    = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEEF3FA);
  static const Color lightSurfaceHigh= Color(0xFFE2EAF4);
  static const Color lightBorder     = Color(0xFFE2E8F0);
  static const Color lightHairline   = Color(0x192563EB); // rgba(37,99,235,0.10)
  static const Color lightText       = Color(0xFF0F172A);
  static const Color lightTextDim    = Color(0xFF475569);
  static const Color lightTextMore   = Color(0xFF64748B);
  static const Color lightTextFaint  = Color(0xFF94A3B8);
  static const Color lightTitle      = Color(0xFF0B2545);
  static const Color lightBlue       = Color(0xFF2563EB);
  static const Color lightBlueDeep   = Color(0xFF1D4ED8);
  static const Color lightBlueSoft   = Color(0xFFDBEAFE);
  static const Color lightBlueGlow   = Color(0x2E2563EB); // rgba(37,99,235,0.18)
  static const Color lightAmber      = Color(0xFFD97706);
  static const Color lightRed        = Color(0xFFDC2626);
  static const Color lightGreen      = Color(0xFF059669);
  static const Color lightChipBg     = Color(0xFFDBEAFE);
  static const Color lightChipText   = Color(0xFF1D4ED8);

  // ── Convenience getters (context-free, for static declarations) ─────────────
  static Color bg(bool isDark)         => isDark ? darkBg         : lightBg;
  static Color bgDeep(bool isDark)     => isDark ? darkBgDeep     : lightBgDeep;
  static Color surface(bool isDark)    => isDark ? darkSurface    : lightSurface;
  static Color surfaceAlt(bool isDark) => isDark ? darkSurfaceAlt : lightSurfaceAlt;
  static Color surfaceHigh(bool isDark)=> isDark ? darkSurfaceHigh: lightSurfaceHigh;
  static Color border(bool isDark)     => isDark ? darkBorder     : lightBorder;
  static Color hairline(bool isDark)   => isDark ? darkHairline   : lightHairline;
  static Color text(bool isDark)       => isDark ? darkText       : lightText;
  static Color textDim(bool isDark)    => isDark ? darkTextDim    : lightTextDim;
  static Color textMore(bool isDark)   => isDark ? darkTextMore   : lightTextMore;
  static Color textFaint(bool isDark)  => isDark ? darkTextFaint  : lightTextFaint;
  static Color title(bool isDark)      => isDark ? darkTitle      : lightTitle;
  static Color blue(bool isDark)       => isDark ? darkBlue       : lightBlue;
  static Color blueDeep(bool isDark)   => isDark ? darkBlueDeep   : lightBlueDeep;
  static Color blueSoft(bool isDark)   => isDark ? darkBlueSoft   : lightBlueSoft;
  static Color blueGlow(bool isDark)   => isDark ? darkBlueGlow   : lightBlueGlow;
  static Color amber(bool isDark)      => isDark ? darkAmber      : lightAmber;
  static Color red(bool isDark)        => isDark ? darkRed        : lightRed;
  static Color green(bool isDark)      => isDark ? darkGreen      : lightGreen;
  static Color chipBg(bool isDark)     => isDark ? darkChipBg     : lightChipBg;
  static Color chipText(bool isDark)   => isDark ? darkChipText   : lightChipText;
}

/// KitaKo App Text Styles
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle appBarTitle = TextStyle(
    color: AppColors.darkTitle,
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle heading1 = TextStyle(
    color: AppColors.darkText,
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading2 = TextStyle(
    color: AppColors.darkText,
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading3 = TextStyle(
    color: AppColors.darkText,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLarge = TextStyle(
    color: AppColors.darkText,
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodyMedium = TextStyle(
    color: AppColors.darkText,
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    color: AppColors.darkTextDim,
    fontSize: 12,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle hint = TextStyle(
    color: AppColors.darkTextMore,
    fontSize: 16,
  );

  static const TextStyle button = TextStyle(
    color: AppColors.darkText,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
}

/// KitaKo App Dimensions and Spacing
class AppDimensions {
  AppDimensions._();

  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 28.0;

  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 28.0;
  static const double iconXLarge = 40.0;

  static const int gridColumnCount = 3;
  static const double gridSpacing = 6.0;
  static const double gridAspectRatio = 1.0;

  static const double logoSize = 150.0;
  static const double logoCircleSmall = 20.0;
  static const double logoCircleMedium = 35.0;
  static const double logoCircleLarge = 60.0;
}
