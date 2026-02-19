import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';

/// Brute-force similarity search service for image embeddings.
///
/// Computes exact cosine similarity over all stored embeddings.
/// This gives 100% recall and is fast enough for datasets up to ~10K images
/// (751 images searches in ~2ms on a mobile device).
///
/// Usage:
/// ```dart
/// final annService = ANNSearchService();
/// await annService.initialize();
///
/// // Index images with embeddings
/// await annService.indexBatch(images, embeddings);
///
/// // Search for similar images
/// final results = await annService.searchSimilarWithScores(queryEmbedding, k: 10);
/// ```
class ANNSearchService {
  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Image ID → embedding vector
  final Map<String, Float32List> _imageEmbeddings = {};

  /// Image ID → image metadata
  final Map<String, ImageItem> _imageMetadata = {};

  /// Number of top results to return by default
  static const int defaultTopK = 20;

  /// Similarity threshold (cosine similarity)
  /// Set to -1.0 to return ALL results regardless of similarity for debugging.
  static const double similarityThreshold = -1.0;

  /// Whether the index has any embeddings and is ready for search
  bool get isReady => _isInitialized && _imageEmbeddings.isNotEmpty;

  /// Initialize the search service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = true;
    debugPrint('ANNSearchService: Initialized (brute-force search)');
    return true;
  }

  /// Index an image with its embedding
  Future<void> indexImage(ImageItem image, List<double> embedding) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    _imageEmbeddings[image.id] = Float32List.fromList(embedding);
    _imageMetadata[image.id] = image;
  }

  /// Index multiple images in batch
  Future<void> indexBatch(
    List<ImageItem> images,
    List<List<double>> embeddings,
  ) async {
    if (images.length != embeddings.length) {
      throw ArgumentError('Images and embeddings lists must have same length');
    }

    for (var i = 0; i < images.length; i++) {
      _imageEmbeddings[images[i].id] = Float32List.fromList(embeddings[i]);
      _imageMetadata[images[i].id] = images[i];
    }

    debugPrint('ANNSearchService: Indexed ${images.length} images '
        '(total: ${_imageEmbeddings.length})');
  }

  // ========== Search ==========

  /// Search for similar images (returns ImageItem list without scores)
  Future<List<ImageItem>> searchSimilar(
    List<double> queryEmbedding, {
    int k = defaultTopK,
    double? threshold,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    final effectiveThreshold = threshold ?? similarityThreshold;
    final stopwatch = Stopwatch()..start();

    final results = _bruteForceSearch(queryEmbedding, k, effectiveThreshold);

    stopwatch.stop();
    debugPrint(
      'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, '
      'found ${results.length} results (${_imageEmbeddings.length} total)',
    );

    return results;
  }

  /// Search for similar images with similarity scores
  Future<List<SearchResultWithScore>> searchSimilarWithScores(
    List<double> queryEmbedding, {
    int k = defaultTopK,
    double? threshold,
    bool forceBruteForce = false, // kept for API compat, always brute-force
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    final effectiveThreshold = threshold ?? similarityThreshold;
    final stopwatch = Stopwatch()..start();

    final results = _bruteForceSearchWithScores(
      queryEmbedding, k, effectiveThreshold,
    );

    stopwatch.stop();
    debugPrint(
      'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, '
      'found ${results.length} results (${_imageEmbeddings.length} total)',
    );

    return results;
  }

  // ========== Index Management ==========

  /// Get the total number of indexed images
  int get indexSize => _imageMetadata.length;

  /// Check if an image is indexed
  bool isIndexed(String imageId) => _imageMetadata.containsKey(imageId);

  /// Get all indexed images
  List<ImageItem> getAllIndexedImages() => _imageMetadata.values.toList();

  /// Remove an image from the index
  void removeImage(String imageId) {
    _imageEmbeddings.remove(imageId);
    _imageMetadata.remove(imageId);
  }

  /// Clear the entire index
  void clearIndex() {
    _imageEmbeddings.clear();
    _imageMetadata.clear();
    debugPrint('ANNSearchService: Index cleared');
  }

  // ========== Data Export (for storage layer) ==========

  /// Read-only access to stored embeddings.
  Map<String, Float32List> get imageEmbeddings =>
      Map.unmodifiable(_imageEmbeddings);

  /// Read-only access to image metadata.
  Map<String, ImageItem> get imageMetadata =>
      Map.unmodifiable(_imageMetadata);

  // ========== Cache Restore ==========

  /// Restore internal state from cached embeddings + metadata.
  ///
  /// This populates the in-memory maps without running any ONNX inference.
  void restoreFromCache(
    Map<String, Float32List> embeddings,
    Map<String, ImageItem> metadata,
  ) {
    for (final entry in embeddings.entries) {
      _imageEmbeddings[entry.key] = entry.value;
      if (metadata.containsKey(entry.key)) {
        _imageMetadata[entry.key] = metadata[entry.key]!;
      }
    }

    debugPrint('ANNSearchService: Restored ${embeddings.length} cached embeddings');
  }

  // ========== Statistics ==========

  /// Get index statistics
  Map<String, dynamic> getIndexStats() {
    return {
      'totalImages': _imageMetadata.length,
      'totalEmbeddings': _imageEmbeddings.length,
      'isReady': isReady,
      'dimensionality': _imageEmbeddings.isEmpty
          ? 0
          : _imageEmbeddings.values.first.length,
      'algorithm': 'Brute-Force (Cosine Similarity)',
    };
  }

  /// Dispose of resources
  void dispose() {
    clearIndex();
    _isInitialized = false;
    debugPrint('ANNSearchService: Disposed');
  }

  // ========== Private Search Methods ==========

  /// Brute force search returning ImageItem list
  List<ImageItem> _bruteForceSearch(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) {
    if (_imageEmbeddings.isEmpty) return [];

    final allSimilarities = <MapEntry<String, double>>[];

    for (final entry in _imageEmbeddings.entries) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.value);
      if (threshold < 0 || similarity >= threshold) {
        allSimilarities.add(MapEntry(entry.key, similarity));
      }
    }

    allSimilarities.sort((a, b) => b.value.compareTo(a.value));

    return allSimilarities
        .take(k)
        .map((entry) => _imageMetadata[entry.key]!)
        .toList();
  }

  /// Brute force search returning results with similarity scores
  List<SearchResultWithScore> _bruteForceSearchWithScores(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) {
    if (_imageEmbeddings.isEmpty) return [];

    final allResults = <SearchResultWithScore>[];

    for (final entry in _imageEmbeddings.entries) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.value);
      final image = _imageMetadata[entry.key];
      if (image != null && (threshold < 0 || similarity >= threshold)) {
        allResults.add(SearchResultWithScore(image: image, similarity: similarity));
      }
    }

    allResults.sort((a, b) => b.similarity.compareTo(a.similarity));

    // Print top 5 for debugging
    debugPrint('ANNSearchService: Top 5 with scores:');
    for (var i = 0; i < allResults.length && i < 5; i++) {
      final result = allResults[i];
      debugPrint('  ${i + 1}. ${result.image.id}: ${result.similarity.toStringAsFixed(4)}');
    }

    return allResults.take(k).toList();
  }

  /// Calculate cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<num> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have same length');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = math.sqrt(normA);
    normB = math.sqrt(normB);

    if (normA == 0 || normB == 0) return 0.0;

    return dotProduct / (normA * normB);
  }
}
