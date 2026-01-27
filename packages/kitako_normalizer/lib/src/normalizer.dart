import 'rules.dart';

/// Taglish text normalizer for KitaKo image search.
///
/// Normalizes Filipino/Tagalog/Taglish text queries by:
/// - Expanding abbreviations and text speak
/// - Handling code-switching patterns (e.g., "nag-" + English verb)
/// - Removing excessive punctuation and repeated characters
/// - Preserving meaningful reduplication (e.g., "araw-araw")
///
/// Example:
/// ```dart
/// final normalizer = TaglishNormalizer();
/// final normalized = normalizer.normalize('nagshopping aq kanina!!');
/// print(normalized); // "shopping ako kanina !"
/// ```
class TaglishNormalizer {
  /// Creates a new TaglishNormalizer with default rules.
  const TaglishNormalizer();

  /// Punctuation characters to add spacing around.
  static const String _punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';

  /// Normalizes Taglish text for embedding/search.
  ///
  /// Processing steps:
  /// 1. Lowercase conversion
  /// 2. Dictionary-based expansion (abbreviations → full words)
  /// 3. Remove apostrophes
  /// 4. Convert hyphens to spaces
  /// 5. Collapse repeated characters (3+ → 1)
  /// 6. Add spacing around punctuation
  /// 7. Normalize whitespace
  /// 8. Handle "nag-" + English verb patterns
  /// 9. Remove consecutive duplicate words (preserving allowed reduplication)
  ///
  /// Returns the normalized text string.
  String normalize(String text) {
    if (text.isEmpty) return text;

    // Step 1: Lowercase
    var result = text.toLowerCase();

    // Step 2: Apply dictionary mappings
    result = _applyDictionary(result);

    // Step 3: Remove apostrophes
    result = result.replaceAll("'", '');

    // Step 4: Convert hyphens to spaces
    result = result.replaceAll('-', ' ');

    // Step 5: Normalize repeated characters (3+ of same char → 1)
    result = _collapseRepeatedChars(result);

    // Step 6: Add space around punctuation
    result = _spacePunctuation(result);

    // Step 7: Normalize spacing
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Step 8: Tokenize and process
    final tokens = result.split(' ');

    // Step 9: Handle "nag-" + English verb patterns
    final processedTokens = _processNagVerbs(tokens);

    // Step 10: Remove consecutive duplicates (except allowed reduplication)
    final dedupedTokens = _deduplicateTokens(processedTokens);

    // Final cleanup
    return dedupedTokens.join(' ').trim();
  }

  /// Applies dictionary mappings using word boundaries.
  String _applyDictionary(String text) {
    var result = text;
    for (final entry in normalizationDictionary.entries) {
      // Use word boundary regex for accurate replacement
      final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b');
      result = result.replaceAll(pattern, entry.value);
    }
    return result;
  }

  /// Collapses 3+ consecutive identical characters to 1.
  /// Matches Python: re.sub(r"(.)\1{2,}", r"\1", text)
  ///
  /// Example: "hellooo" → "helo", "niceeee" → "nice"
  String _collapseRepeatedChars(String text) {
    // Regex: any character followed by 2+ of the same character
    // Replace with just the first occurrence
    return text.replaceAllMapped(
      RegExp(r'(.)\1{2,}'),
      (match) => match.group(1)!,
    );
  }

  /// Adds spaces around punctuation characters.
  String _spacePunctuation(String text) {
    var result = text;
    for (int i = 0; i < _punctuation.length; i++) {
      final p = _punctuation[i];
      result = result.replaceAll(p, ' $p ');
    }
    return result;
  }

  /// Processes "nag-" + English verb patterns.
  ///
  /// Converts Taglish verb conjugations to base English verbs.
  /// Example: "nagshopping" → "shopping", "nagcooking" → "cooking"
  List<String> _processNagVerbs(List<String> tokens) {
    final result = <String>[];

    for (var token in tokens) {
      if (token.startsWith('nag')) {
        // Check if token ends with any English verb
        for (final verb in englishVerbs) {
          if (token.endsWith(verb)) {
            token = verb;
            break;
          }
        }
      }
      result.add(token);
    }

    return result;
  }

  /// Removes consecutive duplicate tokens.
  ///
  /// Preserves duplicates that are in [allowedReduplication] set.
  /// Example: "ang ang" → "ang", but "araw araw" stays as "araw araw"
  List<String> _deduplicateTokens(List<String> tokens) {
    if (tokens.isEmpty) return tokens;

    final result = <String>[];
    String? prev;

    for (final token in tokens) {
      if (prev != null) {
        final pair = '$prev $token';
        // Skip duplicate if not in allowed reduplication
        if (token == prev && !allowedReduplication.contains(pair)) {
          continue;
        }
      }
      result.add(token);
      prev = token;
    }

    return result;
  }
}

/// Extension methods for String normalization.
extension TaglishStringExtension on String {
  /// Normalizes this string using [TaglishNormalizer].
  String normalizeTaglish() => const TaglishNormalizer().normalize(this);
}
