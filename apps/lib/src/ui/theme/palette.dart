import 'package:flutter/material.dart';
import 'theme_notifier.dart';

/// Context-free palette. Standard mode reproduces the original blue scheme
/// (light or dark depending on [isDark]). When [ThemeNotifier.girlyPop] is
/// on, every token returns a girly-pop value — saturated pink background,
/// white foreground — regardless of [isDark]. This way a single flag flip
/// repaints every surface and text run without per-screen branching.
class P {
  P._();

  // ── Standard blue scheme (matches AppColors) ────────────────────────
  // bg / surface / border
  static const _dBg          = Color(0xFF0E1116);
  static const _lBg          = Color(0xFFF4F7FB);
  static const _dSurface     = Color(0xFF161B22);
  static const _lSurface     = Color(0xFFFFFFFF);
  static const _dSurfaceAlt  = Color(0xFF1A2030);
  static const _lSurfaceAlt  = Color(0xFFE2EAF4);
  static const _dSurfaceHigh = Color(0xFF222A36);
  static const _lSurfaceHigh = Color(0xFFEEF3FA);
  static const _dBorder      = Color(0xFF1F2733);
  static const _lBorder      = Color(0xFFE2E8F0);
  // text
  static const _dText        = Color(0xFFFFFFFF);
  static const _lText        = Color(0xFF0F172A);
  static const _dTextDim     = Color(0xC7FFFFFF); // ~0.78
  static const _lTextDim     = Color(0xFF475569);
  static const _dTextMore    = Color(0x8CFFFFFF); // ~0.55
  static const _lTextMore    = Color(0xFF64748B);
  static const _dTextFaint   = Color(0x61FFFFFF); // ~0.38
  static const _lTextFaint   = Color(0xFF94A3B8);
  // accent
  static const _dAccent      = Color(0xFF3B82F6);
  static const _lAccent      = Color(0xFF2563EB);
  static const _dAccentDeep  = Color(0xFF1D4ED8);
  static const _lAccentDeep  = Color(0xFF1D4ED8);
  static const _dAccentSoft  = Color(0x2E3B82F6);
  static const _lAccentSoft  = Color(0xFFDBEAFE);
  static const _dAccentGlow  = Color(0x593B82F6);
  static const _lAccentGlow  = Color(0x2E2563EB);
  static const _dChipBg      = Color(0x243B82F6);
  static const _lChipBg      = Color(0xFFDBEAFE);
  static const _dChipText    = Color(0xFF93C5FD);
  static const _lChipText    = Color(0xFF1D4ED8);
  static const _dTitle       = Color(0xFF60A5FA);
  static const _lTitle       = Color(0xFF0B2545);
  static const _dHairline    = Color(0x1F60A5FA);
  static const _lHairline    = Color(0x192563EB);

  // ── Girly-pop scheme: hot-pink bg + white text everywhere ────────────
  // Inverted brightness: same colors regardless of dark/light system mode.
  static const _gBg          = Color(0xFFF7C8DC); // muted rose — soft canvas
  static const _gSurface     = Color(0xFFFBD8E6); // lighter rose — card on bg
  static const _gSurfaceAlt  = Color(0xFFF1B4CE); // deeper rose — card alt
  static const _gSurfaceHigh = Color(0xFFE89DBE); // deepest rose accent
  static const _gBorder      = Color(0x3D500724); // wine @ 0.24
  // Dark wine/lipstick foreground — high contrast on hot-pink canvas,
  // reads as glam/Y2K rather than flat white-on-pink.
  static const _gText        = Color(0xFF500724); // pink-950
  static const _gTextDim     = Color(0xFF831843); // pink-900
  static const _gTextMore    = Color(0xCC500724); // pink-950 @ 0.80
  static const _gTextFaint   = Color(0x99500724); // pink-950 @ 0.60
  static const _gAccent      = Color(0xFFFFFFFF); // white pop on pink
  static const _gAccentDeep  = Color(0xFFFCE7F3); // pink-100
  static const _gAccentSoft  = Color(0x33FFFFFF); // white @ 0.20
  static const _gAccentGlow  = Color(0x59FFFFFF); // white @ 0.35
  static const _gChipBg      = Color(0xFFFCE7F3); // pink-100 chip
  static const _gChipText    = Color(0xFF500724); // pink-950 chip text
  static const _gTitle       = Color(0xFF500724); // pink-950 titles
  static const _gHairline    = Color(0x29500724); // wine @ 0.16

  static bool get girly =>
      ThemeNotifier.maybeInstance?.girlyPop ?? false;

  // bg / surface / border ─────────────────────────────────────────────
  static Color bg(bool isDark) =>
      girly ? _gBg : (isDark ? _dBg : _lBg);
  static Color surface(bool isDark) =>
      girly ? _gSurface : (isDark ? _dSurface : _lSurface);
  static Color surfaceAlt(bool isDark) =>
      girly ? _gSurfaceAlt : (isDark ? _dSurfaceAlt : _lSurfaceAlt);
  static Color surfaceHigh(bool isDark) =>
      girly ? _gSurfaceHigh : (isDark ? _dSurfaceHigh : _lSurfaceHigh);
  static Color border(bool isDark) =>
      girly ? _gBorder : (isDark ? _dBorder : _lBorder);

  // text ──────────────────────────────────────────────────────────────
  static Color text(bool isDark) =>
      girly ? _gText : (isDark ? _dText : _lText);
  static Color textDim(bool isDark) =>
      girly ? _gTextDim : (isDark ? _dTextDim : _lTextDim);
  static Color textMore(bool isDark) =>
      girly ? _gTextMore : (isDark ? _dTextMore : _lTextMore);
  static Color textFaint(bool isDark) =>
      girly ? _gTextFaint : (isDark ? _dTextFaint : _lTextFaint);

  // accent ────────────────────────────────────────────────────────────
  static Color accent(bool isDark) =>
      girly ? _gAccent : (isDark ? _dAccent : _lAccent);
  static Color accentDeep(bool isDark) =>
      girly ? _gAccentDeep : (isDark ? _dAccentDeep : _lAccentDeep);
  static Color accentSoft(bool isDark) =>
      girly ? _gAccentSoft : (isDark ? _dAccentSoft : _lAccentSoft);
  static Color accentGlow(bool isDark) =>
      girly ? _gAccentGlow : (isDark ? _dAccentGlow : _lAccentGlow);
  static Color chipBg(bool isDark) =>
      girly ? _gChipBg : (isDark ? _dChipBg : _lChipBg);
  static Color chipText(bool isDark) =>
      girly ? _gChipText : (isDark ? _dChipText : _lChipText);
  static Color title(bool isDark) =>
      girly ? _gTitle : (isDark ? _dTitle : _lTitle);
  static Color hairline(bool isDark) =>
      girly ? _gHairline : (isDark ? _dHairline : _lHairline);

  /// Foreground for icons/text sitting on top of an [accent]-colored surface
  /// (FilledButton, send-pill circle, badge). Normal scheme uses white on the
  /// blue surface; girly inverts because accent is white, so the icon needs
  /// the dark-wine foreground to read.
  static Color onAccent(bool isDark) =>
      girly ? _gText : const Color(0xFFFFFFFF);
}
