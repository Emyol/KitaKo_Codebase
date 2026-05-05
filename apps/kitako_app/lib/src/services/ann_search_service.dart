import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;

import '../models/search_models.dart';

/// Unified ANN search service supporting HNSW, IVF-PQ, and brute-force search.
///
/// Algorithm selection (in priority order):
///
/// 1. **HNSW** (via native FFI / `kitako_ffi`) — no training required,
///    supports incremental additions, fast graph-based search.
///    Preferred when the native library is available.
///
/// 2. **IVF-PQ** (pure Dart) — requires training with ≥300 vectors,
///    memory-efficient via product quantization.
///    Used when HNSW FFI is unavailable or on platforms without native libs.
///
/// 3. **Brute-force** — exact cosine similarity over all stored embeddings.
///    Always available as fallback for small datasets or when an ANN index
///    is not yet ready.
///
/// Usage:
/// ```dart
/// final annService = ANNSearchService();
/// await annService.initialize();
///
/// await annService.indexBatch(images, embeddings);
/// final results = await annService.searchSimilarWithScores(query, k: 20);
/// ```
class ANNSearchService {
  // ── Active ANN indices ───────────────────────────────────────────────────

  ann.HnswAnnIndex? _hnswIndex;
  ann.IvfPqAnnIndex? _ivfpqIndex;

  /// Which algorithm is active (null = brute-force only).
  ann.AnnAlgorithm? _activeAlgorithm;

  // ── State ────────────────────────────────────────────────────────────────

  bool _isInitialized = false;

  /// True once `_hnswIndex.initialize()` has been called successfully.
  bool _hnswInitialized = false;

  /// True once IVF-PQ has been trained and vectors added.
  bool _ivfpqTrained = false;

  /// IVF-PQ: accumulate vectors here until we have enough for training.
  final List<Float32List> _pendingEmbeddings = [];
  final List<ImageItem> _pendingImages = [];

  // ── Embeddings store (brute-force + cache persistence) ───────────────────

  /// imageId → embedding (used for brute-force and ANN index rebuild).
  final Map<String, Float32List> _imageEmbeddings = {};

  /// imageId → ImageItem metadata.
  final Map<String, ImageItem> _imageMetadata = {};

  // ── ID mapping (int IDs for the ANN index ↔ string image IDs) ───────────

  final Map<int, String> _indexIdToImageId = {};
  final Map<String, int> _imageIdToIndexId = {};
  int _nextIndexId = 0;

  // ── User preference ──────────────────────────────────────────────────────

  /// Override the auto-selected algorithm.
  ///
  /// - `null` (default): use whichever algorithm was chosen during [initialize]
  /// - `AnnAlgorithm.hnsw`: prefer HNSW even if IVF-PQ was auto-selected
  /// - `AnnAlgorithm.ivfpq`: prefer IVF-PQ even if HNSW was auto-selected
  ///
  /// If the preferred algorithm is not ready the service transparently falls
  /// back through the priority chain: HNSW → IVF-PQ → brute-force.
  ann.AnnAlgorithm? preferredAlgorithm;

  /// When `true`, always use exact brute-force cosine similarity regardless
  /// of dataset size or [preferredAlgorithm]. Used by alpha testing.
  bool forceBruteForceMode = false;

  /// Convenience setter for callers that don't import `kitako_ann` directly.
  ///
  /// [useHnsw] = `true`  → HNSW (Accuracy mode)
  /// [useHnsw] = `false` → IVF-PQ (Performance mode)
  void setPreferHnsw(bool useHnsw) {
    preferredAlgorithm =
        useHnsw ? ann.AnnAlgorithm.hnsw : ann.AnnAlgorithm.ivfpq;
  }

  /// Whether the user preference is HNSW (`true`), IVF-PQ (`false`), or auto (`null`).
  bool? get preferHnsw {
    if (preferredAlgorithm == null) return null;
    return preferredAlgorithm == ann.AnnAlgorithm.hnsw;
  }

  /// Trains and populates the IVF-PQ index from currently stored embeddings.
  ///
  /// Safe to call multiple times — returns immediately if already trained.
  /// When HNSW was the auto-selected algorithm, [_ivfpqIndex] may be null;
  /// this method creates and trains it on demand using [_imageEmbeddings].
  ///
  /// Returns `true` if IVF-PQ is now ready to serve queries.
  /// Returns `false` if there aren't enough vectors to train (< [minVectorsForTraining]).
  Future<bool> ensureIvfpqReady() async {
    if (_ivfpqTrained && _ivfpqIndex != null && _ivfpqIndex!.isReady) {
      return true;
    }

    final count = _imageEmbeddings.length;
    if (count < minVectorsForTraining) {
      debugPrint(
        'ANNSearchService: Cannot train IVF-PQ — '
        '$count vectors available, $minVectorsForTraining needed',
      );
      return false;
    }

    // Always recreate with adaptive config sized for current dataset.
    final adaptiveConfig = _ivfpqConfigFor(count);
    _ivfpqIndex?.dispose();
    _ivfpqIndex = ann.IvfPqAnnIndex(config: adaptiveConfig);
    _ivfpqTrained = false;
    _activeIvfpqConfig = adaptiveConfig;

    debugPrint('ANNSearchService: Training IVF-PQ on $count vectors...');
    final sw = Stopwatch()..start();

    try {
      final vectors = _imageEmbeddings.values.toList();
      final ids = _imageEmbeddings.keys
          .map((imageId) => _imageIdToIndexId[imageId]!)
          .toList();

      await _ivfpqIndex!.train(vectors);
      await _ivfpqIndex!.addVectors(vectors, ids);

      _ivfpqTrained = true;
      sw.stop();
      debugPrint(
        'ANNSearchService: IVF-PQ ready — '
        '${_ivfpqIndex!.size} vectors indexed in ${sw.elapsedMilliseconds}ms',
      );
      debugPrint(
        'ANNSearchService: IVF-PQ stats: ${_ivfpqIndex!.getStatistics()}',
      );
      return true;
    } catch (e) {
      sw.stop();
      debugPrint('ANNSearchService: IVF-PQ training failed: $e');
      return false;
    }
  }

  // ── Configuration ────────────────────────────────────────────────────────

  /// Default number of results to return.
  static const int defaultTopK = 20;

  /// Similarity threshold: negative means return everything.
  static const double similarityThreshold = -1.0;

  /// Minimum vectors required for IVF-PQ training.
  /// Adaptive config ensures ~10 samples/centroid, so 50 is sufficient.
  static const int minVectorsForTraining = 50;

  /// Below this dataset size always use brute-force (100% accurate and fast).
  static const int bruteForceThreshold = 100;

  /// HNSW maximum index capacity.
  static const int _maxHnswElements = 50000;

  /// HNSW configuration for SigLIP-768 embeddings.
  static ann.HnswConfig get _hnswConfig => ann.HnswConfig(
    dimension: 768,
    metric: ann.DistanceMetric.innerProduct,
    m: 16,
    efConstruction: 200,
    efSearch: 50,
    maxElements: _maxHnswElements,
  );

  /// IVF-PQ configuration adaptive to dataset size [n].
  ///
  /// Rule of thumb: need ~10 training samples per PQ centroid for a usable
  /// codebook. With a fixed 256-centroid config and <2560 images, quantization
  /// is so poor that distances exceed 2.0 and cosine similarities go negative.
  ///
  /// Adaptive strategy:
  /// - `numCentroidsPerSubquantizer = (n / 10).clamp(8, 256)` → ~10 pts/centroid
  /// - `numClusters = sqrt(n).round().clamp(2, 256)` → balanced cluster sizes
  /// - `numProbes = numClusters` → probe all clusters for maximum recall
  ///
  /// Example for 751 images: 75 centroids, 27 clusters → ~10 pts/centroid ✓
  static ann.IvfPqConfig _ivfpqConfigFor(int n) {
    final numCentroids = (n / 10).floor().clamp(8, 256);
    return ann.IvfPqConfig(
      dimension: 768,
      numClusters: 256,
      numSubquantizers: 64,           // 768 / 64 = 12 dims per subquantizer
      numCentroidsPerSubquantizer: numCentroids,
      numProbes: 256,
      trainingIterations: 50,
    );
  }

  /// Last config used to build the active IVF-PQ index. Driven by
  /// [_ivfpqConfigFor] unless overridden by the alpha-test retrain flow.
  ann.IvfPqConfig? _activeIvfpqConfig;

  // ── Alpha-test tuning surface ────────────────────────────────────────────

  /// Adjust HNSW's runtime accuracy/speed knob. No-op if HNSW isn't loaded.
  /// Higher ef → more accurate but slower per query.
  void setHnswEfSearch(int ef) {
    _hnswIndex?.setEfSearch(ef);
  }

  /// Snapshot of the IVF-PQ config that produced the currently trained index,
  /// or null if no IVF-PQ index is built. Used by the alpha screen tuner.
  ann.IvfPqConfig? get activeIvfpqConfig => _activeIvfpqConfig;

  /// Rebuild the IVF-PQ index with caller-provided overrides on top of the
  /// adaptive defaults. Any null override falls back to [_ivfpqConfigFor]'s
  /// recommended value for the current dataset size. Re-runs k-means + PQ
  /// training, so it's the slow path — only call from explicit user action.
  ///
  /// Returns true on success, false if there aren't enough vectors yet.
  Future<bool> retrainIvfpq({
    int? numClusters,
    int? numSubquantizers,
    int? numProbes,
    int? trainingIterations,
  }) async {
    final n = _imageEmbeddings.length;
    if (n < minVectorsForTraining) {
      debugPrint(
        'ANNSearchService: Cannot retrain IVF-PQ — '
        '$n vectors available, $minVectorsForTraining needed',
      );
      return false;
    }

    final base = _ivfpqConfigFor(n);
    final clusters = (numClusters ?? base.numClusters).clamp(2, 256);
    final probes = (numProbes ?? base.numProbes).clamp(1, clusters);
    final config = ann.IvfPqConfig(
      dimension: base.dimension,
      numClusters: clusters,
      numSubquantizers: numSubquantizers ?? base.numSubquantizers,
      numCentroidsPerSubquantizer: base.numCentroidsPerSubquantizer,
      numProbes: probes,
      trainingIterations: trainingIterations ?? base.trainingIterations,
    );

    _ivfpqIndex?.dispose();
    _ivfpqIndex = ann.IvfPqAnnIndex(config: config);
    _ivfpqTrained = false;

    debugPrint(
      'ANNSearchService: Retraining IVF-PQ — '
      'clusters=${config.numClusters} subs=${config.numSubquantizers} '
      'probes=${config.numProbes} iters=${config.trainingIterations}',
    );

    try {
      final vectors = _imageEmbeddings.values.toList();
      final ids = _imageEmbeddings.keys
          .map((imageId) => _imageIdToIndexId[imageId]!)
          .toList();
      await _ivfpqIndex!.train(vectors);
      await _ivfpqIndex!.addVectors(vectors, ids);
      _ivfpqTrained = true;
      _activeIvfpqConfig = config;
      return true;
    } catch (e) {
      debugPrint('ANNSearchService: IVF-PQ retrain failed: $e');
      return false;
    }
  }

  // ── Public getters ───────────────────────────────────────────────────────

  /// True when the service has embeddings to search over.
  ///
  /// Brute-force is always the final fallback, so [isReady] only requires
  /// that embeddings exist — not that an ANN index is built.
  bool get isReady => _isInitialized && _imageEmbeddings.isNotEmpty;

  bool get usingNativeHnsw =>
      _activeAlgorithm == ann.AnnAlgorithm.hnsw && _hnswInitialized;

  bool get usingIvfPq =>
      _activeAlgorithm == ann.AnnAlgorithm.ivfpq && _ivfpqTrained;

  String get activeAlgorithmName => _activeAlgorithm?.name ?? 'brute-force';

  int get indexSize => _imageMetadata.length;
  int get nativeIndexSize => _hnswIndex?.size ?? _ivfpqIndex?.size ?? 0;

  /// Read-only view of stored embeddings (for cache persistence).
  Map<String, Float32List> get imageEmbeddings =>
      Map.unmodifiable(_imageEmbeddings);

  /// Read-only view of image metadata.
  Map<String, ImageItem> get imageMetadata =>
      Map.unmodifiable(_imageMetadata);

  // ── Initialization ───────────────────────────────────────────────────────

  /// Initialize the service.
  ///
  /// Tries HNSW (native FFI) first; falls back to IVF-PQ (pure Dart) if the
  /// native library is unavailable; falls back to brute-force if both fail.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // ── 1. Try HNSW ──
    try {
      final hnswIndex = ann.HnswAnnIndex(config: _hnswConfig);
      await hnswIndex.initialize();
      _hnswIndex = hnswIndex;
      _hnswInitialized = true;
      _activeAlgorithm = ann.AnnAlgorithm.hnsw;
      _isInitialized = true;
      debugPrint('ANNSearchService: Initialized with HNSW (native FFI)');
      return true;
    } catch (e) {
      debugPrint(
        'ANNSearchService: HNSW unavailable ($e) — trying IVF-PQ',
      );
    }

    // ── 2. Try IVF-PQ ──
    try {
      // Index is created lazily in _trainAndBuildIvfpq() with adaptive config.
      _activeAlgorithm = ann.AnnAlgorithm.ivfpq;
      _isInitialized = true;
      debugPrint(
        'ANNSearchService: Initialized with IVF-PQ '
        '(pure Dart, awaiting training data)',
      );
      return true;
    } catch (e) {
      debugPrint(
        'ANNSearchService: IVF-PQ also failed ($e) — brute-force only',
      );
    }

    // ── 3. Brute-force only ──
    _activeAlgorithm = null;
    _isInitialized = true;
    debugPrint('ANNSearchService: Initialized (brute-force search only)');
    return true;
  }

  // ── Indexing ─────────────────────────────────────────────────────────────

  /// Index a single image with its embedding.
  Future<void> indexImage(ImageItem image, List<double> embedding) async {
    _assertInitialized();

    final float32 = Float32List.fromList(embedding);
    _storeEmbedding(image, float32);

    if (_activeAlgorithm == ann.AnnAlgorithm.hnsw &&
        _hnswIndex != null &&
        _hnswInitialized) {
      await _addToHnsw(image, float32);
    } else if (_activeAlgorithm == ann.AnnAlgorithm.ivfpq) {
      if (_ivfpqTrained) {
        final indexId = _imageIdToIndexId[image.id]!;
        await _ivfpqIndex!.addVector(float32, indexId);
      } else {
        _pendingEmbeddings.add(float32);
        _pendingImages.add(image);
      }
    }
  }

  /// Index multiple images in batch.
  Future<void> indexBatch(
    List<ImageItem> images,
    List<List<double>> embeddings,
  ) async {
    if (images.length != embeddings.length) {
      throw ArgumentError('Images and embeddings must have equal length');
    }

    debugPrint(
      'ANNSearchService: Indexing ${images.length} images '
      '(algorithm: $activeAlgorithmName)...',
    );

    // Store all embeddings first
    for (var i = 0; i < images.length; i++) {
      _storeEmbedding(images[i], Float32List.fromList(embeddings[i]));
    }

    if (_activeAlgorithm == ann.AnnAlgorithm.hnsw) {
      await _ensureHnswInitialized();
      await _addBatchToHnsw(images, embeddings);
    } else if (_activeAlgorithm == ann.AnnAlgorithm.ivfpq) {
      for (var i = 0; i < images.length; i++) {
        _pendingEmbeddings.add(Float32List.fromList(embeddings[i]));
        _pendingImages.add(images[i]);
      }

      if (!_ivfpqTrained &&
          _pendingEmbeddings.length >= minVectorsForTraining) {
        await _trainAndBuildIvfpq();
      } else if (_ivfpqTrained) {
        // Add new vectors to already-trained index
        for (var i = 0; i < _pendingImages.length; i++) {
          final indexId = _imageIdToIndexId[_pendingImages[i].id]!;
          await _ivfpqIndex!.addVector(_pendingEmbeddings[i], indexId);
        }
        _pendingEmbeddings.clear();
        _pendingImages.clear();
      }
    }

    debugPrint(
      'ANNSearchService: Indexed ${images.length} images '
      '(total: ${_imageEmbeddings.length}, ready: $isReady)',
    );
  }

  /// Restore internal state from a previously saved embedding cache.
  ///
  /// For HNSW: vectors are added to the index asynchronously in the background
  /// so that HNSW becomes the active search backend when the next search
  /// arrives. Brute-force is always available immediately.
  ///
  /// For IVF-PQ: vectors are queued as pending and the index is trained the
  /// next time [indexBatch] provides enough data.
  void restoreFromCache(
    Map<String, Float32List> embeddings,
    Map<String, ImageItem> metadata,
  ) {
    for (final entry in embeddings.entries) {
      final imageId = entry.key;
      _imageEmbeddings[imageId] = entry.value;
      if (metadata.containsKey(imageId)) {
        _imageMetadata[imageId] = metadata[imageId]!;
      }
      _assignIndexId(imageId);
    }

    debugPrint(
      'ANNSearchService: Restored ${embeddings.length} cached embeddings',
    );

    // For HNSW: populate index in the background (non-blocking).
    // Searches fall back to brute-force while HNSW is being populated.
    if (_activeAlgorithm == ann.AnnAlgorithm.hnsw &&
        _hnswIndex != null &&
        _hnswInitialized) {
      _populateHnswFromCacheAsync(embeddings);
    }

    // For IVF-PQ: embeddings are in _imageEmbeddings; training happens
    // when enough data arrives via indexBatch.
  }

  // ── Search ───────────────────────────────────────────────────────────────

  /// Search for similar images, returning results with similarity scores.
  ///
  /// Set [forceBruteForce] to `true` for exact results regardless of dataset
  /// size (useful for alpha testing / accuracy evaluation).
  Future<List<SearchResultWithScore>> searchSimilarWithScores(
    List<double> queryEmbedding, {
    int k = defaultTopK,
    double? threshold,
    bool forceBruteForce = false,
  }) async {
    _assertInitialized();

    final effectiveThreshold = threshold ?? similarityThreshold;
    final sw = Stopwatch()..start();

    List<SearchResultWithScore> results;

    // Effective algorithm: user preference wins; fall through if not ready.
    final effectiveAlgorithm = preferredAlgorithm ?? _activeAlgorithm;

    try {
      if (forceBruteForce ||
          forceBruteForceMode ||
          _imageEmbeddings.length <= bruteForceThreshold) {
        results = _bruteForceSearchWithScores(
          queryEmbedding, k, effectiveThreshold,
        );
        debugPrint(
          'ANNSearchService: Brute-force search '
          '(${_imageEmbeddings.length} images)',
        );
      } else if (effectiveAlgorithm == ann.AnnAlgorithm.hnsw &&
          _hnswIndex != null &&
          _hnswInitialized &&
          _hnswIndex!.size > 0) {
        results = await _hnswSearchWithScores(
          Float32List.fromList(queryEmbedding), k, effectiveThreshold,
        );
        debugPrint('ANNSearchService: HNSW search completed');
      } else if (effectiveAlgorithm == ann.AnnAlgorithm.ivfpq &&
          _ivfpqTrained &&
          _ivfpqIndex != null &&
          _ivfpqIndex!.isReady) {
        results = await _ivfpqSearchWithScores(
          Float32List.fromList(queryEmbedding), k, effectiveThreshold,
        );
        debugPrint('ANNSearchService: IVF-PQ search completed');
      } else {
        results = _bruteForceSearchWithScores(
          queryEmbedding, k, effectiveThreshold,
        );
        debugPrint('ANNSearchService: Brute-force search (ANN index not ready)');
      }
    } catch (e) {
      debugPrint(
        'ANNSearchService: Search failed ($e) — brute-force fallback',
      );
      results = _bruteForceSearchWithScores(
        queryEmbedding, k, effectiveThreshold,
      );
    }

    sw.stop();
    debugPrint(
      'ANNSearchService: Search completed in ${sw.elapsedMilliseconds}ms, '
      'found ${results.length} results (${_imageEmbeddings.length} total)',
    );

    return results;
  }

  /// Search for similar images (returns [ImageItem] list without scores).
  Future<List<ImageItem>> searchSimilar(
    List<double> queryEmbedding, {
    int k = defaultTopK,
    double? threshold,
  }) async {
    final results = await searchSimilarWithScores(
      queryEmbedding,
      k: k,
      threshold: threshold,
    );
    return results.map((r) => r.image).toList();
  }

  // ── Index management ─────────────────────────────────────────────────────

  bool isIndexed(String imageId) => _imageMetadata.containsKey(imageId);

  void removeImage(String imageId) {
    _imageEmbeddings.remove(imageId);
    _imageMetadata.remove(imageId);
    debugPrint('ANNSearchService: Removed $imageId from metadata');
  }

  void clearIndex() {
    _imageEmbeddings.clear();
    _imageMetadata.clear();
    _indexIdToImageId.clear();
    _imageIdToIndexId.clear();
    _pendingEmbeddings.clear();
    _pendingImages.clear();
    _nextIndexId = 0;

    // Recreate the active index object (no await — init happens lazily).
    if (_activeAlgorithm == ann.AnnAlgorithm.hnsw) {
      _hnswIndex?.dispose();
      _hnswIndex = ann.HnswAnnIndex(config: _hnswConfig);
      _hnswInitialized = false;
    } else if (_activeAlgorithm == ann.AnnAlgorithm.ivfpq) {
      _ivfpqIndex?.dispose();
      _ivfpqIndex = null;  // recreated lazily with adaptive config on next train
      _ivfpqTrained = false;
    }

    debugPrint('ANNSearchService: Index cleared');
  }

  Map<String, dynamic> getIndexStats() {
    return {
      'totalImages': _imageMetadata.length,
      'totalEmbeddings': _imageEmbeddings.length,
      'activeAlgorithm': activeAlgorithmName,
      'hnswSize': _hnswIndex?.size ?? 0,
      'hnswInitialized': _hnswInitialized,
      'ivfpqSize': _ivfpqIndex?.size ?? 0,
      'ivfpqTrained': _ivfpqTrained,
      'pendingVectors': _pendingEmbeddings.length,
      'isReady': isReady,
      'dimensionality': _imageEmbeddings.isEmpty
          ? 0
          : _imageEmbeddings.values.first.length,
    };
  }

  void dispose() {
    _hnswIndex?.dispose();
    _hnswIndex = null;
    _ivfpqIndex?.dispose();
    _ivfpqIndex = null;
    _imageEmbeddings.clear();
    _imageMetadata.clear();
    _indexIdToImageId.clear();
    _imageIdToIndexId.clear();
    _pendingEmbeddings.clear();
    _pendingImages.clear();
    _isInitialized = false;
    _hnswInitialized = false;
    _ivfpqTrained = false;
    debugPrint('ANNSearchService: Disposed');
  }

  // ── Alpha-testing support ────────────────────────────────────────────────

  /// Measures ANN accuracy relative to brute-force ground truth (recall@k).
  Future<Map<String, dynamic>> testAccuracy(
    List<double> queryEmbedding, {
    int k = 10,
  }) async {
    if (_imageEmbeddings.isEmpty) {
      return {'error': 'No embeddings indexed'};
    }

    final bfResults =
        _bruteForceSearchWithScores(queryEmbedding, k, -1.0);
    final bfIds = bfResults.map((r) => r.image.id).toSet();

    final annResults = await searchSimilarWithScores(
      queryEmbedding,
      k: k,
      threshold: -1.0,
    );
    final annIds = annResults.map((r) => r.image.id).toSet();

    final correct = bfIds.intersection(annIds).length;
    final recall = k > 0 ? correct / k : 0.0;

    debugPrint(
      'ANNSearchService: Accuracy test ($activeAlgorithmName): '
      'Recall@$k = ${(recall * 100).toStringAsFixed(1)}%',
    );

    return {
      'k': k,
      'algorithm': activeAlgorithmName,
      'bruteForceResults': bfIds.toList(),
      'algorithmResults': annIds.toList(),
      'correctMatches': correct,
      'recall': recall,
      'recallPercent': '${(recall * 100).toStringAsFixed(1)}%',
    };
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  void _assertInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }
  }

  void _storeEmbedding(ImageItem image, Float32List float32) {
    _imageEmbeddings[image.id] = float32;
    _imageMetadata[image.id] = image;
    _assignIndexId(image.id);
  }

  void _assignIndexId(String imageId) {
    if (!_imageIdToIndexId.containsKey(imageId)) {
      _imageIdToIndexId[imageId] = _nextIndexId;
      _indexIdToImageId[_nextIndexId] = imageId;
      _nextIndexId++;
    }
  }

  Future<void> _ensureHnswInitialized() async {
    if (_hnswIndex == null || _hnswInitialized) return;
    try {
      await _hnswIndex!.initialize();
      _hnswInitialized = true;
    } catch (e) {
      debugPrint('ANNSearchService: HNSW re-initialization failed: $e');
    }
  }

  Future<void> _addToHnsw(ImageItem image, Float32List float32) async {
    final indexId = _imageIdToIndexId[image.id]!;
    try {
      await _hnswIndex!.addVector(float32, indexId);
    } catch (e) {
      debugPrint(
        'ANNSearchService: HNSW addVector failed for ${image.id}: $e',
      );
    }
  }

  Future<void> _addBatchToHnsw(
    List<ImageItem> images,
    List<List<double>> embeddings,
  ) async {
    if (_hnswIndex == null || !_hnswInitialized) return;

    for (var i = 0; i < images.length; i++) {
      final indexId = _imageIdToIndexId[images[i].id]!;
      try {
        await _hnswIndex!.addVector(
          Float32List.fromList(embeddings[i]),
          indexId,
        );
      } catch (e) {
        debugPrint(
          'ANNSearchService: HNSW addVector failed for ${images[i].id}: $e',
        );
      }
    }
    debugPrint('ANNSearchService: HNSW index size: ${_hnswIndex!.size}');
  }

  /// Populate HNSW from cached embeddings asynchronously.
  ///
  /// Searches fall back to brute-force while this runs in the background.
  void _populateHnswFromCacheAsync(Map<String, Float32List> embeddings) {
    Future.microtask(() async {
      if (_hnswIndex == null || !_hnswInitialized) return;
      int added = 0;
      for (final entry in embeddings.entries) {
        final indexId = _imageIdToIndexId[entry.key];
        if (indexId == null) continue;
        try {
          await _hnswIndex!.addVector(entry.value, indexId);
          added++;
        } catch (_) {}
      }
      debugPrint(
        'ANNSearchService: Added $added cached vectors to HNSW '
        '(size: ${_hnswIndex!.size})',
      );
    });
  }

  Future<void> _trainAndBuildIvfpq() async {
    if (_pendingEmbeddings.isEmpty) return;

    final count = _pendingEmbeddings.length;
    debugPrint(
      'ANNSearchService: Training IVF-PQ on $count vectors...',
    );
    final sw = Stopwatch()..start();

    try {
      // Create (or recreate) index with adaptive config for this dataset size.
      _ivfpqIndex?.dispose();
      _ivfpqIndex = ann.IvfPqAnnIndex(config: _ivfpqConfigFor(count));

      await _ivfpqIndex!.train(_pendingEmbeddings);

      final ids =
          _pendingImages.map((img) => _imageIdToIndexId[img.id]!).toList();
      await _ivfpqIndex!.addVectors(_pendingEmbeddings, ids);

      _ivfpqTrained = true;
      _pendingEmbeddings.clear();
      _pendingImages.clear();

      sw.stop();
      debugPrint(
        'ANNSearchService: IVF-PQ trained in ${sw.elapsedMilliseconds}ms '
        '(${_ivfpqIndex!.size} vectors)',
      );
      debugPrint(
        'ANNSearchService: IVF-PQ stats: ${_ivfpqIndex!.getStatistics()}',
      );
    } catch (e) {
      debugPrint(
        'ANNSearchService: IVF-PQ training failed ($e) — brute-force active',
      );
    }
  }

  // ── Search implementations ───────────────────────────────────────────────

  Future<List<SearchResultWithScore>> _hnswSearchWithScores(
    Float32List query,
    int k,
    double threshold,
  ) async {
    final searchResults = await _hnswIndex!.search(query, k);

    final results = <SearchResultWithScore>[];
    for (final r in searchResults) {
      final imageId = _indexIdToImageId[r.id];
      if (imageId == null) continue;
      final image = _imageMetadata[imageId];
      if (image == null) continue;

      // HNSW with innerProduct space: distance = 1 − cos_sim,
      // so similarity = 1 − distance.
      final similarity = 1.0 - r.distance;

      if (threshold < 0 || similarity >= threshold) {
        results.add(
          SearchResultWithScore(image: image, similarity: similarity),
        );
      }
    }

    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    _logTop5('HNSW', results);
    return results;
  }

  Future<List<SearchResultWithScore>> _ivfpqSearchWithScores(
    Float32List query,
    int k,
    double threshold,
  ) async {
    if (_ivfpqIndex == null || !_ivfpqIndex!.isReady) {
      return _bruteForceSearchWithScores(query.toList(), k, threshold);
    }

    final searchResults = await _ivfpqIndex!.search(query, k);

    final results = <SearchResultWithScore>[];
    for (final r in searchResults) {
      final imageId = _indexIdToImageId[r.id];
      if (imageId == null) continue;
      final image = _imageMetadata[imageId];
      if (image == null) continue;

      // IVF-PQ: computeAsymmetricDistance returns the sum of squared
      // sub-vector distances, which approximates the full squared L2 distance
      // ||q − v||².  For unit-normalized SigLIP vectors:
      //   cos_sim = 1 − ||q − v||² / 2
      // r.distance is already the squared distance — do NOT square it again.
      final similarity = 1.0 - r.distance / 2.0;

      if (threshold < 0 || similarity >= threshold) {
        results.add(
          SearchResultWithScore(image: image, similarity: similarity),
        );
      }
    }

    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    _logTop5('IVF-PQ', results);
    return results;
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
        allResults.add(
          SearchResultWithScore(image: image, similarity: similarity),
        );
      }
    }

    allResults.sort((a, b) => b.similarity.compareTo(a.similarity));
    _logTop5('Brute-force', allResults);
    return allResults.take(k).toList();
  }

  void _logTop5(String label, List<SearchResultWithScore> results) {
    debugPrint('ANNSearchService: $label top results:');
    for (var i = 0; i < results.length && i < 5; i++) {
      final r = results[i];
      debugPrint(
        '  ${i + 1}. ${r.image.id}: ${r.similarity.toStringAsFixed(4)}',
      );
    }
  }

  double _cosineSimilarity(List<double> a, List<num> b) {
    assert(a.length == b.length, 'Vector dimensions must match');

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = math.sqrt(normA);
    normB = math.sqrt(normB);
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (normA * normB);
  }
}
