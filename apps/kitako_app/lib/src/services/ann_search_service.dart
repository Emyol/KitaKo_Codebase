import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';

/// Service for Approximate Nearest Neighbor (ANN) search
///
/// This service provides:
/// - Vector similarity search
/// - Index management
/// - K-nearest neighbors search
///
/// Example usage:
/// ```dart
/// final annService = ANNSearchService();
/// await annService.initialize();
/// final results = await annService.searchSimilar(queryEmbedding, k: 10);
/// ```
class ANNSearchService {
  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Index of image embeddings
  /// Maps image ID to its embedding vector
  final Map<String, List<double>> _imageEmbeddings = {};

  /// Metadata for indexed images
  /// Maps image ID to ImageItem
  final Map<String, ImageItem> _imageMetadata = {};

  /// Number of top results to return by default
  static const int defaultTopK = 10;

  /// Similarity threshold (0.0 to 1.0)
  static const double similarityThreshold = 0.5;

  /// Initialize the ANN search service
  ///
  /// Loads the search index and prepares for queries.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // TODO: Load ANN index from kitako_ann package
      // await annClient.loadIndex(indexPath);

      _isInitialized = true;
      debugPrint('ANNSearchService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('ANNSearchService: Failed to initialize: $e');
      return false;
    }
  }

  /// Index an image with its embedding
  ///
  /// Adds an image and its embedding to the search index.
  ///
  /// Parameters:
  /// - [image]: The image to index
  /// - [embedding]: The embedding vector for the image
  Future<void> indexImage(ImageItem image, List<double> embedding) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    _imageEmbeddings[image.id] = embedding;
    _imageMetadata[image.id] = image;

    debugPrint('ANNSearchService: Indexed image ${image.id}');
  }

  /// Index multiple images in batch
  ///
  /// More efficient than calling [indexImage] multiple times.
  ///
  /// Parameters:
  /// - [images]: List of images to index
  /// - [embeddings]: Corresponding embedding vectors
  Future<void> indexBatch(
    List<ImageItem> images,
    List<List<double>> embeddings,
  ) async {
    if (images.length != embeddings.length) {
      throw ArgumentError('Images and embeddings lists must have same length');
    }

    for (var i = 0; i < images.length; i++) {
      await indexImage(images[i], embeddings[i]);
    }

    debugPrint('ANNSearchService: Indexed ${images.length} images');
  }

  /// Search for similar images using ANN
  ///
  /// Finds the k-nearest neighbors to the query embedding.
  ///
  /// Parameters:
  /// - [queryEmbedding]: The query embedding vector
  /// - [k]: Number of top results to return (default: 10)
  /// - [threshold]: Minimum similarity score (0.0 to 1.0)
  ///
  /// Returns a list of matching images sorted by similarity
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

    try {
      // TODO: Use actual ANN search from kitako_ann
      // final results = await annClient.search(queryEmbedding, k: k);

      // For now, use brute force similarity search (mock)
      final results = _bruteForceSearch(queryEmbedding, k, effectiveThreshold);

      stopwatch.stop();
      debugPrint(
        'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, found ${results.length} results',
      );

      return results;
    } catch (e) {
      debugPrint('ANNSearchService: Search failed: $e');
      rethrow;
    }
  }

  /// Get the total number of indexed images
  int get indexSize => _imageMetadata.length;

  /// Check if an image is indexed
  bool isIndexed(String imageId) => _imageMetadata.containsKey(imageId);

  /// Remove an image from the index
  void removeImage(String imageId) {
    _imageEmbeddings.remove(imageId);
    _imageMetadata.remove(imageId);
    debugPrint('ANNSearchService: Removed image $imageId from index');
  }

  /// Clear the entire index
  void clearIndex() {
    _imageEmbeddings.clear();
    _imageMetadata.clear();
    debugPrint('ANNSearchService: Index cleared');
  }

  /// Get index statistics
  Map<String, dynamic> getIndexStats() {
    return {
      'totalImages': _imageMetadata.length,
      'totalEmbeddings': _imageEmbeddings.length,
      'dimensionality': _imageEmbeddings.isEmpty
          ? 0
          : _imageEmbeddings.values.first.length,
    };
  }

  /// Dispose of resources
  void dispose() {
    clearIndex();
    _isInitialized = false;
    debugPrint('ANNSearchService: Disposed');
  }

  // ========== Helper Methods ==========

  /// Brute force similarity search (for mock implementation)
  ///
  /// Computes cosine similarity between query and all indexed embeddings.
  /// Returns top-k results above threshold.
  List<ImageItem> _bruteForceSearch(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) {
    final similarities = <String, double>{};

    // Compute similarity for each indexed image
    for (final entry in _imageEmbeddings.entries) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.value);
      if (similarity >= threshold) {
        similarities[entry.key] = similarity;
      }
    }

    // Sort by similarity (descending) and take top-k
    final sortedIds = similarities.keys.toList()
      ..sort((a, b) => similarities[b]!.compareTo(similarities[a]!));

    final topK = sortedIds.take(k);

    return topK.map((id) => _imageMetadata[id]!).toList();
  }

  /// Calculate cosine similarity between two vectors
  ///
  /// Returns a value between -1 and 1, where:
  /// - 1 means identical
  /// - 0 means orthogonal
  /// - -1 means opposite
  double _cosineSimilarity(List<double> a, List<double> b) {
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
