import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;
import '../models/search_models.dart';

/// Service for Approximate Nearest Neighbor (ANN) search using IVF-PQ
///
/// This service uses pure Dart IVF-PQ (Inverted File with Product Quantization)
/// for fast and memory-efficient similarity search.
///
/// Key features:
/// - No native code required - works on all platforms
/// - Memory efficient via vector compression
/// - Fast search with configurable accuracy (numProbes)
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
/// final results = await annService.searchSimilar(queryEmbedding, k: 10);
/// ```
class ANNSearchService {
  /// The IVF-PQ index for fast similarity search
  ann.IvfPqAnnIndex? _ivfpqIndex;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Whether the index has been trained
  bool _isTrained = false;

  /// Pending embeddings to be added after training
  final List<Float32List> _pendingEmbeddings = [];
  final List<ImageItem> _pendingImages = [];

  /// Metadata for indexed images
  final Map<String, ImageItem> _imageMetadata = {};

  /// ID to index mapping
  final Map<int, String> _indexIdToImageId = {};
  final Map<String, int> _imageIdToIndexId = {};
  int _nextIndexId = 0;

  /// Stored embeddings for brute-force fallback and retraining
  final Map<String, Float32List> _imageEmbeddings = {};

  /// Number of top results to return by default
  static const int defaultTopK = 20;

  /// Similarity threshold (cosine similarity)
  /// Set to -1.0 to return ALL results regardless of similarity for debugging.
  static const double similarityThreshold = -1.0;

  /// Minimum vectors required for training (need enough for clustering)
  /// Must be >= numCentroidsPerSubquantizer (512) for stable training
  /// With 64 subquantizers × 512 centroids, we need substantial data
  static const int minVectorsForTraining = 600;

  /// IVF-PQ Configuration for SigLIP-768
  /// Optimized for 1000+ images with MAXIMUM accuracy
  ///
  /// Ultra-high accuracy configuration:
  /// - numClusters: 16 (fewer clusters = less quantization at cluster level)
  /// - numProbes: 16 = search ALL clusters (100%) for perfect recall
  /// - numSubquantizers: 64 (768 / 64 = 12 dims per subquantizer, minimal quantization)
  /// - numCentroidsPerSubquantizer: 512 = 9-bit quantization (higher precision)
  /// - trainingIterations: 50 = extensive training for optimal codebooks
  ///
  /// This configuration prioritizes accuracy over speed:
  /// - Fewer clusters with more probes = less cluster-level approximation
  /// - More subquantizers = finer-grained vector decomposition
  /// - Higher centroids = more precise quantization per subquantizer
  /// - More training = better converged codebooks
  static ann.IvfPqConfig get _config => ann.IvfPqConfig(
    dimension: 768,
    numClusters: 16,  // Fewer clusters for less coarse approximation
    numSubquantizers: 64,  // 768 / 64 = 12 dims per subquantizer (finer quantization)
    numCentroidsPerSubquantizer: 512,  // 9-bit = higher precision per subquantizer
    numProbes: 16,  // Search ALL 16 clusters (100% recall at cluster level)
    trainingIterations: 50,  // Extensive training for optimal convergence
  );

  /// Threshold for using brute-force instead of IVF-PQ
  /// IVF-PQ is now configured for high accuracy (searching all clusters)
  static const int bruteForceThreshold = 100;

  /// Whether the index is ready for searching
  bool get isReady => _isTrained && _ivfpqIndex != null && _ivfpqIndex!.isReady;

  /// Whether we're using IVF-PQ (always true when trained)
  bool get usingNativeHnsw => false; // We use pure Dart IVF-PQ now

  /// Initialize the ANN search service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('ANNSearchService: Initializing with pure Dart IVF-PQ...');

      _ivfpqIndex = ann.IvfPqAnnIndex(config: _config);

      _isInitialized = true;
      debugPrint('ANNSearchService: Initialized (awaiting training data)');
      return true;
    } catch (e) {
      debugPrint('ANNSearchService: Failed to initialize: $e');
      return false;
    }
  }

  /// Index an image with its embedding
  Future<void> indexImage(ImageItem image, List<double> embedding) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    // Convert to Float32List
    final float32Embedding = Float32List.fromList(embedding);

    // Store for potential retraining
    _imageEmbeddings[image.id] = float32Embedding;
    _imageMetadata[image.id] = image;

    // Assign index ID
    if (!_imageIdToIndexId.containsKey(image.id)) {
      _imageIdToIndexId[image.id] = _nextIndexId;
      _indexIdToImageId[_nextIndexId] = image.id;
      _nextIndexId++;
    }

    if (_isTrained && _ivfpqIndex != null && _ivfpqIndex!.isReady) {
      // Add directly to trained index
      final indexId = _imageIdToIndexId[image.id]!;
      await _ivfpqIndex!.addVector(float32Embedding, indexId);
      debugPrint('ANNSearchService: Added image ${image.id} to IVF-PQ index');
    } else {
      // Queue for batch training
      _pendingEmbeddings.add(float32Embedding);
      _pendingImages.add(image);
      debugPrint('ANNSearchService: Queued image ${image.id} for training');
    }
  }

  /// Index multiple images in batch
  Future<void> indexBatch(
    List<ImageItem> images,
    List<List<double>> embeddings,
  ) async {
    if (images.length != embeddings.length) {
      throw ArgumentError('Images and embeddings lists must have same length');
    }

    debugPrint('ANNSearchService: Indexing batch of ${images.length} images...');

    // Store all embeddings
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final float32Embedding = Float32List.fromList(embeddings[i]);

      _imageEmbeddings[image.id] = float32Embedding;
      _imageMetadata[image.id] = image;

      if (!_imageIdToIndexId.containsKey(image.id)) {
        _imageIdToIndexId[image.id] = _nextIndexId;
        _indexIdToImageId[_nextIndexId] = image.id;
        _nextIndexId++;
      }

      _pendingEmbeddings.add(float32Embedding);
      _pendingImages.add(image);
    }

    // Train if we have enough data
    debugPrint('ANNSearchService: Check training - isTrained: $_isTrained, pending: ${_pendingEmbeddings.length}, min: $minVectorsForTraining');
    if (!_isTrained && _pendingEmbeddings.length >= minVectorsForTraining) {
      debugPrint('ANNSearchService: Starting training with ${_pendingEmbeddings.length} vectors...');
      await _trainAndBuildIndex();
    } else if (_isTrained) {
      // Add new vectors to existing index
      for (var i = 0; i < _pendingImages.length; i++) {
        final image = _pendingImages[i];
        final indexId = _imageIdToIndexId[image.id]!;
        await _ivfpqIndex!.addVector(_pendingEmbeddings[i], indexId);
      }
      _pendingEmbeddings.clear();
      _pendingImages.clear();
    }

    debugPrint('ANNSearchService: Indexed ${images.length} images (trained: $_isTrained)');
  }

  /// Train the IVF-PQ index and add all pending vectors
  Future<void> _trainAndBuildIndex() async {
    if (_pendingEmbeddings.isEmpty) {
      debugPrint('ANNSearchService: No embeddings to train on');
      return;
    }

    debugPrint('ANNSearchService: Training IVF-PQ on ${_pendingEmbeddings.length} vectors...');
    final stopwatch = Stopwatch()..start();

    try {
      // Train the index
      await _ivfpqIndex!.train(_pendingEmbeddings);

      // Add all vectors
      final ids = _pendingImages.map((img) => _imageIdToIndexId[img.id]!).toList();
      await _ivfpqIndex!.addVectors(_pendingEmbeddings, ids);

      _isTrained = true;
      _pendingEmbeddings.clear();
      _pendingImages.clear();

      stopwatch.stop();
      debugPrint(
        'ANNSearchService: IVF-PQ trained and built in ${stopwatch.elapsedMilliseconds}ms '
        '(${_ivfpqIndex!.size} vectors)',
      );

      // Print statistics
      final stats = _ivfpqIndex!.getStatistics();
      debugPrint('ANNSearchService: IVF-PQ stats: $stats');
    } catch (e) {
      debugPrint('ANNSearchService: Training failed: $e');
      debugPrint('ANNSearchService: Falling back to brute-force search');
    }
  }

  /// Search for similar images
  ///
  /// For small datasets (<500 images), uses brute-force for 100% accuracy.
  /// For larger datasets, uses IVF-PQ for faster approximate search.
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
      List<ImageItem> results;

      // For small datasets, brute-force is fast AND 100% accurate
      if (_imageEmbeddings.length <= bruteForceThreshold) {
        results = _bruteForceSearch(queryEmbedding, k, effectiveThreshold);
        debugPrint('ANNSearchService: Brute-force search (small dataset: ${_imageEmbeddings.length} images)');
      } else if (isReady) {
        // Use IVF-PQ for larger datasets
        final float32Query = Float32List.fromList(queryEmbedding);
        results = await _ivfpqSearch(float32Query, k, effectiveThreshold);
        debugPrint('ANNSearchService: IVF-PQ search completed');
      } else {
        // Fall back to brute-force if IVF-PQ not ready
        results = _bruteForceSearch(queryEmbedding, k, effectiveThreshold);
        debugPrint('ANNSearchService: Brute-force search (IVF-PQ not ready)');
      }

      stopwatch.stop();
      debugPrint(
        'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, '
        'found ${results.length} results',
      );

      return results;
    } catch (e) {
      debugPrint('ANNSearchService: Search failed: $e');
      // Fall back to brute force on error
      return _bruteForceSearch(queryEmbedding, k, effectiveThreshold);
    }
  }

  /// Test IVF-PQ accuracy by comparing with brute-force (ground truth)
  ///
  /// Returns recall@k: percentage of true top-k results found by IVF-PQ
  Future<Map<String, dynamic>> testAccuracy(List<double> queryEmbedding, {int k = 10}) async {
    if (!isReady || _imageEmbeddings.isEmpty) {
      return {'error': 'Index not ready or empty'};
    }

    final float32Query = Float32List.fromList(queryEmbedding);

    // Get brute-force results (ground truth)
    final bruteForceResults = _bruteForceSearch(queryEmbedding, k, -1.0);
    final bruteForceIds = bruteForceResults.map((img) => img.id).toSet();

    // Get IVF-PQ results
    final ivfpqResults = await _ivfpqSearch(float32Query, k, -1.0);
    final ivfpqIds = ivfpqResults.map((img) => img.id).toSet();

    // Calculate recall
    final correctMatches = bruteForceIds.intersection(ivfpqIds).length;
    final recall = correctMatches / k;

    debugPrint('ANNSearchService: Accuracy Test Results:');
    debugPrint('  Brute-force top-$k: ${bruteForceIds.toList()}');
    debugPrint('  IVF-PQ top-$k: ${ivfpqIds.toList()}');
    debugPrint('  Correct matches: $correctMatches/$k');
    debugPrint('  Recall@$k: ${(recall * 100).toStringAsFixed(1)}%');

    return {
      'k': k,
      'bruteForceResults': bruteForceIds.toList(),
      'ivfpqResults': ivfpqIds.toList(),
      'correctMatches': correctMatches,
      'recall': recall,
      'recallPercent': '${(recall * 100).toStringAsFixed(1)}%',
    };
  }

  /// Search using IVF-PQ index
  Future<List<ImageItem>> _ivfpqSearch(
    Float32List query,
    int k,
    double threshold,
  ) async {
    final searchResults = await _ivfpqIndex!.search(query, k);

    final results = <ImageItem>[];
    for (final result in searchResults) {
      final imageId = _indexIdToImageId[result.id];
      if (imageId != null && _imageMetadata.containsKey(imageId)) {
        // IVF-PQ returns L2 distance, convert to similarity for filtering
        // For normalized vectors: similarity ≈ 1 - distance/2
        final similarity = 1.0 - (result.distance / 2.0);

        if (threshold < 0 || similarity >= threshold) {
          results.add(_imageMetadata[imageId]!);
        }
      }
    }

    // Debug: print top results
    debugPrint('ANNSearchService: IVF-PQ top ${results.length} results:');
    for (var i = 0; i < results.length && i < 5; i++) {
      final result = searchResults[i];
      final imageId = _indexIdToImageId[result.id];
      debugPrint('  ${i + 1}. $imageId: distance=${result.distance.toStringAsFixed(4)}');
    }

    return results;
  }

  /// Get the total number of indexed images
  int get indexSize => _imageMetadata.length;

  /// Get IVF-PQ index size
  int get nativeIndexSize => _ivfpqIndex?.size ?? 0;

  /// Check if an image is indexed
  bool isIndexed(String imageId) => _imageMetadata.containsKey(imageId);

  /// Remove an image from the index
  void removeImage(String imageId) {
    _imageEmbeddings.remove(imageId);
    _imageMetadata.remove(imageId);
    // Note: IVF-PQ doesn't support removal, would need to rebuild
    debugPrint('ANNSearchService: Removed image $imageId from metadata');
  }

  /// Clear the entire index
  void clearIndex() {
    _imageEmbeddings.clear();
    _imageMetadata.clear();
    _indexIdToImageId.clear();
    _imageIdToIndexId.clear();
    _pendingEmbeddings.clear();
    _pendingImages.clear();
    _nextIndexId = 0;
    _isTrained = false;

    // Recreate index
    _ivfpqIndex?.dispose();
    _ivfpqIndex = ann.IvfPqAnnIndex(config: _config);

    debugPrint('ANNSearchService: Index cleared');
  }

  /// Get index statistics
  Map<String, dynamic> getIndexStats() {
    return {
      'totalImages': _imageMetadata.length,
      'totalEmbeddings': _imageEmbeddings.length,
      'ivfpqIndexSize': _ivfpqIndex?.size ?? 0,
      'isTrained': _isTrained,
      'isReady': isReady,
      'pendingVectors': _pendingEmbeddings.length,
      'dimensionality': _imageEmbeddings.isEmpty
          ? 0
          : _imageEmbeddings.values.first.length,
      'algorithm': 'IVF-PQ (Pure Dart)',
    };
  }

  /// Dispose of resources
  void dispose() {
    _ivfpqIndex?.dispose();
    _ivfpqIndex = null;
    clearIndex();
    _isInitialized = false;
    debugPrint('ANNSearchService: Disposed');
  }

  // ========== Alpha Testing Support ==========

  /// Search for similar images with similarity scores (for alpha testing)
  /// 
  /// This method returns results WITH similarity scores for evaluation.
  /// Use [forceBruteForce] = true for 100% accurate results (no approximation).
  Future<List<SearchResultWithScore>> searchSimilarWithScores(
    List<double> queryEmbedding, {
    int k = defaultTopK,
    double? threshold,
    bool forceBruteForce = false,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    final effectiveThreshold = threshold ?? similarityThreshold;
    final stopwatch = Stopwatch()..start();

    try {
      List<SearchResultWithScore> results;

      // Force brute-force for alpha testing (100% accuracy)
      if (forceBruteForce || _imageEmbeddings.length <= bruteForceThreshold || !isReady) {
        results = _bruteForceSearchWithScores(queryEmbedding, k, effectiveThreshold);
        debugPrint('ANNSearchService: Brute-force search with scores (${_imageEmbeddings.length} images)');
      } else {
        // Use IVF-PQ for larger datasets
        final float32Query = Float32List.fromList(queryEmbedding);
        results = await _ivfpqSearchWithScores(float32Query, k, effectiveThreshold);
        debugPrint('ANNSearchService: IVF-PQ search with scores completed');
      }

      stopwatch.stop();
      debugPrint(
        'ANNSearchService: Search with scores completed in ${stopwatch.elapsedMilliseconds}ms, '
        'found ${results.length} results',
      );

      return results;
    } catch (e) {
      debugPrint('ANNSearchService: Search with scores failed: $e');
      return _bruteForceSearchWithScores(queryEmbedding, k, effectiveThreshold);
    }
  }

  /// Brute force search returning results with similarity scores
  List<SearchResultWithScore> _bruteForceSearchWithScores(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) {
    debugPrint('ANNSearchService: Brute force search with scores over ${_imageEmbeddings.length} embeddings');

    if (_imageEmbeddings.isEmpty) {
      return [];
    }

    // Compute ALL similarities
    final allResults = <SearchResultWithScore>[];

    for (final entry in _imageEmbeddings.entries) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.value);
      final image = _imageMetadata[entry.key];
      if (image != null && (threshold < 0 || similarity >= threshold)) {
        allResults.add(SearchResultWithScore(image: image, similarity: similarity));
      }
    }

    // Sort by similarity (highest first)
    allResults.sort((a, b) => b.similarity.compareTo(a.similarity));

    // Print top 5 for debugging
    debugPrint('ANNSearchService: Top 5 with scores:');
    for (var i = 0; i < allResults.length && i < 5; i++) {
      final result = allResults[i];
      debugPrint('  ${i + 1}. ${result.image.id}: ${result.similarity.toStringAsFixed(4)}');
    }

    // Return top k results
    return allResults.take(k).toList();
  }

  /// IVF-PQ search returning results with similarity scores
  Future<List<SearchResultWithScore>> _ivfpqSearchWithScores(
    Float32List query,
    int k,
    double threshold,
  ) async {
    if (_ivfpqIndex == null || !_ivfpqIndex!.isReady) {
      return _bruteForceSearchWithScores(query.toList(), k, threshold);
    }

    // IVF-PQ returns approximate results with distances
    final searchResults = await _ivfpqIndex!.search(query, k);
    
    final results = <SearchResultWithScore>[];
    for (final result in searchResults) {
      final imageId = _indexIdToImageId[result.id];
      if (imageId == null) continue;
      
      final image = _imageMetadata[imageId];
      if (image == null) continue;

      // Convert distance to similarity (IVF-PQ uses L2 distance internally)
      // For normalized vectors: similarity ≈ 1 - distance^2 / 2
      final similarity = 1.0 - (result.distance * result.distance) / 2.0;
      
      if (threshold < 0 || similarity >= threshold) {
        results.add(SearchResultWithScore(image: image, similarity: similarity));
      }
    }

    return results;
  }

  // ========== Brute-Force Fallback ==========

  /// Brute force similarity search (used before training or as fallback)
  List<ImageItem> _bruteForceSearch(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) {
    debugPrint('ANNSearchService: Brute force search over ${_imageEmbeddings.length} embeddings');

    if (_imageEmbeddings.isEmpty) {
      return [];
    }

    // Compute ALL similarities
    final allSimilarities = <MapEntry<String, double>>[];

    for (final entry in _imageEmbeddings.entries) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.value);
      allSimilarities.add(MapEntry(entry.key, similarity));
    }

    // Sort all similarities (highest first)
    allSimilarities.sort((a, b) => b.value.compareTo(a.value));

    // Print top 5 similarities for debugging
    debugPrint('ANNSearchService: Top 5 similarities:');
    for (var i = 0; i < allSimilarities.length && i < 5; i++) {
      final entry = allSimilarities[i];
      final meta = _imageMetadata[entry.key];
      debugPrint('  ${i + 1}. ${entry.key}: ${entry.value.toStringAsFixed(4)} - ${meta?.path ?? "unknown"}');
    }

    // Return top k results
    final topK = allSimilarities.take(k);
    return topK.map((entry) => _imageMetadata[entry.key]!).toList();
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
