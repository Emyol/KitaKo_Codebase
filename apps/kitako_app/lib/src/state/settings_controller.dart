import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/embedding_service.dart';

/// Persists the user's dev-facing model-variant preference across launches.
///
/// Only surfaced through the dev-mode section of the settings screen; default
/// is [ModelVariant.kitakoMixed] (FP32 vision + INT8 text).
class SettingsController extends ChangeNotifier {
  static const _prefKey = 'dev_selected_variant';
  static const ModelVariant defaultVariant = ModelVariant.kitakoMixed;

  ModelVariant _selectedVariant;

  SettingsController._(this._selectedVariant);

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    final variant = _decode(saved) ?? defaultVariant;
    return SettingsController._(variant);
  }

  ModelVariant get selectedVariant => _selectedVariant;

  Future<void> setSelectedVariant(ModelVariant variant) async {
    if (variant == _selectedVariant) return;
    _selectedVariant = variant;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, variant.name);
  }

  static ModelVariant? _decode(String? name) {
    if (name == null) return null;
    for (final v in ModelVariant.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
