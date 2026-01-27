import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';

/// Service wrapper for Taglish text normalization in the app.
///
/// Wraps [TaglishNormalizer] from the kitako_normalizer package
/// and provides app-level integration with caching and logging.
///
/// Example:
/// ```dart
/// final service = NormalizerService();
/// final normalized = service.normalize('ngshopping aq sa mall');
/// print(normalized); // "shopping ako sa mall"
/// ```
class NormalizerService {
  /// The underlying normalizer instance.
  final TaglishNormalizer _normalizer;

  /// Cache of recently normalized queries for performance.
  final Map<String, String> _cache = {};

  /// Maximum cache size before eviction.
  static const int _maxCacheSize = 200;

  /// Whether to log normalization operations.
  final bool enableLogging;

  /// Creates a new NormalizerService.
  ///
  /// Set [enableLogging] to true for debug output.
  NormalizerService({
    this.enableLogging = false,
  }) : _normalizer = const TaglishNormalizer();

  /// Normalizes the given text query.
  ///
  /// Returns the normalized text suitable for embedding generation.
  /// Results are cached for repeated queries.
  String normalize(String text) {
    if (text.isEmpty) return text;

    // Check cache first
    final cached = _cache[text];
    if (cached != null) {
      if (enableLogging) {
        debugPrint('NormalizerService: Cache hit for "$text"');
      }
      return cached;
    }

    // Normalize
    final stopwatch = Stopwatch()..start();
    final normalized = _normalizer.normalize(text);
    stopwatch.stop();

    if (enableLogging) {
      debugPrint(
        'NormalizerService: Normalized "$text" → "$normalized" '
        'in ${stopwatch.elapsedMicroseconds}µs',
      );
    }

    // Cache result
    _cacheResult(text, normalized);

    return normalized;
  }

  /// Normalizes multiple queries in batch.
  ///
  /// More efficient than calling [normalize] multiple times
  /// as it can leverage caching better.
  List<String> normalizeBatch(List<String> texts) {
    return texts.map(normalize).toList();
  }

  /// Clears the normalization cache.
  void clearCache() {
    _cache.clear();
    if (enableLogging) {
      debugPrint('NormalizerService: Cache cleared');
    }
  }

  /// Gets cache statistics.
  Map<String, int> get cacheStats => {
        'size': _cache.length,
        'maxSize': _maxCacheSize,
      };

  /// Caches a normalization result with LRU eviction.
  void _cacheResult(String input, String output) {
    // Evict oldest entry if cache is full
    if (_cache.length >= _maxCacheSize) {
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
    }
    _cache[input] = output;
  }
}
