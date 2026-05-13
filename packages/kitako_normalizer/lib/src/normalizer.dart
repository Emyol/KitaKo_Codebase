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

  /// Pre-compiled dictionary patterns — built once on first use, reused forever.
  /// Compiling 580+ RegExp objects per query was the main latency source.
  static final List<(RegExp, String)> _dictPatterns = [
    for (final e in normalizationDictionary.entries)
      (RegExp(r'\b' + RegExp.escape(e.key) + r'\b'), e.value),
  ];

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

    // Step 2b: Apply context-sensitive substitutions (whole-token matching,
    // prevents mid-word matches; see contextSensitiveDictionary in rules.dart)
    result = _applyContextSensitive(result);

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

    // Step 9: Strip Taglish verbal prefixes and English -ing gerunds
    final processedTokens = _processNagVerbs(tokens);

    // Step 10: Remove consecutive duplicates (except allowed reduplication)
    final dedupedTokens = _deduplicateTokens(processedTokens);

    // Final cleanup
    return dedupedTokens.join(' ').trim();
  }

  /// Applies dictionary mappings using pre-compiled word-boundary patterns.
  String _applyDictionary(String text) {
    var result = text;
    for (final (pattern, replacement) in _dictPatterns) {
      result = result.replaceAll(pattern, replacement);
    }
    return result;
  }

  /// Applies context-sensitive substitutions using exact whole-token matching.
  ///
  /// Splits text on whitespace and checks each token against
  /// [contextSensitiveDictionary]. The lowercase guard is preserved for
  /// documentation intent — all tokens are already lowercase after Step 1,
  /// but the check makes the constraint explicit and future-proofs the method
  /// against pipeline reordering.
  ///
  /// This step runs after [_applyDictionary] so that multi-word matches
  /// (e.g., 'san yung' → 'saan iyon') are consumed first, preventing the
  /// context-sensitive 'san' → 'saan' from double-firing on the same token.
  String _applyContextSensitive(String text) {
    final tokens = text.split(' ');
    final result = tokens.map((token) {
      if (token == token.toLowerCase()) {
        return contextSensitiveDictionary[token] ?? token;
      }
      return token;
    });
    return result.join(' ');
  }

  /// Collapses 3+ consecutive identical characters to 2.
  ///
  /// Preserves emphasis signal for the encoder while removing excessive
  /// noise. Collapsing to 1 is too aggressive — "hellooooo" → "helloo",
  /// not "helo". See DESIGN DECISION #2 in rules.dart block comment.
  ///
  /// Example: "hellooooo" → "helloo", "sobraaang" → "sobraang", "aaa" → "aa"
  String _collapseRepeatedChars(String text) {
    // Regex: any character followed by 2+ of the same character.
    // Replace the entire run with exactly 2 copies of that character.
    return text.replaceAllMapped(
      RegExp(r'(.)\1{2,}'),
      (match) => match.group(1)! + match.group(1)!,
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

  // Taglish verbal prefixes that attach to English verbs, longest first.
  static const List<String> _taglishPrefixes = [
    'naka', 'nag', 'mag', 'na', 'ma',
  ];

  /// Processes Taglish prefix + English verb patterns and standalone -ing gerunds.
  ///
  /// Strips Taglish verbal prefixes (nag-, naka-, na-, mag-, ma-) and/or the
  /// English -ing suffix to recover the base verb.
  /// Examples: "nagshopping" → "shop", "shopping" → "shop", "nagwork" → "work"
  List<String> _processNagVerbs(List<String> tokens) {
    return tokens.map(_normalizeVerb).toList();
  }

  String _normalizeVerb(String token) {
    for (final prefix in _taglishPrefixes) {
      if (token.startsWith(prefix) && token.length > prefix.length) {
        final stem = token.substring(prefix.length);
        if (englishVerbs.contains(stem)) return stem;
        final base = _stripIngSuffix(stem);
        if (base != null) return base;
      }
    }
    // No prefix — try stripping -ing from a standalone gerund.
    final base = _stripIngSuffix(token);
    if (base != null) return base;
    return token;
  }

  /// Strips the English -ing suffix and returns the base verb if it is in
  /// [englishVerbs]; returns null if no valid base is found.
  ///
  /// Handles three standard English -ing formation patterns:
  ///   direct strip   : cooking  → cook
  ///   doubled consonant: shopping → shopp → shop
  ///   e-drop         : hiking   → hik   → hike
  String? _stripIngSuffix(String word) {
    if (!word.endsWith('ing') || word.length <= 4) return null;
    final stem = word.substring(0, word.length - 3);
    if (englishVerbs.contains(stem)) return stem;
    // Doubled consonant: shopping → shopp → shop
    if (stem.length >= 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
      final undoubled = stem.substring(0, stem.length - 1);
      if (englishVerbs.contains(undoubled)) return undoubled;
    }
    // e-drop: hiking → hik → hike
    if (englishVerbs.contains('${stem}e')) return '${stem}e';
    return null;
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

  /// Runs the normalization pipeline and records a per-rule trace.
  ///
  /// Returns the same final output as [normalize] but also captures the
  /// before/after state for each of the seven thesis-level rules. Used by
  /// research instrumentation under `chapter_4_validation_src/` to produce
  /// the §4.2.1 results table (token-level firing rates per rule).
  ///
  /// Pipeline-step grouping into the seven rules cited in §3.4.4:
  ///   1. CaseFolding          (Step 1)
  ///   2. DictionarySubstitution (Steps 2 + 2b)
  ///   3. ApostropheHyphen     (Steps 3 + 4)
  ///   4. CharRunCollapse      (Step 5)
  ///   5. PunctuationSpacing   (Steps 6 + 7)
  ///   6. AffixStripping       (Step 9)
  ///   7. Reduplication        (Step 10)
  NormalizationTrace normalizeWithTrace(String text) {
    final input = text;
    final inputTokens = _whitespaceTokens(text).length;
    final steps = <RuleStep>[];

    if (text.isEmpty) {
      return NormalizationTrace(
        input: input,
        output: '',
        inputTokens: 0,
        steps: const [],
      );
    }

    String state = text;

    // Rule 1 — Case folding
    var before = state;
    state = state.toLowerCase();
    steps.add(_makeStringStep('CaseFolding', before, state));

    // Rule 2 — Dictionary substitution (general + context-sensitive)
    before = state;
    state = _applyDictionary(state);
    state = _applyContextSensitive(state);
    steps.add(_makeStringStep('DictionarySubstitution', before, state));

    // Rule 3 — Apostrophe + hyphen normalization
    before = state;
    state = state.replaceAll("'", '');
    state = state.replaceAll('-', ' ');
    steps.add(_makeStringStep('ApostropheHyphen', before, state));

    // Rule 4 — Character-run collapsing (3+ → 2)
    before = state;
    state = _collapseRepeatedChars(state);
    steps.add(_makeStringStep('CharRunCollapse', before, state));

    // Rule 5 — Punctuation spacing + whitespace normalization
    before = state;
    state = _spacePunctuation(state);
    state = state.replaceAll(RegExp(r'\s+'), ' ').trim();
    steps.add(_makeStringStep('PunctuationSpacing', before, state));

    // Tokenize once for the final two list-level rules.
    var tokens = state.split(' ').where((t) => t.isNotEmpty).toList();

    // Rule 6 — Affix stripping (nag-/naka-/na-/mag-/ma- + English verb, -ing gerunds)
    final beforeAffix = List<String>.from(tokens);
    tokens = _processNagVerbs(tokens);
    steps.add(_makeTokenStep('AffixStripping', beforeAffix, tokens));

    // Rule 7 — Reduplication-aware deduping
    final beforeDedup = List<String>.from(tokens);
    tokens = _deduplicateTokens(tokens);
    steps.add(_makeTokenStep('Reduplication', beforeDedup, tokens));

    return NormalizationTrace(
      input: input,
      output: tokens.join(' ').trim(),
      inputTokens: inputTokens,
      steps: steps,
    );
  }

  RuleStep _makeStringStep(String name, String before, String after) {
    final beforeTokens = _whitespaceTokens(before);
    final afterTokens = _whitespaceTokens(after);
    return RuleStep(
      ruleName: name,
      beforeText: before,
      afterText: after,
      beforeTokens: beforeTokens,
      afterTokens: afterTokens,
      affectedTokens: _tokenDiffCount(beforeTokens, afterTokens),
      fired: before != after,
    );
  }

  RuleStep _makeTokenStep(String name, List<String> before, List<String> after) {
    return RuleStep(
      ruleName: name,
      beforeText: before.join(' '),
      afterText: after.join(' '),
      beforeTokens: List<String>.unmodifiable(before),
      afterTokens: List<String>.unmodifiable(after),
      affectedTokens: _tokenDiffCount(before, after),
      fired: !_listEq(before, after),
    );
  }

  static List<String> _whitespaceTokens(String s) =>
      s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  /// Token-level edit metric: max(|a|, |b|) - LCS(a, b).
  /// Counts each substitution, insertion, or deletion as 1 affected token.
  static int _tokenDiffCount(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] >= dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    final lcs = dp[m][n];
    return (m > n ? m : n) - lcs;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One pipeline rule's contribution to a [NormalizationTrace].
class RuleStep {
  final String ruleName;
  final String beforeText;
  final String afterText;
  final List<String> beforeTokens;
  final List<String> afterTokens;

  /// Token-level edit count between [beforeTokens] and [afterTokens]
  /// (max length minus LCS). Substitution / insertion / deletion = 1.
  final int affectedTokens;

  /// Whether this rule changed the state at all.
  final bool fired;

  const RuleStep({
    required this.ruleName,
    required this.beforeText,
    required this.afterText,
    required this.beforeTokens,
    required this.afterTokens,
    required this.affectedTokens,
    required this.fired,
  });

  Map<String, dynamic> toJson() => {
        'rule': ruleName,
        'before': beforeText,
        'after': afterText,
        'before_tokens': beforeTokens,
        'after_tokens': afterTokens,
        'affected_tokens': affectedTokens,
        'fired': fired,
      };
}

/// Per-query record of every rule's firing produced by
/// [TaglishNormalizer.normalizeWithTrace].
class NormalizationTrace {
  final String input;
  final String output;
  final int inputTokens;
  final List<RuleStep> steps;

  const NormalizationTrace({
    required this.input,
    required this.output,
    required this.inputTokens,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'output': output,
        'input_tokens': inputTokens,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

/// Extension methods for String normalization.
extension TaglishStringExtension on String {
  /// Normalizes this string using [TaglishNormalizer].
  String normalizeTaglish() => const TaglishNormalizer().normalize(this);
}
