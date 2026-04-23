import 'package:shared_preferences/shared_preferences.dart';

/// Persists recent text search queries across sessions.
class SearchHistoryService {
  static const _key = 'search_query_history';
  static const _maxEntries = 20;

  List<String> _queries = [];

  /// Returns an unmodifiable copy of saved queries, most recent first.
  List<String> get queries => List.unmodifiable(_queries);

  /// Load history from shared preferences. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _queries = prefs.getStringList(_key) ?? [];
  }

  /// Add [query] to the top of the list, removing any duplicate.
  Future<void> addQuery(String query) async {
    query = query.trim();
    if (query.isEmpty) return;
    _queries.remove(query);
    _queries.insert(0, query);
    if (_queries.length > _maxEntries) {
      _queries = _queries.sublist(0, _maxEntries);
    }
    await _save();
  }

  /// Remove a single [query] from history.
  Future<void> removeQuery(String query) async {
    _queries.remove(query);
    await _save();
  }

  /// Remove all history entries.
  Future<void> clearAll() async {
    _queries.clear();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _queries);
  }
}
