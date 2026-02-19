import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';
import '../models/search_models.dart';
import 'image_loader_service.dart';
import 'embedding_service.dart';
import 'embedding_storage_service.dart';
import 'ann_search_service.dart';

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

  /// Create a new ImageSearchService with optional custom services
  ///
  /// If services are not provided, default instances will be created.
  ImageSearchService({
    ImageLoaderService? imageLoader,
    EmbeddingService? embeddingService,
    ANNSearchService? annSearchService,
  }) : _imageLoader = imageLoader ?? ImageLoaderService(),
       _embeddingService = embeddingService ?? EmbeddingService(),
       _annSearch = annSearchService ?? ANNSearchService();

  // ========== State Management ==========

  /// Stream controller for search state updates
  final _searchStateController = StreamController<SearchState>.broadcast();

  /// Stream controller for image loading updates
  final _imagesLoadedController = StreamController<List<ImageItem>>.broadcast();

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

  // ========== Service Access (for Alpha Testing) ==========
  
  /// Access to image loader service (for alpha testing)
  ImageLoaderService get imageLoader => _imageLoader;
  
  /// Access to ANN search service (for alpha testing with brute force)
  ANNSearchService get annSearchService => _annSearch;

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
  /// For SigLIP embeddings, scores below ~0.05 are pure noise.
  double absoluteThreshold = 0.05;

  /// Relative cutoff: results must score at least this fraction of the
  /// top result's similarity. E.g. 0.4 means "at least 40% of the best match".
  /// Set to 0.0 to disable relative filtering.
  double relativeThreshold = 0.4;

  /// Whether to auto-index images on load
  bool autoIndex = true;

  // ========== Initialization ==========

  /// Initialize all services
  ///
  /// Must be called before using the search functionality.
  ///
  /// Returns `true` if all services initialized successfully
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('ImageSearchService: Initializing...');

      // Initialize loader and ANN (required)
      final loaderInit = await _imageLoader.initialize();
      final annInit = await _annSearch.initialize();

      if (!loaderInit || !annInit) {
        debugPrint('ImageSearchService: Loader or ANN failed to initialize');
        return false;
      }

      // Initialize embedding service EARLY (before slow thumbnail loading)
      // so it's ready when the user navigates to the alpha test screen.
      final embeddingInit = await _embeddingService.initialize();

      // Always load device images for gallery display
      final allImages = await _imageLoader.loadDeviceImages();
      if (allImages.isNotEmpty) {
        // Load thumbnails for gallery
        final imagesWithThumbs = <ImageItem>[];
        for (final image in allImages.take(1000)) {
          try {
            final withThumb = await _imageLoader.getImageWithThumbnail(image.id);
            imagesWithThumbs.add(withThumb);
          } catch (_) {
            imagesWithThumbs.add(image);
          }
        }
        _loadedImages = imagesWithThumbs;
        _imagesLoadedController.add(imagesWithThumbs);
        debugPrint('ImageSearchService: Loaded ${imagesWithThumbs.length} images for gallery');
      }

      _isInitialized = true;

      if (!embeddingInit) {
        debugPrint('ImageSearchService: Initialized WITHOUT embedding model. '
            'Install ONNX model files to enable search.');
        return true;
      }

      // Auto-index existing images if a real model is loaded
      if (autoIndex && _embeddingService.isImageReady) {
        await _indexDeviceImages();
      }

      debugPrint('ImageSearchService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('ImageSearchService: Initialization failed: $e');
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

      debugPrint('ImageSearchService: Searching for "$query"...');
      final stopwatch = Stopwatch()..start();

      // Step 1: Generate embedding for NORMALIZED query
      final queryEmbedding = await _embeddingService.generateEmbedding(normalizedQuery);

      // Step 2: Search with scores (no threshold — combo filter handles it)
      final scoredResults = await _annSearch.searchSimilarWithScores(
        queryEmbedding,
        k: k,
        threshold: -1.0,
        forceBruteForce: true,
      );

      // Step 3: Apply combo filter (absolute floor + relative cutoff)
      final filtered = _applyComboFilter(scoredResults);

      // Step 4: Load thumbnails for search results
      debugPrint('ImageSearchService: Loading thumbnails for ${filtered.length} results...');
      final imagesWithThumbnails = <ImageItem>[];
      final scores = <double>[];
      for (final result in filtered) {
        try {
          final imageWithThumb = await _imageLoader.getImageWithThumbnail(result.image.id);
          imagesWithThumbnails.add(imageWithThumb);
        } catch (e) {
          debugPrint('ImageSearchService: Failed to load thumbnail for ${result.image.id}: $e');
          imagesWithThumbnails.add(result.image);
        }
        scores.add(result.similarity);
      }

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Step 5: Update state with results
      if (imagesWithThumbnails.isEmpty) {
        _updateState(
          SearchState(
            status: SearchStatus.noResults,
            query: query,
            normalizedQuery: normalizedQuery,
            result: SearchResult(images: [], scores: [], query: query),
          ),
        );
      } else {
        _updateState(
          SearchState(
            status: SearchStatus.success,
            query: query,
            normalizedQuery: normalizedQuery,
            result: SearchResult(
              images: imagesWithThumbnails,
              scores: scores,
              query: query,
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

      // Step 2: Search with scores
      final scoredResults = await _annSearch.searchSimilarWithScores(
        queryEmbedding,
        k: k,
        threshold: -1.0,
        forceBruteForce: true,
      );

      // Step 3: Apply combo filter
      final filtered = _applyComboFilter(scoredResults);

      // Step 4: Load thumbnails for search results
      debugPrint('ImageSearchService: Loading thumbnails for ${filtered.length} results...');
      final imagesWithThumbnails = <ImageItem>[];
      final scores = <double>[];
      for (final result in filtered) {
        try {
          final imageWithThumb = await _imageLoader.getImageWithThumbnail(result.image.id);
          imagesWithThumbnails.add(imageWithThumb);
        } catch (e) {
          debugPrint('ImageSearchService: Failed to load thumbnail for ${result.image.id}: $e');
          imagesWithThumbnails.add(result.image);
        }
        scores.add(result.similarity);
      }

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

  // ========== Cleanup ==========

  /// Dispose of all resources
  void dispose() {
    _searchStateController.close();
    _imagesLoadedController.close();
    _imageLoader.dispose();
    _embeddingService.dispose();
    _annSearch.dispose();
    _isInitialized = false;
    debugPrint('ImageSearchService: Disposed');
  }

  // ========== Private Methods ==========

  /// Apply combo relevance filter: absolute floor + relative cutoff.
  ///
  /// 1. Discard any result with similarity < [absoluteThreshold] (noise floor).
  /// 2. Of the remaining, discard any result whose similarity is less than
  ///    [relativeThreshold] × (best result's similarity).
  ///
  /// The input list must already be sorted by similarity descending.
  List<SearchResultWithScore> _applyComboFilter(
    List<SearchResultWithScore> results,
  ) {
    if (results.isEmpty) return results;

    // Step 1: absolute floor — remove pure noise
    final aboveFloor = results
        .where((r) => r.similarity >= absoluteThreshold)
        .toList();

    if (aboveFloor.isEmpty) {
      debugPrint('ImageSearchService: Combo filter: all ${results.length} results '
          'below absolute floor ($absoluteThreshold)');
      return [];
    }

    // Step 2: relative cutoff — keep results within range of best match
    final bestScore = aboveFloor.first.similarity;
    final cutoff = bestScore * relativeThreshold;
    final filtered = aboveFloor
        .where((r) => r.similarity >= cutoff)
        .toList();

    debugPrint('ImageSearchService: Combo filter: '
        '${results.length} raw → ${aboveFloor.length} above floor ($absoluteThreshold) '
        '→ ${filtered.length} above relative cutoff '
        '(${(relativeThreshold * 100).toStringAsFixed(0)}% of best ${bestScore.toStringAsFixed(3)} = ${cutoff.toStringAsFixed(3)})');

    return filtered;
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

      const maxImagesToIndex = 1000;
      final imagesToProcess = allImages.take(maxImagesToIndex).toList();

      // ── Step 1: Try loading cached embeddings from storage layer ──
      final modelVariant = _embeddingService.activeVariant?.name ?? 'unknown';
      final snapshot = await _storage.loadAll(modelVariant);

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
        debugPrint('║ Model:   $modelVariant');
        debugPrint('║ Search:  Brute-force cosine similarity');
        debugPrint('╚══════════════════════════════════════════════════════╝');
        debugPrint('');

        await _loadThumbnailsAndNotify(imagesToProcess);
        return;
      }

      // ── Step 3: Embed only new images ──
      final stopwatch = Stopwatch()..start();
      final newlyIndexed = <ImageItem>[];
      final newEmbeddings = <List<double>>[];
      int successCount = 0;
      int failedCount = 0;

      const batchSize = 10;

      for (var batchStart = 0; batchStart < newImages.length; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize).clamp(0, newImages.length);
        final batch = newImages.sublist(batchStart, batchEnd);

        final futures = batch.map((image) async {
          try {
            final bytes = await _imageLoader.loadThumbnail(image.id);
            if (bytes != null && bytes.isNotEmpty) {
              final embedding = await _embeddingService.generateImageEmbedding(bytes);
              return (image: image, embedding: embedding, success: true);
            }
          } catch (e) {
            debugPrint('ImageSearchService: Failed to embed ${image.id}: $e');
          }
          return (image: image, embedding: <double>[], success: false);
        }).toList();

        final results = await Future.wait(futures);

        for (final result in results) {
          if (result.success) {
            newlyIndexed.add(result.image);
            newEmbeddings.add(result.embedding);
            successCount++;
          } else {
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
            ? (remaining * stopwatch.elapsedMilliseconds / successCount / 1000).toStringAsFixed(0)
            : '?';
        final barWidth = 20;
        final filled = (batchEnd / total * barWidth).round();
        final empty = barWidth - filled;
        final bar = '${'█' * filled}${'░' * empty}';

        debugPrint(
          'Embedding: [$bar] $percent%  ($successCount/$total)  '
          '${elapsedSec}s elapsed  ~${etaSec}s remaining  ${avgMs}ms/img',
        );
      }

      // Sanity check
      if (successCount == 0 && newImages.isNotEmpty) {
        throw StateError(
          'All ${newImages.length} new images failed to embed. '
          'The model may not be loaded correctly.',
        );
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
    }
  }

  /// Save current embeddings via the storage layer.
  Future<void> _saveEmbeddingCache() async {
    try {
      final modelVariant = _embeddingService.activeVariant?.name ?? 'unknown';
      final embeddings = _annSearch.imageEmbeddings;
      final metadata = _annSearch.imageMetadata;

      if (embeddings.isEmpty) return;

      final imagePaths = metadata.map((k, v) => MapEntry(k, v.path));

      await _storage.saveAll(
        embeddings: Map<String, Float32List>.from(embeddings),
        imagePaths: imagePaths,
        modelVariant: modelVariant,
      );

      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════╗');
      debugPrint('║          EMBEDDINGS SAVED TO STORAGE                ║');
      debugPrint('╠══════════════════════════════════════════════════════╣');
      debugPrint('║ Images:  ${embeddings.length}');
      debugPrint('║ Model:   $modelVariant');
      debugPrint('║ Search:  Brute-force cosine similarity');
      debugPrint('╚══════════════════════════════════════════════════════╝');
      debugPrint('');
    } catch (e) {
      debugPrint('ImageSearchService: Failed to save to storage: $e');
      // Non-fatal — next launch will just re-embed
    }
  }

  /// Load thumbnails for the given images and notify listeners.
  Future<void> _loadThumbnailsAndNotify(List<ImageItem> images) async {
    debugPrint('ImageSearchService: Loading thumbnails for ${images.length} images...');
    final imagesWithThumbnails = <ImageItem>[];
    for (final image in images) {
      try {
        final imageWithThumb = await _imageLoader.getImageWithThumbnail(image.id);
        imagesWithThumbnails.add(imageWithThumb);
      } catch (e) {
        debugPrint('ImageSearchService: Failed to load thumbnail for ${image.id}: $e');
        imagesWithThumbnails.add(image);
      }
    }

    _loadedImages = imagesWithThumbnails;
    _indexedCount = imagesWithThumbnails.length;
    _imagesLoadedController.add(imagesWithThumbnails);
    debugPrint('ImageSearchService: Gallery ready with ${imagesWithThumbnails.length} images');
  }

  // ========== Model Management ==========

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
