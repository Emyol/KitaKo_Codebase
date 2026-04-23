import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme notifier for managing app theme mode with persistence.
///
/// Use [ThemeNotifier.load()] to restore the saved preference on startup.
/// Defaults to [ThemeMode.light] when no preference is saved.
class ThemeNotifier extends ChangeNotifier {
  static const _prefKey = 'theme_is_dark';

  ThemeMode _themeMode;

  ThemeNotifier._(this._themeMode);

  /// Loads the saved theme preference from disk.
  ///
  /// Falls back to [ThemeMode.light] if no preference has been saved yet.
  static Future<ThemeNotifier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_prefKey) ?? false; // default: light
    return ThemeNotifier._(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

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

  Future<void> _save(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, isDark);
  }
}
