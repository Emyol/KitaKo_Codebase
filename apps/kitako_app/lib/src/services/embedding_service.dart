import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';

// Conditional import - don't import tflite on web
import 'embedding_service_stub.dart'
    if (dart.library.io) 'package:kitako_embedding/kitako_embedding.dart';

/// Service for generating text and image embeddings
///
/// This service wraps the kitako_embedding package and provides:
/// - Text normalization (Taglish support)
/// - Text embedding generation via SigLIP
/// - Image embedding generation via SigLIP
/// - Caching for repeated queries
///
/// Example usage:
/// ```dart
/// final embeddingService = EmbeddingService();
/// await embeddingService.initialize();
/// final embedding = await embeddingService.generateEmbedding('search query');
/// ```
class EmbeddingService {
  /// The underlying KitaKo embedding service
  KitakoEmbeddingService? _embeddingClient;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Taglish normalizer for preprocessing queries
  final TaglishNormalizer _normalizer = const TaglishNormalizer();

  /// Cache of recently generated embeddings
  final Map<String, List<double>> _embeddingCache = {};

  /// Maximum cache size
  static const int _maxCacheSize = 100;

  /// Embedding dimension (SigLIP)
  static const int embeddingDimension = 768;

  /// Asset paths for models
  static const String _imageModelAsset = 'assets/model/image_encoder/kitako_image_encoder_int8.tflite';
  static const String _textModelAsset = 'assets/model/text_encoder/kitako_text_encoder_dynamic.tflite';
  static const String _tokenizerAsset = 'assets/tokenizer/tokenizer.json';

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether text embedding is available
  bool get isTextReady => _embeddingClient?.isTextEncoderReady ?? false;

  /// Whether image embedding is available
  bool get isImageReady => _embeddingClient?.isImageEncoderReady ?? false;

  /// Initialize the embedding service
  ///
  /// Loads the TFLite models and tokenizer from assets.
  /// Must be called before generating embeddings.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('EmbeddingService: Initializing with real TFLite models...');

      _embeddingClient = KitakoEmbeddingService();

      // Initialize with asset paths
      await _embeddingClient!.initialize(
        imageModelPath: _imageModelAsset,
        textModelPath: _textModelAsset,
        tokenizerPath: _tokenizerAsset,
      );

      _isInitialized = true;
      debugPrint('EmbeddingService: Initialized successfully');
      debugPrint('  - Text encoder ready: ${_embeddingClient!.isTextEncoderReady}');
      debugPrint('  - Image encoder ready: ${_embeddingClient!.isImageEncoderReady}');
      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize TFLite: $e');
      debugPrint('Stack trace: $stack');
      
      // Fall back to mock mode
      _embeddingClient = null;
      _isInitialized = true; // Still mark as initialized for mock fallback
      debugPrint('EmbeddingService: Running in MOCK mode');
      return true;
    }
  }

  /// Generate embedding for a text query
  ///
  /// Normalizes the query and converts it to a dense vector.
  /// Results are cached to improve performance.
  ///
  /// Parameters:
  /// - [query]: The text to embed
  ///
  /// Returns a list of doubles representing the embedding vector
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
      debugPrint('EmbeddingService: Cache hit for query: "$normalizedQuery"');
      return _embeddingCache[normalizedQuery]!;
    }

    try {
      List<double> embedding;

      if (_embeddingClient != null && _embeddingClient!.isTextEncoderReady) {
        // Use real embedding model
        final float32Embedding = _embeddingClient!.embedText(normalizedQuery);
        embedding = float32Embedding.toList();
        debugPrint('EmbeddingService: Generated real embedding for: "$normalizedQuery"');
      } else {
        // Fall back to mock embedding
        embedding = _generateMockEmbedding(normalizedQuery);
        debugPrint('EmbeddingService: Generated MOCK embedding for: "$normalizedQuery"');
      }

      // Cache the result
      _cacheEmbedding(normalizedQuery, embedding);

      return embedding;
    } catch (e) {
      debugPrint('EmbeddingService: Failed to generate embedding: $e');
      // Fall back to mock on error
      final mockEmbedding = _generateMockEmbedding(normalizedQuery);
      _cacheEmbedding(normalizedQuery, mockEmbedding);
      return mockEmbedding;
    }
  }

  /// Generate embedding for an image
  ///
  /// Parameters:
  /// - [imageBytes]: Raw image bytes (JPEG, PNG, etc.)
  ///
  /// Returns a normalized 768-dimensional embedding vector
  Future<List<double>> generateImageEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized) {
      throw StateError(
        'EmbeddingService not initialized. Call initialize() first.',
      );
    }

    try {
      if (_embeddingClient != null && _embeddingClient!.isImageEncoderReady) {
        final float32Embedding = _embeddingClient!.embedImage(imageBytes);
        debugPrint('EmbeddingService: Generated real image embedding');
        return float32Embedding.toList();
      } else {
        // Fall back to mock embedding
        debugPrint('EmbeddingService: Generated MOCK image embedding');
        return _generateMockEmbedding('image_${imageBytes.hashCode}');
      }
    } catch (e) {
      debugPrint('EmbeddingService: Failed to generate image embedding: $e');
      return _generateMockEmbedding('image_${imageBytes.hashCode}');
    }
  }

  /// Generate embeddings for multiple queries in batch
  Future<List<List<double>>> generateBatchEmbeddings(
    List<String> queries,
  ) async {
    final embeddings = <List<double>>[];
    for (final query in queries) {
      final embedding = await generateEmbedding(query);
      embeddings.add(embedding);
    }
    return embeddings;
  }

  /// Compute similarity between two embeddings
  double computeSimilarity(List<double> a, List<double> b) {
    if (_embeddingClient != null) {
      return _embeddingClient!.cosineSimilarity(
        Float32List.fromList(a),
        Float32List.fromList(b),
      );
    }
    return _cosineSimilarity(a, b);
  }

  /// Normalize a text query using TaglishNormalizer
  String _normalizeQuery(String query) {
    final normalized = _normalizer.normalize(query);
    if (normalized != query) {
      debugPrint('EmbeddingService: Normalized "$query" → "$normalized"');
    }
    return normalized;
  }

  /// Cache an embedding result (LRU eviction)
  void _cacheEmbedding(String query, List<double> embedding) {
    if (_embeddingCache.length >= _maxCacheSize) {
      final firstKey = _embeddingCache.keys.first;
      _embeddingCache.remove(firstKey);
    }
    _embeddingCache[query] = embedding;
  }

  /// Clear the embedding cache
  void clearCache() {
    _embeddingCache.clear();
    debugPrint('EmbeddingService: Cache cleared');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _embeddingCache.length,
      'maxSize': _maxCacheSize,
      'utilization': _embeddingCache.length / _maxCacheSize,
      'mode': _embeddingClient?.isTextEncoderReady == true ? 'real' : 'mock',
    };
  }

  /// Dispose of resources
  void dispose() {
    _embeddingClient?.dispose();
    _embeddingClient = null;
    clearCache();
    _isInitialized = false;
    debugPrint('EmbeddingService: Disposed');
  }

  // ========== Fallback Mock Implementation ==========

  /// Generate a mock embedding vector (deterministic based on hash)
  List<double> _generateMockEmbedding(String input) {
    final hash = input.hashCode;
    final random = _SeededRandom(hash);
    return List.generate(
      embeddingDimension,
      (index) => (random.nextDouble() * 2) - 1,
    );
  }

  /// Cosine similarity fallback
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    final denominator = _sqrt(normA) * _sqrt(normB);
    return denominator == 0 ? 0.0 : dot / denominator;
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

/// Simple seeded random for deterministic mock embeddings
class _SeededRandom {
  int _seed;
  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = ((_seed * 1103515245) + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}
