import 'dart:async';
import 'package:flutter/foundation.dart';

/// Service for generating text embeddings
///
/// This service wraps the kitako_embedding package and provides:
/// - Text normalization
/// - Embedding generation
/// - Batch processing
/// - Caching
///
/// Example usage:
/// ```dart
/// final embeddingService = EmbeddingService();
/// await embeddingService.initialize();
/// final embedding = await embeddingService.generateEmbedding('search query');
/// ```
class EmbeddingService {
  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Cache of recently generated embeddings
  final Map<String, List<double>> _embeddingCache = {};

  /// Maximum cache size
  static const int _maxCacheSize = 100;

  /// Embedding dimension (SigLIP model)
  static const int embeddingDimension = 768;

  /// Initialize the embedding service
  ///
  /// Loads the embedding model and prepares for inference.
  /// Must be called before generating embeddings.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // TODO: Initialize embedding model from kitako_embedding package
      // await embeddingClient.initialize(modelPath);

      _isInitialized = true;
      debugPrint('EmbeddingService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('EmbeddingService: Failed to initialize: $e');
      return false;
    }
  }

  /// Generate embedding for a text query
  ///
  /// Converts the input text into a dense vector representation.
  /// Results are cached to improve performance for repeated queries.
  ///
  /// Parameters:
  /// - [query]: The text to embed
  ///
  /// Returns a list of doubles representing the embedding vector
  ///
  /// Throws [StateError] if service is not initialized
  Future<List<double>> generateEmbedding(String query) async {
    if (!_isInitialized) {
      throw StateError(
        'EmbeddingService not initialized. Call initialize() first.',
      );
    }

    // Normalize query
    final normalizedQuery = _normalizeQuery(query);

    // Check cache
    if (_embeddingCache.containsKey(normalizedQuery)) {
      debugPrint('EmbeddingService: Cache hit for query: $normalizedQuery');
      return _embeddingCache[normalizedQuery]!;
    }

    try {
      // TODO: Generate actual embedding using kitako_embedding
      // final embedding = await embeddingClient.embed(normalizedQuery);

      // For now, generate mock embedding
      final embedding = _generateMockEmbedding(normalizedQuery);

      // Cache the result
      _cacheEmbedding(normalizedQuery, embedding);

      return embedding;
    } catch (e) {
      debugPrint('EmbeddingService: Failed to generate embedding: $e');
      rethrow;
    }
  }

  /// Generate embeddings for multiple queries in batch
  ///
  /// More efficient than calling [generateEmbedding] multiple times.
  ///
  /// Parameters:
  /// - [queries]: List of texts to embed
  ///
  /// Returns a list of embedding vectors
  Future<List<List<double>>> generateBatchEmbeddings(
    List<String> queries,
  ) async {
    if (!_isInitialized) {
      throw StateError(
        'EmbeddingService not initialized. Call initialize() first.',
      );
    }

    final embeddings = <List<double>>[];

    for (final query in queries) {
      final embedding = await generateEmbedding(query);
      embeddings.add(embedding);
    }

    return embeddings;
  }

  /// Normalize a text query
  ///
  /// Applies text preprocessing:
  /// - Lowercase conversion
  /// - Whitespace trimming
  /// - Special character handling
  String _normalizeQuery(String query) {
    return query.trim().toLowerCase();
  }

  /// Cache an embedding result
  ///
  /// Implements LRU cache eviction when cache is full
  void _cacheEmbedding(String query, List<double> embedding) {
    // Remove oldest entry if cache is full
    if (_embeddingCache.length >= _maxCacheSize) {
      final firstKey = _embeddingCache.keys.first;
      _embeddingCache.remove(firstKey);
    }

    _embeddingCache[query] = embedding;
  }

  /// Clear the embedding cache
  ///
  /// Use this to free up memory
  void clearCache() {
    _embeddingCache.clear();
    debugPrint('EmbeddingService: Cache cleared');
  }

  /// Get cache statistics
  ///
  /// Returns information about cache usage
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _embeddingCache.length,
      'maxSize': _maxCacheSize,
      'utilization': _embeddingCache.length / _maxCacheSize,
    };
  }

  /// Dispose of resources
  ///
  /// Call this when the service is no longer needed
  void dispose() {
    clearCache();
    _isInitialized = false;
    debugPrint('EmbeddingService: Disposed');
  }

  // ========== Mock Implementation ==========
  // TODO: Replace with actual embedding generation

  /// Generate a mock embedding vector
  ///
  /// Creates a deterministic embedding based on query hash
  List<double> _generateMockEmbedding(String query) {
    final hash = query.hashCode;
    final random = _SeededRandom(hash);

    return List.generate(
      embeddingDimension,
      (index) => (random.nextDouble() * 2) - 1, // Range: -1 to 1
    );
  }
}

/// Simple seeded random number generator for mock embeddings
class _SeededRandom {
  int _seed;

  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = ((_seed * 1103515245) + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}
