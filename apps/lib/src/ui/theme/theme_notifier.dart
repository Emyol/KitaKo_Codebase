import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme notifier for managing app theme mode with persistence.
///
/// Use [ThemeNotifier.load()] to restore the saved preference on startup.
/// Defaults to [ThemeMode.light] when no preference is saved.
class ThemeNotifier extends ChangeNotifier {
  static const _prefKey = 'theme_is_dark';
  static const _girlyKey = 'theme_girly_pop';

  /// Static handle so context-free palette helpers can read the current
  /// girly-pop flag without threading the notifier through every constructor.
  /// Set in [load]; reset to null in [dispose].
  static ThemeNotifier? maybeInstance;

  ThemeMode _themeMode;
  bool _girlyPop;

  ThemeNotifier._(this._themeMode, this._girlyPop);

  /// Loads the saved theme preference from disk.
  ///
  /// Falls back to [ThemeMode.light] if no preference has been saved yet.
  static Future<ThemeNotifier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_prefKey) ?? false; // default: light
    final girly = prefs.getBool(_girlyKey) ?? false;
    final n = ThemeNotifier._(
      isDark ? ThemeMode.dark : ThemeMode.light,
      girly,
    );
    maybeInstance = n;
    return n;
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get girlyPop => _girlyPop;

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    _save(isDark);
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _save(mode == ThemeMode.dark);
  }

  void setGirlyPop(bool enabled) {
    if (_girlyPop == enabled) return;
    _girlyPop = enabled;
    notifyListeners();
    _saveGirly(enabled);
  }

  Future<void> _save(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, isDark);
  }

  Future<void> _saveGirly(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_girlyKey, enabled);
  }

  @override
  void dispose() {
    if (identical(maybeInstance, this)) maybeInstance = null;
    super.dispose();
  }
}
