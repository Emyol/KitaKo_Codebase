import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/search_models.dart';
import 'image_loader_service.dart';
import 'embedding_service.dart';
import 'embedding_storage_service.dart';
import 'ann_search_service.dart';
import 'query_assist_service.dart';
import 'face_service.dart';

/// High-level phase of the startup indexing pipeline.
enum IndexingPhase {
  idle,
  loadingModel,
  prewarmingVariants,
  restoringCache,
  loadingGallery,
  embedding,
  embeddingPartialFailure,
  savingCache,
  switchingVariant,
  ready,
  error,
}

/// Progress snapshot emitted during startup indexing and variant switching.
class IndexingProgress {
  final IndexingPhase phase;
  final String message;

  /// Completed count (for phases that iterate — embedding / prewarm).
  final int? done;

  /// Total count (for phases that iterate — embedding / prewarm).
  final int? total;

  /// Error message when [phase] is [IndexingPhase.error].
  final String? error;

  /// Number of images that failed to embed (for [IndexingPhase.embeddingPartialFailure]).
  final int? failedCount;

  const IndexingProgress({
    required this.phase,
    required this.message,
    this.done,
    this.total,
    this.error,
    this.failedCount,
  });

  /// Fractional progress 0.0–1.0 if known, else null.
  double? get fraction {
    if (done == null || total == null || total == 0) return null;
    return (done! / total!).clamp(0.0, 1.0);
  }
}

/// Main orchestrator service for image search functionality
///
/// This service coordinates:
/// - Loading images from device
/// - Generating embeddings for text queries
/// - Performing ANN similarity search
/// - Managing search state and results
///
/// Example usage:
/// ```dart
/// final searchService = ImageSearchService();
/// await searchService.initialize();
///
/// // Perform search
/// searchService.searchImages('sunset beach');
///
/// // Listen to results
/// searchService.searchStateStream.listen((state) {
///   if (state.status == SearchStatus.completed) {
///     print('Found ${state.results.length} images');
///   }
/// });
/// ```
class ImageSearchService {
  // ========== Dependencies ==========

  final ImageLoaderService _imageLoader;
  final EmbeddingService _embeddingService;
  final ANNSearchService _annSearch;
  final EmbeddingStorageService _storage = EmbeddingStorageService();
  final TaglishNormalizer _normalizer = const TaglishNormalizer();
  final QueryAssistService _queryAssist = QueryAssistService();

  /// Optional face recognition service. Null = face features disabled.
  final FaceService? _faceService;

  /// Create a new ImageSearchService with optional custom services.
  ///
  /// [faceService] is fully optional — omit to disable face features.
  ImageSearchService({
    ImageLoaderService? imageLoader,
    EmbeddingService? embeddingService,
    ANNSearchService? annSearchService,
    FaceService? faceService,
  }) : _imageLoader = imageLoader ?? ImageLoaderService(),
       _embeddingService = embeddingService ?? EmbeddingService(),
       _annSearch = annSearchService ?? ANNSearchService(),
       _faceService = faceService;

  // ========== State Management ==========

  /// Stream controller for search state updates
  final _searchStateController = StreamController<SearchState>.broadcast();

  /// Stream controller for image loading updates
  final _imagesLoadedController = StreamController<List<ImageItem>>.broadcast();

  /// Stream controller for indexing progress updates
  final _progressController = StreamController<IndexingProgress>.broadcast();

  /// Last progress snapshot (so late subscribers see current state)
  IndexingProgress _lastProgress =
      const IndexingProgress(phase: IndexingPhase.idle, message: '');

  /// Resolves to true (retry) or false (skip) when the UI responds to a partial
  /// embedding failure prompt.
  Completer<bool>? _embeddingFailureCompleter;

  /// Current search state
  SearchState _currentState = const SearchState();

  /// All loaded device images (for gallery display)
  List<ImageItem> _loadedImages = [];

  /// Count of images indexed with embeddings (for search)
  int _indexedCount = 0;

  /// Stream of search state changes
  Stream<SearchState> get searchStateStream => _searchStateController.stream;

  /// Stream of images loaded events (notifies when gallery images are available)
  Stream<List<ImageItem>> get imagesLoadedStream => _imagesLoadedController.stream;

  /// Stream of indexing progress events (startup + variant switch).
  Stream<IndexingProgress> get indexingProgressStream =>
      _progressController.stream;

  /// Most recent indexing progress snapshot.
  IndexingProgress get lastProgress => _lastProgress;

  void _emitProgress(
    IndexingPhase phase,
    String message, {
    int? done,
    int? total,
    String? error,
    int? failedCount,
  }) {
    _lastProgress = IndexingProgress(
      phase: phase,
      message: message,
      done: done,
      total: total,
      error: error,
      failedCount: failedCount,
    );
    if (!_progressController.isClosed) {
      _progressController.add(_lastProgress);
    }
  }

  // ========== Service Access ==========

  /// Access to image loader service (for alpha testing and person detail screen)
  ImageLoaderService get imageLoader => _imageLoader;

  /// Access to ANN search service (for alpha testing with brute force)
  ANNSearchService get annSearchService => _annSearch;

  /// Access to face service. Null when face recognition is disabled.
  FaceService? get faceService => _faceService;

  /// Whether face recognition features are available.
  bool get isFaceSearchAvailable => _faceService?.isAvailable ?? false;

  /// Run face detection + clustering over the loaded gallery.
  ///
  /// Call this once after [FaceService.tryAutoInitialize] returns true.
  /// Images are loaded and processed in small batches so peak memory stays
  /// bounded; the face pipeline is released between batches by the GC.
  Future<void> startFaceIndexing() async {
    final face = _faceService;
    if (face == null || !face.isAvailable) return;

    final images = getAllImages();
    if (images.isEmpty) return;

    debugPrint('ImageSearchService: Starting face indexing for ${images.length} images');

    // Reset any previously cached data so re-indexing starts clean
    face.clearAllData();

    const batchSize = 30;
    for (int i = 0; i < images.length; i += batchSize) {
      final batch = images.sublist(i, (i + batchSize).clamp(0, images.length));
      final entries = <MapEntry<String, Uint8List>>[];

      for (final img in batch) {
        try {
          final bytes = await _imageLoader.loadImageBytes(img.id);
          if (bytes != null) entries.add(MapEntry(img.id, bytes));
        } catch (e) {
          debugPrint('ImageSearchService: Face indexing — skipping ${img.id}: $e');
        }
      }

      if (entries.isNotEmpty) {
        await face.indexImageBatch(entries);
      }

      debugPrint(
        'ImageSearchService: Face indexing ${(i + batchSize).clamp(0, images.length)}/${images.length}',
      );
    }

    await face.finalizeClustering();
    debugPrint(
      'ImageSearchService: Face indexing complete — '
      '${face.faceCount} faces, ${face.personCount} persons',
    );
  }

  // ========== Algorithm Preference ==========

  /// Whether the user preference is HNSW (`true`), IVF-PQ (`false`), or auto (`null`).
  bool? get preferHnsw => _annSearch.preferHnsw;

  /// Force exact brute-force search regardless of index state.
  /// Used by the alpha test screen to compare algorithms head-to-head.
  void setForceBruteForce(bool force) {
    _annSearch.forceBruteForceMode = force;
  }

  /// Snapshot of ANN index state for display in the alpha test screen.
  Map<String, dynamic> get annIndexStatus => _annSearch.getIndexStats();

  // ========== Memory pressure / lifecycle ==========

  /// Release non-essential in-memory buffers. Safe to call at any time —
  /// the index, embeddings, and image metadata are untouched. Currently
  /// drops thumbnail byte buffers (which can total multiple GB at scale)
  /// and clears the last search result so its retained images don't
  /// pin thumbnails. Callers: lifecycle observer on memory pressure.
  void releaseTransientMemory() {
    _imageLoader.clearThumbnailBytes();
    _currentState = const SearchState();
    if (!_searchStateController.isClosed) {
      _searchStateController.add(_currentState);
    }
  }

  // ========== ANN Tuning (Alpha Test) ==========

  /// Adjust HNSW's runtime accuracy/speed knob. Higher ef → more accurate
  /// per query, but slower. No-op if HNSW isn't loaded.
  void setHnswEfSearch(int ef) => _annSearch.setHnswEfSearch(ef);

  /// Rebuild the IVF-PQ index with caller-provided overrides on top of the
  /// adaptive defaults. Slow path — re-runs k-means + PQ training.
  Future<bool> retrainIvfpq({
    int? numClusters,
    int? numSubquantizers,
    int? numProbes,
    int? trainingIterations,
  }) {
    return _annSearch.retrainIvfpq(
      numClusters: numClusters,
      numSubquantizers: numSubquantizers,
      numProbes: numProbes,
      trainingIterations: trainingIterations,
    );
  }

  /// Set the preferred search algorithm shown in Settings.
  ///
  /// [useHnsw] = `true`  → Accuracy mode  (HNSW)
  /// [useHnsw] = `false` → Performance mode (IVF-PQ)
  ///
  /// When switching to IVF-PQ the index is trained in the background from
  /// already-stored embeddings. Searches fall back to brute-force until
  /// training completes (usually a few seconds).
  void setPreferredAlgorithm(bool useHnsw) {
    _annSearch.setPreferHnsw(useHnsw);
    debugPrint(
      'ImageSearchService: Preferred algorithm set to '
      '${_annSearch.preferredAlgorithm?.name}',
    );
    if (!useHnsw) {
      // Fire-and-forget: train IVF-PQ from existing embeddings.
      // Brute-force handles any searches that arrive while training runs.
      _annSearch.ensureIvfpqReady();
    }
  }

  /// Current search state (read-only)
  SearchState get currentState => _currentState;

  /// Access to embedding service (for model switching)
  EmbeddingService get embeddingService => _embeddingService;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  // ========== Configuration ==========

  /// Number of top results to return
  int topK = 20;

  /// Absolute floor: any result below this cosine similarity is discarded.
  ///
  /// Observed score ranges for Kitako INT8 model:
  ///   Image-image: 0.66 – 1.00 (same encoder, no modality gap)
  ///   Text-image:  0.08 – 0.11 (cross-modal; tight cluster)
  ///
  /// For text-image queries a floor of 0.08 removes clear noise while
  /// keeping genuine matches (~0.10 typical top score).
  double absoluteThreshold = 0.08;

  /// Relative cutoff: results must score at least this fraction of the
  /// top result's similarity.
  ///
  /// Text-image scores cluster tightly (e.g. top=0.106, 5th=0.102 — only
  /// 0.4% spread). A high relative threshold (0.90) means only results within
  /// 10% of the best match are kept, which gives meaningful discrimination
  /// without cutting too aggressively.
  ///
  /// For image-image (top ~0.68) this keeps results above ~0.61 — appropriate.
  double relativeThreshold = 0.90;

  /// Whether to auto-index images on load
  bool autoIndex = true;

  // ========== Initialization ==========

  /// Initialize all services.
  ///
  /// [preferredVariant]  — the model variant to activate after startup.
  /// [prewarmVariants]   — variants whose ONNX files are loaded once during
  ///                       startup to verify they are usable. Pass the full
  ///                       developer-facing set on first launch so a later
  ///                       model switch can't hit an unloadable model.
  ///
  /// Returns `true` if all services initialized successfully.
  Future<bool> initialize({
    ModelVariant? preferredVariant,
    List<ModelVariant> prewarmVariants = const [],
  }) async {
    if (_isInitialized) return true;

    try {
      debugPrint('ImageSearchService: Initializing...');
      _emitProgress(IndexingPhase.loadingModel, 'Starting up…');

      // Initialize loader and ANN (required)
      final loaderInit = await _imageLoader.initialize();
      final annInit = await _annSearch.initialize();

      if (!loaderInit || !annInit) {
        debugPrint('ImageSearchService: Loader or ANN failed to initialize');
        _emitProgress(IndexingPhase.error, 'Storage init failed',
            error: 'Loader or ANN failed to initialize');
        return false;
      }

      // Load the preferred variant up-front when specified, otherwise fall
      // back to the default auto-probe.
      _emitProgress(IndexingPhase.loadingModel,
          'Loading ${preferredVariant?.displayName ?? "model"}…');
      bool embeddingInit;
      if (preferredVariant != null) {
        embeddingInit =
            await _embeddingService.switchToVariant(preferredVariant);
        if (!embeddingInit) {
          debugPrint('ImageSearchService: Preferred variant '
              '${preferredVariant.displayName} failed to load — falling back '
              'to default probe');
          embeddingInit = await _embeddingService.initialize();
        }
      } else {
        embeddingInit = await _embeddingService.initialize();
      }

      // First-launch prewarm: verify the other declared variants load too.
      // Uses the shared per-vision-encoder cache, so no extra embedding
      // happens here — just ONNX session open/close.
      final currentVariant = _embeddingService.activeVariant;
      for (final v in prewarmVariants) {
        if (v == currentVariant) continue;
        if (!await _embeddingService.isVariantAvailable(v)) {
          debugPrint(
              'ImageSearchService: Skipping prewarm for ${v.displayName} '
              '— files not present');
          continue;
        }
        _emitProgress(IndexingPhase.prewarmingVariants,
            'Verifying ${v.displayName}…');
        final ok = await _embeddingService.switchToVariant(v);
        debugPrint('ImageSearchService: Prewarm ${v.displayName} → '
            '${ok ? "OK" : "FAILED"}');
      }
      // Return to the preferred variant after prewarm.
      if (prewarmVariants.isNotEmpty && currentVariant != null &&
          _embeddingService.activeVariant != currentVariant) {
        _emitProgress(IndexingPhase.loadingModel,
            'Restoring ${currentVariant.displayName}…');
        await _embeddingService.switchToVariant(currentVariant);
      }

      // Load device gallery metadata so the grid can render lazily from disk.
      _emitProgress(IndexingPhase.loadingGallery, 'Loading device gallery…');
      final allImages = await _imageLoader.loadDeviceImages();
      if (allImages.isNotEmpty) {
        final gallery = allImages.take(1000).toList();
        _loadedImages = gallery;
        _imagesLoadedController.add(gallery);
        debugPrint('ImageSearchService: Loaded ${gallery.length} images for gallery');
      }

      _isInitialized = true;

      if (!embeddingInit) {
        debugPrint('ImageSearchService: Initialized WITHOUT embedding model. '
            'Install ONNX model files to enable search.');
        _emitProgress(IndexingPhase.ready,
            'Gallery loaded — no embedding model found');
        return true;
      }

      // Auto-index existing images if a real model is loaded
      if (autoIndex && _embeddingService.isImageReady) {
        await _indexDeviceImages();
      }

      debugPrint('ImageSearchService: Initialized successfully');
      _emitProgress(IndexingPhase.ready, 'Ready');
      return true;
    } catch (e) {
      debugPrint('ImageSearchService: Initialization failed: $e');
      _emitProgress(IndexingPhase.error, 'Startup failed', error: e.toString());
      return false;
    }
  }

  // ========== Search Operations ==========

  /// Search for images using text query
  ///
  /// This method:
  /// 1. Generates embedding for the query text
  /// 2. Searches for similar images using ANN
  /// 3. Updates search state throughout the process
  ///
  /// Parameters:
  /// - [query]: The search query text
  /// - [topK]: Number of results to return (optional)
  /// - [threshold]: Minimum similarity threshold (optional)
  Future<void> searchImages(
    String query, {
    int? topK,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'ImageSearchService not initialized. Call initialize() first.',
      );
    }

    if (query.trim().isEmpty) {
      _updateState(const SearchState());
      return;
    }

    // Explicit "person:<name>" prefix → face label search.
    final trimmed = query.trim();
    if (trimmed.toLowerCase().startsWith('person:')) {
      final label = trimmed.substring(7).trim();
      if (label.isNotEmpty) {
        await searchByPerson(label);
        return;
      }
    }

    final k = topK ?? this.topK;

    // Normalize the query using TaglishNormalizer
    final normalizedQuery = _normalizer.normalize(query);
    debugPrint('ImageSearchService: Original: "$query" → Normalized: "$normalizedQuery"');

    try {
      // Update to searching state with normalized query
      _updateState(SearchState(
        status: SearchStatus.searching,
        query: query,
        normalizedQuery: normalizedQuery,
      ));

      // If a known person label appears in the query, narrow candidates to
      // that person's images and re-rank them with the full SigLIP-2 query.
      final matchedLabel = _findPersonLabelInQuery(query);
      if (matchedLabel != null) {
        await _searchPersonWithSemantics(
          matchedLabel, query, normalizedQuery, k,
        );
        return;
      }

      debugPrint('ImageSearchService: Searching for "$query"...');
      final stopwatch = Stopwatch()..start();

      // Step 1: Generate embedding for NORMALIZED query
      final embeddingSw = Stopwatch()..start();
      final queryEmbedding = await _embeddingService.generateEmbedding(normalizedQuery);
      embeddingSw.stop();

      // Step 2: Search with scores (no threshold — combo filter handles it)
      // Oversample so dataset filtering still leaves >= k candidates when
      // the active dataset is sparsely represented in the global top-k.
      final searchSw = Stopwatch()..start();
      final raw = await _annSearch.searchSimilarWithScores(
        queryEmbedding,
        k: k * 8,
        threshold: -1.0,
      );
      searchSw.stop();

      // Step 3: Take top-k, then apply combo filter.
      final scoped = raw.take(k).toList();
      final filtered = _applyComboFilter(scoped);

      // Step 4: Collect results (thumbnails are loaded lazily by the grid).
      final imagesWithThumbnails = filtered.map((r) => r.image).toList();
      final scores = filtered.map((r) => r.similarity).toList();

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Step 5: Classify confidence and generate suggestions if needed
      final confidence = _queryAssist.detectConfidence(
        scores,
        imagesWithThumbnails.length,
      );
      final suggestions = confidence != QueryConfidence.strong
          ? _queryAssist.generateSuggestions(normalizedQuery)
          : null;

      // Step 6: Update state with results
      if (imagesWithThumbnails.isEmpty) {
        _updateState(
          SearchState(
            status: SearchStatus.noResults,
            query: query,
            normalizedQuery: normalizedQuery,
            suggestions: suggestions,
            queryConfidence: QueryConfidence.failed,
            result: SearchResult(
              images: [],
              scores: [],
              query: query,
              embeddingTimeMs: embeddingSw.elapsedMilliseconds,
              searchTimeMs: searchSw.elapsedMilliseconds,
            ),
          ),
        );
      } else {
        _updateState(
          SearchState(
            status: SearchStatus.success,
            query: query,
            normalizedQuery: normalizedQuery,
            suggestions: suggestions,
            queryConfidence: confidence,
            result: SearchResult(
              images: imagesWithThumbnails,
              scores: scores,
              query: query,
              embeddingTimeMs: embeddingSw.elapsedMilliseconds,
              searchTimeMs: searchSw.elapsedMilliseconds,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('ImageSearchService: Search failed: $e');
      _updateState(
        SearchState(
          status: SearchStatus.error,
          query: query,
          normalizedQuery: normalizedQuery,
          error: e.toString(),
        ),
      );
    }
  }

  /// Clear current search and reset to initial state
  void clearSearch() {
    _updateState(const SearchState());
  }

  /// Search for images containing a person with the given label.
  ///
  /// Delegates to [FaceService.searchByPersonLabel] and then loads
  /// thumbnails for matching image IDs. No-op if face service is unavailable.
  Future<void> searchByPerson(String label) async {
    final face = _faceService;
    if (face == null || !face.isAvailable) return;

    _updateState(SearchState(
      status: SearchStatus.searching,
      query: 'Person: $label',
    ));

    try {
      final imageIds = face.searchByPersonLabel(label);

      final images = imageIds
          .map((id) => getImageById(id))
          .whereType<ImageItem>()
          .toList();

      if (images.isEmpty) {
        _updateState(SearchState(
          status: SearchStatus.noResults,
          query: 'Person: $label',
          result: const SearchResult(images: [], scores: [], query: ''),
        ));
      } else {
        _updateState(SearchState(
          status: SearchStatus.success,
          query: 'Person: $label',
          result: SearchResult(
            images: images,
            scores: List.filled(images.length, 1.0),
            query: 'Person: $label',
          ),
        ));
      }
    } catch (e) {
      _updateState(SearchState(
        status: SearchStatus.error,
        query: 'Person: $label',
        error: e.toString(),
      ));
    }
  }

  /// Search for similar images using an image query (image-to-image search)
  ///
  /// This method:
  /// 1. Generates embedding for the query image
  /// 2. Searches for similar images using ANN
  /// 3. Updates search state throughout the process
  ///
  /// Parameters:
  /// - [imageBytes]: The image data as bytes
  /// - [topK]: Number of results to return (optional)
  /// - [threshold]: Minimum similarity threshold (optional)
  Future<void> searchByImage(
    List<int> imageBytes, {
    int? topK,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'ImageSearchService not initialized. Call initialize() first.',
      );
    }

    final k = topK ?? this.topK;
    final queryImageBytes = Uint8List.fromList(imageBytes);

    try {
      // Update to searching state with query image
      _updateState(SearchState(
        status: SearchStatus.searching,
        query: '[Image Search]',
        queryImage: queryImageBytes,
      ));

      debugPrint('ImageSearchService: Searching by image...');
      final stopwatch = Stopwatch()..start();

      // Step 1: Generate embedding for query image
      final queryEmbedding = await _embeddingService.generateImageEmbedding(
        queryImageBytes,
      );

      // Step 2: Search with scores. Oversample so dataset filtering leaves
      // enough candidates when the active dataset is sparsely represented.
      final raw = await _annSearch.searchSimilarWithScores(
        queryEmbedding,
        k: k * 8,
        threshold: -1.0,
      );

      // Step 3: Take top-k, then apply combo filter.
      final scoped = raw.take(k).toList();
      final filtered = _applyComboFilter(scoped, isImageSearch: true);

      // Step 4: Collect results (thumbnails are loaded lazily by the grid).
      final imagesWithThumbnails = filtered.map((r) => r.image).toList();
      final scores = filtered.map((r) => r.similarity).toList();

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Image search completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Step 5: Update state with results
      if (imagesWithThumbnails.isEmpty) {
        _updateState(
          SearchState(
            status: SearchStatus.noResults,
            query: '[Image Search]',
            queryImage: queryImageBytes,
            result: const SearchResult(images: [], scores: [], query: '[Image Search]'),
          ),
        );
      } else {
        _updateState(
          SearchState(
            status: SearchStatus.success,
            query: '[Image Search]',
            queryImage: queryImageBytes,
            result: SearchResult(
              images: imagesWithThumbnails,
              scores: scores,
              query: '[Image Search]',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('ImageSearchService: Image search failed: $e');
      _updateState(
        SearchState(
          status: SearchStatus.error,
          query: '[Image Search]',
          queryImage: queryImageBytes,
          error: e.toString(),
        ),
      );
    }
  }

  /// Search for similar images using an indexed image ID
  ///
  /// Convenience method that loads the thumbnail for the given image ID
  /// and performs image-to-image search.
  Future<void> searchByImageId(String imageId) async {
    final bytes = await _imageLoader.loadThumbnail(imageId);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Could not load image for ID: $imageId');
    }
    await searchByImage(bytes);
  }

  // ========== Image Management ==========

  /// Refresh device images and re-index
  ///
  /// Call this when images on device have changed.
  Future<void> refreshImages() async {
    if (!_isInitialized) {
      throw StateError('ImageSearchService not initialized');
    }

    try {
      debugPrint('ImageSearchService: Refreshing images...');

      // Reload images from device
      await _imageLoader.refreshImages();

      // Re-index if auto-index is enabled
      if (autoIndex) {
        await _indexDeviceImages();
      }

      debugPrint('ImageSearchService: Images refreshed');
    } catch (e) {
      debugPrint('ImageSearchService: Failed to refresh images: $e');
      rethrow;
    }
  }

  /// Get all loaded device images (for gallery display)
  List<ImageItem> getAllImages() {
    return _loadedImages;
  }

  /// Get count of images indexed with embeddings (for search)
  int get indexedImageCount => _indexedCount;

  /// Get image by ID
  ImageItem? getImageById(String id) {
    final images = getAllImages();
    try {
      return images.firstWhere((img) => img.id == id);
    } catch (_) {
      return null;
    }
  }

  // ========== Statistics ==========

  /// Get service statistics
  Map<String, dynamic> getStats() {
    return {
      'initialized': _isInitialized,
      'totalImages': getAllImages().length,
      'indexedImages': _annSearch.indexSize,
      'embeddingCache': _embeddingService.getCacheStats(),
      'annIndex': _annSearch.getIndexStats(),
      'currentState': _currentState.status.toString(),
    };
  }

  // ========== Embedding failure response ==========

  /// Called by the UI when the user responds to an [IndexingPhase.embeddingPartialFailure]
  /// prompt. Pass [retry] = true to re-embed failed images, false to skip them
  /// and continue to [IndexingPhase.ready] with what was already embedded.
  void continueAfterEmbeddingFailure({required bool retry}) {
    _embeddingFailureCompleter?.complete(retry);
  }

  // ========== Cleanup ==========

  /// Dispose of all resources
  void dispose() {
    _searchStateController.close();
    _imagesLoadedController.close();
    _progressController.close();
    _imageLoader.dispose();
    _embeddingService.dispose();
    _annSearch.dispose();
    _isInitialized = false;
    debugPrint('ImageSearchService: Disposed');
  }

  // ========== Private Methods ==========

  /// Apply relevance filter to search results.
  ///
  /// **Text search** (isImageSearch = false):
  ///   Uses absolute floor + relative cutoff. Scores cluster tightly
  ///   (~0.08–0.11), so a 90% relative threshold keeps only genuine matches.
  ///
  /// **Image search** (isImageSearch = true):
  ///   Uses absolute floor only (no relative cutoff). The top result is
  ///   always the self-match (score ≈ 1.0), which would set a cutoff of
  ///   ≥0.90 and eliminate all real similar images at ~0.66–0.68. Instead,
  ///   a fixed 0.60 floor keeps all genuinely similar images.
  ///
  /// The input list must already be sorted by similarity descending.
  List<SearchResultWithScore> _applyComboFilter(
    List<SearchResultWithScore> results, {
    bool isImageSearch = false,
  }) {
    if (results.isEmpty) return results;

    // TEMP: threshold filtering disabled for testing — return all raw results
    debugPrint('ImageSearchService: Filter DISABLED — returning all ${results.length} raw results');
    return results;

    // For image-image: use a fixed 0.60 floor, no relative cutoff.
    // For text-image: use the configured absolute + relative thresholds.
    // ignore: dead_code
    const double imageAbsFloor = 0.60;
    // ignore: dead_code
    final double absFloor = isImageSearch ? imageAbsFloor : absoluteThreshold;

    final aboveFloor = results
        .where((r) => r.similarity >= absFloor)
        .toList();

    if (aboveFloor.isEmpty) {
      debugPrint('ImageSearchService: Combo filter: all ${results.length} results '
          'below absolute floor ($absFloor)');
      return [];
    }

    if (isImageSearch) {
      debugPrint('ImageSearchService: Image filter: '
          '${results.length} raw → ${aboveFloor.length} above floor ($absFloor)');
      return aboveFloor;
    }

    // Text search: additional relative cutoff
    final bestScore = aboveFloor.first.similarity;
    final cutoff = bestScore * relativeThreshold;
    final filtered = aboveFloor
        .where((r) => r.similarity >= cutoff)
        .toList();

    debugPrint('ImageSearchService: Text filter: '
        '${results.length} raw → ${aboveFloor.length} above floor ($absFloor) '
        '→ ${filtered.length} above relative cutoff '
        '(${(relativeThreshold * 100).toStringAsFixed(0)}% of best ${bestScore.toStringAsFixed(3)} = ${cutoff.toStringAsFixed(3)})');

    return filtered;
  }

  /// Return the first known person label that appears as a whole word in [query],
  /// or null if none match.
  String? _findPersonLabelInQuery(String query) {
    final face = _faceService;
    if (face == null || !face.isAvailable) return null;
    final queryLower = query.toLowerCase();
    for (final person in face.allPersons) {
      final label = person.label;
      if (label == null || label.isEmpty) continue;
      final escaped = RegExp.escape(label.toLowerCase());
      if (RegExp('(^|\\s)$escaped(\$|\\s)').hasMatch(queryLower)) return label;
    }
    return null;
  }

  /// Narrow candidates to [personLabel]'s images, then re-rank with the full
  /// SigLIP-2 text embedding of [normalizedQuery].
  Future<void> _searchPersonWithSemantics(
    String personLabel,
    String query,
    String normalizedQuery,
    int k,
  ) async {
    final face = _faceService!;
    final candidateIds = face.searchByPersonLabel(personLabel).toSet();
    if (candidateIds.isEmpty) return;

    // If embeddings aren't indexed yet for these images, return unranked.
    final embSw = Stopwatch()..start();
    List<SearchResultWithScore> scored;
    try {
      final queryEmbedding =
          await _embeddingService.generateEmbedding(normalizedQuery);
      embSw.stop();
      scored = _annSearch.searchSubset(queryEmbedding, candidateIds, k: k);
    } catch (e) {
      embSw.stop();
      debugPrint('ImageSearchService: Person semantic re-rank failed: $e');
      // Fallback: return all candidate images unranked.
      final images = candidateIds
          .map(getImageById)
          .whereType<ImageItem>()
          .toList();
      _updateState(SearchState(
        status: images.isEmpty ? SearchStatus.noResults : SearchStatus.success,
        query: query,
        normalizedQuery: normalizedQuery,
        result: SearchResult(
          images: images,
          scores: List.filled(images.length, 1.0),
          query: query,
        ),
      ));
      return;
    }

    // If no stored embeddings for these images, fall back to unranked.
    if (scored.isEmpty) {
      final images = candidateIds
          .map(getImageById)
          .whereType<ImageItem>()
          .toList();
      _updateState(SearchState(
        status: images.isEmpty ? SearchStatus.noResults : SearchStatus.success,
        query: query,
        normalizedQuery: normalizedQuery,
        result: SearchResult(
          images: images,
          scores: List.filled(images.length, 1.0),
          query: query,
        ),
      ));
      return;
    }

    final images = scored.map((r) => r.image).toList();
    final scores = scored.map((r) => r.similarity).toList();
    debugPrint(
      'ImageSearchService: Person "$personLabel" — '
      '${candidateIds.length} candidates → ${scored.length} ranked',
    );
    _updateState(SearchState(
      status: SearchStatus.success,
      query: query,
      normalizedQuery: normalizedQuery,
      result: SearchResult(
        images: images,
        scores: scores,
        query: query,
        embeddingTimeMs: embSw.elapsedMilliseconds,
      ),
    ));
  }

  /// Update search state and notify listeners
  void _updateState(SearchState newState) {
    _currentState = newState;
    _searchStateController.add(newState);
  }

  /// Index all device images, restoring from cache when possible.
  ///
  /// Flow:
  /// 1. Try to load cached embeddings (matching current model variant)
  /// 2. Restore cached embeddings into ANN service + load saved IVF-PQ index
  /// 3. Only embed NEW images that aren't in the cache
  /// 4. Save updated cache after completion
  Future<void> _indexDeviceImages() async {
    try {
      final allImages = await _imageLoader.loadDeviceImages();

      if (allImages.isEmpty) {
        debugPrint('ImageSearchService: No images to index');
        return;
      }

      // Refuse to index with mock backend - would produce garbage results
      if (_embeddingService.activeBackend == EmbeddingBackend.mock) {
        debugPrint('ImageSearchService: Cannot index with MOCK backend - no real model loaded');
        return;
      }

      if (!_embeddingService.isImageReady) {
        debugPrint('ImageSearchService: Image encoder not ready, cannot index');
        throw StateError(
          'Image encoder not ready. Ensure model files are installed and loaded.',
        );
      }

      final imagesToProcess = allImages.toList();

      // ── Step 1: Try loading cached embeddings from storage layer ──
      final visionEncoderId =
          _embeddingService.activeVariant?.visionEncoderId ?? 'unknown';
      _emitProgress(IndexingPhase.restoringCache,
          'Restoring cached embeddings…');
      final snapshot = await _storage.loadAll(visionEncoderId);

      int cachedCount = 0;
      Set<String> cachedIds = {};

      if (snapshot != null) {
        // Filter cache to only include images still on device
        final validCachedEmbeddings = <String, Float32List>{};
        final validCachedMetadata = <String, ImageItem>{};

        for (final image in imagesToProcess) {
          if (snapshot.embeddings.containsKey(image.id)) {
            validCachedEmbeddings[image.id] = snapshot.embeddings[image.id]!;
            validCachedMetadata[image.id] = image;
          }
        }

        if (validCachedEmbeddings.isNotEmpty) {
          _annSearch.restoreFromCache(validCachedEmbeddings, validCachedMetadata);
          cachedCount = validCachedEmbeddings.length;
          cachedIds = validCachedEmbeddings.keys.toSet();
        }
      }

      // ── Step 2: Find images that need embedding ──
      final newImages = imagesToProcess
          .where((img) => !cachedIds.contains(img.id))
          .toList();

      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════╗');
      debugPrint('║             IMAGE EMBEDDING IN PROGRESS             ║');
      debugPrint('╠══════════════════════════════════════════════════════╣');
      debugPrint('║ Backend:    ${_embeddingService.activeBackend.name}');
      debugPrint('║ Model:      ${_embeddingService.modelVersion.name}');
      debugPrint('║ Total imgs: ${imagesToProcess.length}');
      debugPrint('║ Cached:     $cachedCount (skipping)');
      debugPrint('║ New:        ${newImages.length} (to embed)');
      debugPrint('╚══════════════════════════════════════════════════════╝');
      debugPrint('');

      // If everything is cached, skip embedding entirely
      if (newImages.isEmpty && _annSearch.isReady) {
        debugPrint('');
        debugPrint('╔══════════════════════════════════════════════════════╗');
        debugPrint('║          EMBEDDINGS LOADED FROM STORAGE             ║');
        debugPrint('╠══════════════════════════════════════════════════════╣');
        debugPrint('║ Images:  $cachedCount');
        debugPrint('║ Encoder: $visionEncoderId');
        debugPrint('║ Search:  Brute-force cosine similarity');
        debugPrint('╚══════════════════════════════════════════════════════╝');
        debugPrint('');

        await _loadThumbnailsAndNotify(imagesToProcess);
        return;
      }

      // ── Step 3: Embed only new images ──
      // Acquire a partial wakelock so the CPU stays at full speed even when
      // the user backgrounds the app or the screen turns off.
      try { await WakelockPlus.enable(); } catch (_) {}

      final stopwatch = Stopwatch()..start();
      final newlyIndexed = <ImageItem>[];
      final newEmbeddings = <List<double>>[];
      int successCount = 0;
      int failedCount = 0;
      int lastCheckpointCount = 0;

      // Concurrency is bounded by per-isolate decode memory, NOT by ONNX
      // throughput. A 4032×3024 phone JPEG decodes to a ~48 MB RGBA buffer
      // inside compute() before the preprocessor resizes it; running that
      // in 10 isolates concurrently pushes ~500 MB of decode buffers on top
      // of the ~625 MB SigLIP model and OOMs Android. 5 keeps reasonable I/O
      // overlap; if an entire batch fails it is retried one-by-one before
      // counting images as permanently failed.
      const batchSize = 5;

      final failedImages = <ImageItem>[];

      Future<({ImageItem image, List<double> embedding, bool success})>
          embedOne(ImageItem image) async {
        try {
          final decoded = await _imageLoader.loadResizedForEmbedding(image.id);
          if (decoded != null) {
            final embedding = await _embeddingService
                .generateImageEmbeddingFromRgba(
                    decoded.rgba, decoded.width, decoded.height);
            return (image: image, embedding: embedding, success: true);
          }
        } catch (e) {
          debugPrint('ImageSearchService: Failed to embed ${image.id}: $e');
        }
        return (image: image, embedding: <double>[], success: false);
      }

      for (var batchStart = 0;
          batchStart < newImages.length;
          batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize).clamp(0, newImages.length);
        final batch = newImages.sublist(batchStart, batchEnd);

        final results =
            await Future.wait(batch.map(embedOne));

        // If the entire batch failed, retry each image individually to avoid
        // contention being the root cause of all failures.
        final allFailed = results.every((r) => !r.success);
        final effective = allFailed && batch.length > 1
            ? await Future.wait(batch.map(embedOne))
            : results;

        for (final result in effective) {
          if (result.success) {
            newlyIndexed.add(result.image);
            newEmbeddings.add(result.embedding);
            successCount++;
          } else {
            failedImages.add(result.image);
            failedCount++;
          }
        }

        // Progress bar
        final total = newImages.length;
        final percent = (batchEnd / total * 100).toStringAsFixed(1);
        final elapsedSec = stopwatch.elapsed.inSeconds;
        final avgMs = successCount > 0
            ? (stopwatch.elapsedMilliseconds / successCount).toStringAsFixed(0)
            : '?';
        final remaining = total - batchEnd;
        final etaSec = successCount > 0
            ? (remaining * stopwatch.elapsedMilliseconds / successCount / 1000)
                .toStringAsFixed(0)
            : '?';
        const barWidth = 20;
        final filled = (batchEnd / total * barWidth).round();
        final empty = barWidth - filled;
        final bar = '${'█' * filled}${'░' * empty}';

        debugPrint(
          'Embedding: [$bar] $percent%  ($successCount/$total)  '
          '${elapsedSec}s elapsed  ~${etaSec}s remaining  ${avgMs}ms/img',
        );
        _emitProgress(
          IndexingPhase.embedding,
          'Embedding images ($batchEnd/$total)…',
          done: batchEnd,
          total: total,
        );

        // Checkpoint: save every 100 newly embedded images so a background
        // kill or crash doesn't lose all progress.
        if (successCount - lastCheckpointCount >= 100) {
          lastCheckpointCount = successCount;
          await _annSearch.indexBatch(newlyIndexed, newEmbeddings);
          await _saveEmbeddingCache();
          debugPrint('ImageSearchService: Checkpoint saved at $successCount images');
        }
      }

      // If some images failed, pause and let the user decide whether to retry
      // or skip. A retry re-embeds the failed images one-by-one.
      if (failedCount > 0) {
        _embeddingFailureCompleter = Completer<bool>();
        _emitProgress(
          IndexingPhase.embeddingPartialFailure,
          '$failedCount image${failedCount == 1 ? '' : 's'} failed to embed',
          failedCount: failedCount,
          error: successCount == 0
              ? 'No images could be embedded — model may not be loaded correctly.'
              : null,
        );
        final retry = await _embeddingFailureCompleter!.future;
        _embeddingFailureCompleter = null;

        if (retry) {
          debugPrint('ImageSearchService: Retrying ${failedImages.length} failed images…');
          for (final image in failedImages) {
            final result = await embedOne(image);
            if (result.success) {
              newlyIndexed.add(result.image);
              newEmbeddings.add(result.embedding);
              successCount++;
              failedCount--;
            }
          }
        }
      }

      // Index the newly embedded images
      if (newlyIndexed.isNotEmpty) {
        await _annSearch.indexBatch(newlyIndexed, newEmbeddings);
      }

      stopwatch.stop();
      final avgTimeMs = successCount > 0
          ? (stopwatch.elapsedMilliseconds / successCount).toStringAsFixed(1)
          : '0';

      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════╗');
      debugPrint('║            EMBEDDING COMPLETE                       ║');
      debugPrint('╠══════════════════════════════════════════════════════╣');
      debugPrint('║ From cache:     $cachedCount');
      debugPrint('║ Newly embedded: $successCount');
      debugPrint('║ Failed/Skipped: $failedCount');
      debugPrint('║ Total indexed:  ${cachedCount + successCount}');
      debugPrint('║ Time (new):     ${stopwatch.elapsedMilliseconds}ms (${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
      debugPrint('║ Avg per image:  ${avgTimeMs}ms');
      debugPrint('╚══════════════════════════════════════════════════════╝');
      debugPrint('');

      // ── Step 4: Save cache ──
      await _saveEmbeddingCache();

      // ── Step 5: Load thumbnails and notify ──
      // Build the full list of indexed images (cached + new)
      final allIndexedImages = imagesToProcess
          .where((img) => cachedIds.contains(img.id) || newlyIndexed.any((n) => n.id == img.id))
          .toList();
      await _loadThumbnailsAndNotify(allIndexedImages);

    } catch (e) {
      debugPrint('ImageSearchService: Failed to index images: $e');
      rethrow;
    } finally {
      try { await WakelockPlus.disable(); } catch (_) {}
    }
  }

  /// Save current embeddings via the storage layer.
  Future<void> _saveEmbeddingCache() async {
    try {
      final visionEncoderId =
          _embeddingService.activeVariant?.visionEncoderId ?? 'unknown';
      final embeddings = _annSearch.imageEmbeddings;
      final metadata = _annSearch.imageMetadata;

      if (embeddings.isEmpty) return;

      final imagePaths = metadata.map((k, v) => MapEntry(k, v.path));

      _emitProgress(IndexingPhase.savingCache, 'Saving embeddings…');
      await _storage.saveAll(
        embeddings: Map<String, Float32List>.from(embeddings),
        imagePaths: imagePaths,
        visionEncoderId: visionEncoderId,
      );

      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════╗');
      debugPrint('║          EMBEDDINGS SAVED TO STORAGE                ║');
      debugPrint('╠══════════════════════════════════════════════════════╣');
      debugPrint('║ Images:  ${embeddings.length}');
      debugPrint('║ Encoder: $visionEncoderId');
      debugPrint('║ Search:  Brute-force cosine similarity');
      debugPrint('╚══════════════════════════════════════════════════════╝');
      debugPrint('');
    } catch (e) {
      debugPrint('ImageSearchService: Failed to save to storage: $e');
      // Non-fatal — next launch will just re-embed
    }
  }

  /// Notify listeners that the indexed image list is ready.
  /// Thumbnails are loaded lazily by the grid from [ImageItem.path].
  Future<void> _loadThumbnailsAndNotify(List<ImageItem> images) async {
    _loadedImages = images;
    _indexedCount = images.length;
    _imagesLoadedController.add(images);
    debugPrint('ImageSearchService: Gallery ready with ${images.length} images');
  }

  // ========== Model Management ==========

  /// Switch to a different model variant.
  ///
  /// Blocks (via the [indexingProgressStream]) until the new ONNX sessions are
  /// loaded and any missing image embeddings are ready. When the previous
  /// variant shared the same vision encoder as [variant], no re-embedding
  /// occurs — only the text-encoder session is swapped.
  ///
  /// Returns `true` if the switch succeeded.
  Future<bool> switchVariant(ModelVariant variant) async {
    if (!_isInitialized) {
      throw StateError('ImageSearchService not initialized');
    }

    final previousEncoder =
        _embeddingService.activeVariant?.visionEncoderId;

    _emitProgress(IndexingPhase.switchingVariant,
        'Switching to ${variant.displayName}…');

    final ok = await _embeddingService.switchToVariant(variant);
    if (!ok) {
      _emitProgress(IndexingPhase.error,
          'Failed to load ${variant.displayName}',
          error: 'Model files missing or unreadable');
      return false;
    }

    final newEncoder = variant.visionEncoderId;
    if (newEncoder != previousEncoder) {
      // Vision tower changed — drop the current in-memory ANN index and
      // rebuild from the new encoder's cache (or re-embed if empty).
      _annSearch.clearIndex();
      _indexedCount = 0;
      await _indexDeviceImages();
    }

    _emitProgress(IndexingPhase.ready, 'Switched to ${variant.displayName}');
    return true;
  }

  /// Delete cached embeddings for the currently active vision encoder.
  ///
  /// Useful for dev testing — forces the next startup/index pass to re-embed
  /// every image with the current model.
  Future<void> clearCurrentEncoderCache() async {
    final encoderId = _embeddingService.activeVariant?.visionEncoderId;
    if (encoderId == null) return;
    _annSearch.clearIndex();
    _indexedCount = 0;
    await _storage.clear(visionEncoderId: encoderId);
    debugPrint('ImageSearchService: Cleared cache for "$encoderId"');
  }

  /// Re-index all images with the current model
  ///
  /// Use this after switching models to regenerate all embeddings.
  /// This will take 2-3 minutes for 1000 images.
  Future<void> reindexAllImages() async {
    if (!_isInitialized) {
      throw StateError('ImageSearchService not initialized');
    }

    // Validate that a real model is loaded before wiping the index
    if (_embeddingService.activeBackend == EmbeddingBackend.mock) {
      throw StateError(
        'Cannot re-index with MOCK backend. No real model is loaded.',
      );
    }
    if (!_embeddingService.isImageReady) {
      throw StateError(
        'Image encoder not ready. Ensure model files are installed and loaded.',
      );
    }

    debugPrint('ImageSearchService: Re-indexing all images with current model...');
    debugPrint('ImageSearchService: Backend: ${_embeddingService.activeBackend.name}, '
        'Model: ${_embeddingService.modelVersion.name}');

    try {
      // Clear existing embeddings and disk cache
      _annSearch.clearIndex();
      _indexedCount = 0;
      await _storage.clear();

      // Re-index with current model (will embed all images fresh)
      await _indexDeviceImages();

      debugPrint('ImageSearchService: Re-indexing complete');
      debugPrint('ImageSearchService: Total images indexed: $_indexedCount');
    } catch (e) {
      debugPrint('ImageSearchService: Failed to re-index: $e');
      rethrow;
    }
  }
}
