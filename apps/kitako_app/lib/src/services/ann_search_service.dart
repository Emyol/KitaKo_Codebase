import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;
import '../models/search_models.dart';

/// Service for image similarity search.
///
/// Automatically selects the best algorithm based on dataset size:
/// - **Brute-force** (always used for ≤ [bruteForceThreshold] images, or before
///   enough data exists to train IVF-PQ). Gives 100% recall.
/// - **IVF-PQ** (pure Dart, no native FFI) once ≥ [minVectorsForTraining]
///   images have been indexed and training completes. Scales to large datasets.
///
/// The IVF-PQ configuration targets maximum accuracy for SigLIP-768 embeddings:
/// 16 clusters all probed, 64 subquantizers, 512 centroids/subquantizer.
///
/// Usage:
/// ```dart
/// final annService = ANNSearchService();
/// await annService.initialize();
///
/// await annService.indexBatch(images, embeddings);
///
/// final results = await annService.searchSimilarWithScores(queryEmbedding, k: 10);
/// ```
class ANNSearchService {
  // ---- State ----

  bool _isInitialized = false;

  /// Image ID → embedding vector (Float32, kept for brute-force + cache export)
  final Map<String, Float32List> _imageEmbeddings = {};

  /// Image ID → image metadata
  final Map<String, ImageItem> _imageMetadata = {};

  // ---- IVF-PQ index ----

  ann.IvfPqAnnIndex? _ivfpqIndex;
  bool _isTrained = false;

  /// Embeddings queued before the training threshold is reached
  final List<Float32List> _pendingEmbeddings = [];
  final List<ImageItem> _pendingImages = [];

  /// Integer ID ↔ image-ID string mappings required by kitako_ann
  final Map<int, String> _indexIdToImageId = {};
  final Map<String, int> _imageIdToIndexId = {};
  int _nextIndexId = 0;

  // ---- Constants ----

  /// Default number of results to return
  static const int defaultTopK = 20;

  /// Cosine-similarity threshold. Set to -1.0 to return all results (debug).
  static const double similarityThreshold = -1.0;

  /// Minimum indexed vectors required to train IVF-PQ.
  /// Must be ≥ numClusters × numCentroidsPerSubquantizer for stable k-means.
  static const int minVectorsForTraining = 600;

  /// Datasets at or below this size always use brute-force (faster + 100% recall).
  static const int bruteForceThreshold = 100;

  /// IVF-PQ config tuned for SigLIP-768 — high accuracy, all clusters probed.
  ///
  /// - numClusters 16, numProbes 16 → 100% cluster recall
  /// - numSubquantizers 64 → 12 dims/subquantizer (fine-grained)
  /// - numCentroidsPerSubquantizer 512 → ~9-bit precision
  /// - trainingIterations 50 → well-converged codebooks
  static ann.IvfPqConfig get _config => ann.IvfPqConfig(
        dimension: 768,
        numClusters: 16,
        numSubquantizers: 64,
        numCentroidsPerSubquantizer: 512,
        numProbes: 16,
        trainingIterations: 50,
      );

  // ---- Derived state ----

  /// True when the IVF-PQ index is trained and loaded.
  bool get isIvfpqReady =>
      _isTrained && _ivfpqIndex != null && _ivfpqIndex!.isReady;

  /// True when any images are indexed and the service is initialised.
  bool get isReady => _isInitialized && _imageEmbeddings.isNotEmpty;

  // ========== Initialization ==========

  /// Initialise the search service. Must be called before any other method.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    _ivfpqIndex = ann.IvfPqAnnIndex(config: _config);
    _isInitialized = true;
    debugPrint('ANNSearchService: Initialized (IVF-PQ + brute-force fallback)');
    return true;
  }

  // ========== Indexing ==========

  /// Index a single image with its embedding.
  Future<void> indexImage(ImageItem image, List<double> embedding) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    final float32 = Float32List.fromList(embedding);
    _imageEmbeddings[image.id] = float32;
    _imageMetadata[image.id] = image;

    if (!_imageIdToIndexId.containsKey(image.id)) {
      _imageIdToIndexId[image.id] = _nextIndexId;
      _indexIdToImageId[_nextIndexId] = image.id;
      _nextIndexId++;
    }

    if (isIvfpqReady) {
      await _ivfpqIndex!.addVector(float32, _imageIdToIndexId[image.id]!);
      debugPrint('ANNSearchService: Added image ${image.id} to IVF-PQ index');
    } else {
      _pendingEmbeddings.add(float32);
      _pendingImages.add(image);
      debugPrint('ANNSearchService: Queued image ${image.id} for training');
    }
  }

  /// Index multiple images in batch.
  ///
  /// Triggers IVF-PQ training automatically once [minVectorsForTraining] is
  /// reached. Until then (or for small datasets) brute-force is used.
  Future<void> indexBatch(
    List<ImageItem> images,
    List<List<double>> embeddings,
  ) async {
    if (images.length != embeddings.length) {
      throw ArgumentError('Images and embeddings lists must have same length');
    }

    debugPrint('ANNSearchService: Indexing batch of ${images.length} images...');

    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final float32 = Float32List.fromList(embeddings[i]);

      _imageEmbeddings[image.id] = float32;
      _imageMetadata[image.id] = image;

      if (!_imageIdToIndexId.containsKey(image.id)) {
        _imageIdToIndexId[image.id] = _nextIndexId;
        _indexIdToImageId[_nextIndexId] = image.id;
        _nextIndexId++;
      }

      _pendingEmbeddings.add(float32);
      _pendingImages.add(image);
    }

    if (!_isTrained && _pendingEmbeddings.length >= minVectorsForTraining) {
      debugPrint(
        'ANNSearchService: Starting IVF-PQ training with '
        '${_pendingEmbeddings.length} vectors...',
      );
      await _trainAndBuildIndex();
    } else if (_isTrained && _pendingEmbeddings.isNotEmpty) {
      // Add newly queued vectors to the already-trained index
      final ids =
          _pendingImages.map((img) => _imageIdToIndexId[img.id]!).toList();
      await _ivfpqIndex!.addVectors(_pendingEmbeddings, ids);
      _pendingEmbeddings.clear();
      _pendingImages.clear();
    }

    debugPrint(
      'ANNSearchService: Indexed ${images.length} images '
      '(total: ${_imageEmbeddings.length}, ivfpq trained: $_isTrained)',
    );
  }

  /// Train IVF-PQ on all pending embeddings and add them to the index.
  Future<void> _trainAndBuildIndex() async {
    if (_pendingEmbeddings.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    try {
      await _ivfpqIndex!.train(_pendingEmbeddings);

      final ids =
          _pendingImages.map((img) => _imageIdToIndexId[img.id]!).toList();
      await _ivfpqIndex!.addVectors(_pendingEmbeddings, ids);

      _isTrained = true;
      _pendingEmbeddings.clear();
      _pendingImages.clear();

      stopwatch.stop();
      debugPrint(
        'ANNSearchService: IVF-PQ trained in ${stopwatch.elapsedMilliseconds}ms '
        '(${_ivfpqIndex!.size} vectors)',
      );
      debugPrint(
          'ANNSearchService: IVF-PQ stats: ${_ivfpqIndex!.getStatistics()}');
    } catch (e) {
      debugPrint(
          'ANNSearchService: IVF-PQ training failed: $e — using brute-force');
    }
  }

  // ========== Search ==========

  /// Search for similar images, returning [ImageItem] list without scores.
  ///
  /// Uses brute-force for small/untrained datasets and IVF-PQ otherwise.
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

    List<ImageItem> results;
    if (_imageEmbeddings.length <= bruteForceThreshold || !isIvfpqReady) {
      results = _bruteForceSearch(queryEmbedding, k, effectiveThreshold);
      debugPrint(
          'ANNSearchService: Brute-force search (${_imageEmbeddings.length} images)');
    } else {
      final float32Query = Float32List.fromList(queryEmbedding);
      results = await _ivfpqSearch(float32Query, k, effectiveThreshold);
      debugPrint('ANNSearchService: IVF-PQ search completed');
    }

    stopwatch.stop();
    debugPrint(
      'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, '
      'found ${results.length} results (${_imageEmbeddings.length} total)',
    );

    return results;
  }

  /// Search for similar images, returning results with cosine similarity scores.
  ///
  /// Pass [forceBruteForce] = true to bypass IVF-PQ (useful for ground-truth
  /// evaluation or small evaluation sets).
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

    List<SearchResultWithScore> results;
    if (forceBruteForce ||
        _imageEmbeddings.length <= bruteForceThreshold ||
        !isIvfpqReady) {
      results =
          _bruteForceSearchWithScores(queryEmbedding, k, effectiveThreshold);
      debugPrint(
          'ANNSearchService: Brute-force search with scores (${_imageEmbeddings.length} images)');
    } else {
      final float32Query = Float32List.fromList(queryEmbedding);
      results =
          await _ivfpqSearchWithScores(float32Query, k, effectiveThreshold);
      debugPrint('ANNSearchService: IVF-PQ search with scores completed');
    }

    stopwatch.stop();
    debugPrint(
      'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, '
      'found ${results.length} results (${_imageEmbeddings.length} total)',
    );

    return results;
  }

  /// Measure IVF-PQ accuracy against brute-force ground truth.
  ///
  /// Returns recall@k: the fraction of true top-k results also returned by
  /// IVF-PQ. Requires the index to be trained.
  Future<Map<String, dynamic>> testAccuracy(
    List<double> queryEmbedding, {
    int k = 10,
  }) async {
    if (!isIvfpqReady || _imageEmbeddings.isEmpty) {
      return {'error': 'IVF-PQ index not ready or empty'};
    }

    final float32Query = Float32List.fromList(queryEmbedding);

    final bruteForceIds =
        _bruteForceSearch(queryEmbedding, k, -1.0).map((img) => img.id).toSet();
    final ivfpqIds =
        (await _ivfpqSearch(float32Query, k, -1.0)).map((img) => img.id).toSet();

    final correctMatches = bruteForceIds.intersection(ivfpqIds).length;
    final recall = correctMatches / k;

    debugPrint(
        'ANNSearchService: Accuracy — recall@$k: ${(recall * 100).toStringAsFixed(1)}%');

    return {
      'k': k,
      'bruteForceResults': bruteForceIds.toList(),
      'ivfpqResults': ivfpqIds.toList(),
      'correctMatches': correctMatches,
      'recall': recall,
      'recallPercent': '${(recall * 100).toStringAsFixed(1)}%',
    };
  }

  // ========== IVF-PQ private search ==========

  Future<List<ImageItem>> _ivfpqSearch(
    Float32List query,
    int k,
    double threshold,
  ) async {
    final searchResults = await _ivfpqIndex!.search(query, k);
    final results = <ImageItem>[];

    for (final result in searchResults) {
      final imageId = _indexIdToImageId[result.id];
      if (imageId == null) continue;

      // IVF-PQ returns L2 distance. For unit-normalised SigLIP vectors:
      //   cosine_similarity ≈ 1 − L2_distance / 2
      final similarity = 1.0 - (result.distance / 2.0);
      if (threshold < 0 || similarity >= threshold) {
        results.add(_imageMetadata[imageId]!);
      }
    }

    return results;
  }

  Future<List<SearchResultWithScore>> _ivfpqSearchWithScores(
    Float32List query,
    int k,
    double threshold,
  ) async {
    final searchResults = await _ivfpqIndex!.search(query, k);
    final results = <SearchResultWithScore>[];

    for (final result in searchResults) {
      final imageId = _indexIdToImageId[result.id];
      if (imageId == null) continue;

      final image = _imageMetadata[imageId];
      if (image == null) continue;

      // For unit-normalised vectors: similarity ≈ 1 − dist² / 2
      final similarity = 1.0 - (result.distance * result.distance) / 2.0;
      if (threshold < 0 || similarity >= threshold) {
        results.add(SearchResultWithScore(image: image, similarity: similarity));
      }
    }

    return results;
  }

  // ========== Index Management ==========

  /// Total number of indexed images.
  int get indexSize => _imageMetadata.length;

  /// Whether a specific image is indexed.
  bool isIndexed(String imageId) => _imageMetadata.containsKey(imageId);

  /// All currently indexed images.
  List<ImageItem> getAllIndexedImages() => _imageMetadata.values.toList();

  /// Remove an image from in-memory metadata.
  ///
  /// Note: IVF-PQ does not support incremental removal; a full rebuild is
  /// required to physically remove a vector from the index.
  void removeImage(String imageId) {
    _imageEmbeddings.remove(imageId);
    _imageMetadata.remove(imageId);
    debugPrint('ANNSearchService: Removed image $imageId from metadata');
  }

  /// Clear all indexed data and reset the IVF-PQ index.
  void clearIndex() {
    _imageEmbeddings.clear();
    _imageMetadata.clear();
    _indexIdToImageId.clear();
    _imageIdToIndexId.clear();
    _pendingEmbeddings.clear();
    _pendingImages.clear();
    _nextIndexId = 0;
    _isTrained = false;

    _ivfpqIndex?.dispose();
    _ivfpqIndex = ann.IvfPqAnnIndex(config: _config);

    debugPrint('ANNSearchService: Index cleared');
  }

  // ========== Data Export (for storage layer) ==========

  /// Read-only view of stored embeddings (for persistence / cache export).
  Map<String, Float32List> get imageEmbeddings =>
      Map.unmodifiable(_imageEmbeddings);

  /// Read-only view of image metadata (for persistence / cache export).
  Map<String, ImageItem> get imageMetadata =>
      Map.unmodifiable(_imageMetadata);

  // ========== Cache Restore ==========

  /// Restore internal state from previously cached embeddings and metadata.
  ///
  /// Populates in-memory maps without running ONNX inference. Restored
  /// embeddings are queued for IVF-PQ training so the next [indexBatch] or
  /// explicit training call can promote them to the approximate index.
  void restoreFromCache(
    Map<String, Float32List> embeddings,
    Map<String, ImageItem> metadata,
  ) {
    for (final entry in embeddings.entries) {
      _imageEmbeddings[entry.key] = entry.value;
      final image = metadata[entry.key];
      if (image == null) continue;

      _imageMetadata[entry.key] = image;

      if (!_imageIdToIndexId.containsKey(entry.key)) {
        _imageIdToIndexId[entry.key] = _nextIndexId;
        _indexIdToImageId[_nextIndexId] = entry.key;
        _nextIndexId++;
      }

      _pendingEmbeddings.add(entry.value);
      _pendingImages.add(image);
    }

    debugPrint(
      'ANNSearchService: Restored ${embeddings.length} cached embeddings '
      '(pending IVF-PQ training: ${_pendingEmbeddings.length})',
    );
  }

  // ========== Statistics ==========

  /// Diagnostic statistics for the current index state.
  Map<String, dynamic> getIndexStats() {
    return {
      'totalImages': _imageMetadata.length,
      'totalEmbeddings': _imageEmbeddings.length,
      'isReady': isReady,
      'ivfpqReady': isIvfpqReady,
      'isTrained': _isTrained,
      'ivfpqIndexSize': _ivfpqIndex?.size ?? 0,
      'pendingVectors': _pendingEmbeddings.length,
      'dimensionality': _imageEmbeddings.isEmpty
          ? 0
          : _imageEmbeddings.values.first.length,
      'algorithm':
          isIvfpqReady ? 'IVF-PQ (Pure Dart)' : 'Brute-Force (Cosine)',
    };
  }

  /// Dispose of all resources.
  void dispose() {
    _ivfpqIndex?.dispose();
    _ivfpqIndex = null;
    clearIndex();
    _isInitialized = false;
    debugPrint('ANNSearchService: Disposed');
  }

  // ========== Brute-Force (private) ==========

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

    debugPrint('ANNSearchService: Top 5 with scores:');
    for (var i = 0; i < allResults.length && i < 5; i++) {
      final r = allResults[i];
      debugPrint(
          '  ${i + 1}. ${r.image.id}: ${r.similarity.toStringAsFixed(4)}');
    }

    return allResults.take(k).toList();
  }

  /// Cosine similarity between a query vector and a stored [Float32List].
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
