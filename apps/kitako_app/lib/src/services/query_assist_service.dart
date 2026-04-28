import '../models/search_models.dart';

/// On-device query assist service for bilingual Taglish search suggestions.
///
/// When a search produces no results or low-confidence results, this service
/// generates alternative query candidates using:
/// - Bilingual word substitution (Tagalog ↔ English)
/// - Content word extraction (stop word removal)
/// - Single content word fallback
/// - Full bilingual phrase translation
class QueryAssistService {
  /// Scores below this are treated as failed (no meaningful match).
  static const double _failedThreshold = 0.08;

  /// Scores below this (but above [_failedThreshold]) are treated as weak.
  static const double _weakThreshold = 0.095;

  /// Bidirectional content-word translation dictionary (Tagalog ↔ English).
  /// Covers common photo-relevant nouns, adjectives, and actions.
  static const Map<String, String> _bilingualDict = {
    // Tagalog → English
    'pusa': 'cat',
    'aso': 'dog',
    'bahay': 'house',
    'kotse': 'car',
    'pagkain': 'food',
    'damit': 'clothes',
    'lalaki': 'man',
    'babae': 'woman',
    'bata': 'child',
    'pamilya': 'family',
    'kaibigan': 'friend',
    'dagat': 'beach',
    'bundok': 'mountain',
    'ibon': 'bird',
    'puno': 'tree',
    'bulaklak': 'flower',
    'masaya': 'happy',
    'malungkot': 'sad',
    'kain': 'eating',
    'tulog': 'sleeping',
    'laro': 'playing',
    'takbo': 'running',
    'langoy': 'swimming',
    'sayaw': 'dancing',
    'kanta': 'singing',
    'araw': 'day',
    'gabi': 'night',
    'ulan': 'rain',
    'araw-araw': 'sun',
    'ulap': 'cloud',
    'hangin': 'wind',
    'apoy': 'fire',
    'tubig': 'water',
    'lupa': 'ground',
    'langit': 'sky',
    'gulay': 'vegetable',
    'prutas': 'fruit',
    'isda': 'fish',
    'manok': 'chicken',
    'baboy': 'pig',
    'baka': 'cow',
    'kabayo': 'horse',
    'daan': 'road',
    'tulay': 'bridge',
    'simbahan': 'church',
    'eskwelahan': 'school',
    'ospital': 'hospital',
    'palengke': 'market',
    // English → Tagalog
    'cat': 'pusa',
    'dog': 'aso',
    'house': 'bahay',
    'car': 'kotse',
    'food': 'pagkain',
    'man': 'lalaki',
    'woman': 'babae',
    'child': 'bata',
    'family': 'pamilya',
    'friend': 'kaibigan',
    'beach': 'dagat',
    'mountain': 'bundok',
    'bird': 'ibon',
    'tree': 'puno',
    'flower': 'bulaklak',
    'happy': 'masaya',
    'sad': 'malungkot',
    'eating': 'kain',
    'sleeping': 'tulog',
    'playing': 'laro',
    'running': 'takbo',
    'swimming': 'langoy',
    'dancing': 'sayaw',
    'singing': 'kanta',
    'rain': 'ulan',
    'sky': 'langit',
    'water': 'tubig',
    'fire': 'apoy',
    'fish': 'isda',
    'chicken': 'manok',
    'road': 'daan',
    'bridge': 'tulay',
    'church': 'simbahan',
    'school': 'eskwelahan',
    'market': 'palengke',
  };

  /// Function words and particles that carry no visual meaning for photo search.
  static const Set<String> _stopWords = {
    // Tagalog particles
    'ang', 'ng', 'sa', 'na', 'at', 'ay', 'mga', 'pa', 'nga', 'din', 'rin',
    'naman', 'ba', 'po', 'ho', 'dito', 'doon', 'diyan', 'ito', 'iyon', 'iyan',
    'kaya', 'pero', 'kundi', 'dahil', 'kung', 'kapag', 'habang',
    // Tagalog pronouns
    'ako', 'ikaw', 'siya', 'kami', 'tayo', 'kayo', 'sila',
    'ko', 'mo', 'niya', 'namin', 'natin', 'ninyo', 'nila',
    'akin', 'iyo', 'kaniya', 'amin', 'atin', 'inyo', 'kanila',
    // English articles, prepositions, pronouns
    'the', 'a', 'an',
    'my', 'your', 'his', 'her', 'our', 'their', 'its',
    'i', 'you', 'he', 'she', 'we', 'they', 'it',
    'me', 'him', 'us', 'them',
    'in', 'on', 'to', 'for', 'of', 'with', 'from', 'by',
    'and', 'or', 'but', 'so', 'yet',
    'last', 'this', 'that', 'these', 'those',
    'some', 'any', 'all', 'every', 'each',
    'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did',
    'about', 'after', 'before', 'between', 'during',
  };

  /// Classify confidence level from raw search scores.
  ///
  /// - [scores]: Similarity scores from the search, sorted descending.
  /// - [resultCount]: Number of results returned.
  QueryConfidence detectConfidence(List<double>? scores, int resultCount) {
    if (resultCount == 0) return QueryConfidence.failed;
    final topScore =
        (scores != null && scores.isNotEmpty) ? scores.first : 0.0;
    if (topScore < _failedThreshold) return QueryConfidence.failed;
    if (topScore < _weakThreshold) return QueryConfidence.weak;
    return QueryConfidence.strong;
  }

  /// Generate up to [maxSuggestions] alternative query strings for [normalizedQuery].
  ///
  /// Strategies applied in priority order:
  /// 1. Bilingual word substitution (per-token translation)
  /// 2. Content word extraction (remove stop words)
  /// 3. Single content word fallback
  /// 4. Full bilingual phrase translation
  List<String> generateSuggestions(
    String normalizedQuery, {
    int maxSuggestions = 4,
  }) {
    final input = normalizedQuery.trim().toLowerCase();
    if (input.isEmpty) return const [];

    final tokens = input.split(RegExp(r'\s+'));
    final candidates = <String>{};

    // Strategy 1: Per-token bilingual substitution
    for (final token in tokens) {
      final translated = _bilingualDict[token];
      if (translated != null) {
        // Full phrase with this token replaced
        final replaced =
            tokens.map((t) => t == token ? translated : t).join(' ');
        candidates.add(replaced);
        // Also the translated word alone
        candidates.add(translated);
      }
    }

    // Strategy 2: Content words only (strip stop words)
    final contentWords =
        tokens.where((t) => !_stopWords.contains(t)).toList();
    if (contentWords.isNotEmpty && contentWords.length < tokens.length) {
      candidates.add(contentWords.join(' '));
    }

    // Strategy 3: Individual content word fallback (for multi-word queries)
    if (tokens.length > 1) {
      for (final word in contentWords) {
        if (word.length > 2) candidates.add(word);
      }
    }

    // Strategy 4: Full bilingual translation of the whole phrase
    final fullyTranslated =
        tokens.map((t) => _bilingualDict[t] ?? t).join(' ');
    if (fullyTranslated != input) candidates.add(fullyTranslated);

    // Remove the original query and empty strings
    candidates
      ..remove(input)
      ..removeWhere((s) => s.trim().isEmpty);

    return candidates.take(maxSuggestions).toList();
  }
}
