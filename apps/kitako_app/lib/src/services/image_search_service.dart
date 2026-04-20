import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';
import '../models/search_models.dart';
import 'image_loader_service.dart';
import 'embedding_service.dart';
import 'ann_search_service.dart';
import 'face_service.dart';

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
  final TaglishNormalizer _normalizer = const TaglishNormalizer();

  /// Optional face recognition service.
  /// When null or unavailable, face features are silently disabled.
  final FaceService? _faceService;

  /// Create a new ImageSearchService with optional custom services
  ///
  /// If services are not provided, default instances will be created.
  /// [faceService] is fully optional — pass null to disable face features.
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

  /// Current search state
  SearchState _currentState = const SearchState();

  /// List of indexed images with thumbnails
  List<ImageItem> _indexedImages = [];

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

  /// Access to face service (may be null if face recognition is disabled)
  FaceService? get faceService => _faceService;

  /// Whether face recognition features are available
  bool get isFaceSearchAvailable => _faceService?.isAvailable ?? false;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  // ========== Configuration ==========

  /// Number of top results to return
  int topK = 20;

  /// Minimum similarity score - set very low to return results during debugging.
  /// For SigLIP, even good matches may only have similarity of 0.1-0.3.
  double similarityThreshold = -1.0;

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

      // Initialize all services
      final loaderInit = await _imageLoader.initialize();
      final embeddingInit = await _embeddingService.initialize();
      final annInit = await _annSearch.initialize();

      if (!loaderInit || !embeddingInit || !annInit) {
        debugPrint(
          'ImageSearchService: One or more services failed to initialize',
        );
        return false;
      }

      // Auto-index existing images if enabled
      if (autoIndex) {
        await _indexDeviceImages();
      }

      _isInitialized = true;
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
    double? threshold,
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
    final thresh = threshold ?? similarityThreshold;

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

      // Step 2: Search for similar images
      final matchingImages = await _annSearch.searchSimilar(
        queryEmbedding,
        k: k,
        threshold: thresh,
      );

      final imagesWithThumbnails = await _withThumbnails(matchingImages);

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Step 3: Update state with results
      if (imagesWithThumbnails.isEmpty) {
        _updateState(
          SearchState(
            status: SearchStatus.noResults,
            query: query,
            normalizedQuery: normalizedQuery,
            result: SearchResult(images: [], query: query),
          ),
        );
      } else {
        _updateState(
          SearchState(
            status: SearchStatus.success,
            query: query,
            normalizedQuery: normalizedQuery,
            result: SearchResult(images: imagesWithThumbnails, query: query),
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
    double? threshold,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'ImageSearchService not initialized. Call initialize() first.',
      );
    }

    final k = topK ?? this.topK;
    final thresh = threshold ?? similarityThreshold;

    try {
      // Update to searching state
      _updateState(const SearchState(
        status: SearchStatus.searching,
        query: '[Image Search]',
      ));

      debugPrint('ImageSearchService: Searching by image...');
      final stopwatch = Stopwatch()..start();

      // Step 1: Generate embedding for query image
      final queryEmbedding = await _embeddingService.generateImageEmbedding(
        Uint8List.fromList(imageBytes),
      );

      // Step 2: Search for similar images
      final matchingImages = await _annSearch.searchSimilar(
        queryEmbedding,
        k: k,
        threshold: thresh,
      );

      final imagesWithThumbnails = await _withThumbnails(matchingImages);

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Image search completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Step 3: Update state with results
      if (imagesWithThumbnails.isEmpty) {
        _updateState(
          const SearchState(
            status: SearchStatus.noResults,
            query: '[Image Search]',
            result: SearchResult(images: [], query: '[Image Search]'),
          ),
        );
      } else {
        _updateState(
          SearchState(
            status: SearchStatus.success,
            query: '[Image Search]',
            result: SearchResult(images: imagesWithThumbnails, query: '[Image Search]'),
          ),
        );
      }
    } catch (e) {
      debugPrint('ImageSearchService: Image search failed: $e');
      _updateState(
        SearchState(
          status: SearchStatus.error,
          query: '[Image Search]',
          error: e.toString(),
        ),
      );
    }
  }

  // ========== Face-Based Search ==========

  /// Search for images containing a named person.
  ///
  /// Uses the face recognition system to find images containing a
  /// person whose label matches [personLabel]. Falls back gracefully
  /// to empty results if face service is unavailable.
  ///
  /// Parameters:
  /// - [personLabel]: The name/label to search for
  Future<void> searchByPerson(String personLabel) async {
    if (!_isInitialized) {
      throw StateError('ImageSearchService not initialized');
    }

    final face = _faceService;
    if (face == null || !face.isAvailable) {
      debugPrint('ImageSearchService: Face search unavailable, returning empty');
      _updateState(SearchState(
        status: SearchStatus.noResults,
        query: '[Person: $personLabel]',
        result: SearchResult(images: [], query: '[Person: $personLabel]'),
      ));
      return;
    }

    try {
      _updateState(SearchState(
        status: SearchStatus.searching,
        query: '[Person: $personLabel]',
      ));

      final stopwatch = Stopwatch()..start();
      final imageIds = face.searchByPersonLabel(personLabel);

      // Resolve image IDs to ImageItems with thumbnails
      final results = <ImageItem>[];
      for (final id in imageIds) {
        try {
          final imageWithThumb = await _imageLoader.getImageWithThumbnail(id);
          results.add(imageWithThumb);
        } catch (e) {
          debugPrint('ImageSearchService: Failed to load image $id: $e');
        }
      }

      stopwatch.stop();
      debugPrint('ImageSearchService: Person search for "$personLabel" '
          'found ${results.length} images in ${stopwatch.elapsedMilliseconds}ms');

      if (results.isEmpty) {
        _updateState(SearchState(
          status: SearchStatus.noResults,
          query: '[Person: $personLabel]',
          result: SearchResult(images: [], query: '[Person: $personLabel]'),
        ));
      } else {
        _updateState(SearchState(
          status: SearchStatus.success,
          query: '[Person: $personLabel]',
          result: SearchResult(
            images: results,
            query: '[Person: $personLabel]',
            searchTimeMs: stopwatch.elapsedMilliseconds,
          ),
        ));
      }
    } catch (e) {
      debugPrint('ImageSearchService: Person search failed: $e');
      _updateState(SearchState(
        status: SearchStatus.error,
        query: '[Person: $personLabel]',
        error: e.toString(),
      ));
    }
  }

  /// Combined search: text query + optional face matching.
  ///
  /// 1. Performs standard SigLIP text search
  /// 2. If query looks like a person name and face service is available,
  ///    also searches by face label
  /// 3. Merges results (union), keeping text results ranked first
  Future<void> searchCombined(
    String query, {
    int? topK,
    double? threshold,
  }) async {
    if (!_isInitialized) {
      throw StateError('ImageSearchService not initialized');
    }

    if (query.trim().isEmpty) {
      _updateState(const SearchState());
      return;
    }

    // Always do the standard text search
    await searchImages(query, topK: topK, threshold: threshold);

    final face = _faceService;
    if (face != null && face.isAvailable) {
      try {
        final faceImageIds = face.searchByPersonLabel(query);

        if (faceImageIds.isNotEmpty) {
          // Load face-matched images
          final faceImages = <ImageItem>[];
          for (final id in faceImageIds) {
            try {
              final img = await _imageLoader.getImageWithThumbnail(id);
              faceImages.add(img);
            } catch (_) {}
          }

          if (faceImages.isNotEmpty) {
            // Face results go FIRST — then append any SigLIP results that
            // aren't already covered by the face match.
            final faceIds = faceImages.map((img) => img.id).toSet();
            final sigLipOnly = (_currentState.result?.images ?? <ImageItem>[])
                .where((img) => !faceIds.contains(img.id))
                .toList();

            _updateState(SearchState(
              status: SearchStatus.success,
              query: query,
              normalizedQuery: _currentState.normalizedQuery,
              result: SearchResult(
                images: [...faceImages, ...sigLipOnly],
                query: query,
              ),
            ));

            debugPrint('ImageSearchService: Combined search — '
                '${faceImages.length} face matches, '
                '${sigLipOnly.length} SigLIP-only results');
          }
        }
      } catch (e) {
        // Face search failure is non-fatal
        debugPrint('ImageSearchService: Face augmentation failed: $e');
      }
    }
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

  /// Get all indexed images with thumbnails
  List<ImageItem> getAllImages() {
    return _indexedImages;
  }

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
      'faceRecognition': _faceService?.getStats() ?? {'status': 'disabled'},
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
    _faceService?.dispose();
    _isInitialized = false;
    debugPrint('ImageSearchService: Disposed');
  }

  // ========== Private Methods ==========

  /// Resolves a list of images to versions with loaded thumbnails.
  /// Images that fail to load a thumbnail are kept as-is.
  Future<List<ImageItem>> _withThumbnails(List<ImageItem> images) async {
    final result = <ImageItem>[];
    for (final image in images) {
      try {
        result.add(await _imageLoader.getImageWithThumbnail(image.id));
      } catch (e) {
        debugPrint('ImageSearchService: Failed to load thumbnail for ${image.id}: $e');
        result.add(image);
      }
    }
    return result;
  }

  /// Update search state and notify listeners
  void _updateState(SearchState newState) {
    _currentState = newState;
    _searchStateController.add(newState);
  }

  /// Index all device images
  ///
  /// This is called automatically on initialization if autoIndex is true.
  /// You can also call this manually after loading new images.
  ///
  /// NOTE: Only images that successfully generate embeddings will be indexed.
  /// Images that fail or cannot be loaded will be skipped.
  Future<void> _indexDeviceImages() async {
    try {
      final allImages = await _imageLoader.loadDeviceImages();

      if (allImages.isEmpty) {
        debugPrint('ImageSearchService: No images to index');
        return;
      }

      if (!_embeddingService.isImageReady) {
        debugPrint('ImageSearchService: Image embedding not ready, skipping indexing');
        return;
      }

      debugPrint('ImageSearchService: Processing ${allImages.length} images for indexing...');
      final stopwatch = Stopwatch()..start();

      // Only index images that we can successfully embed
      final imagesToIndex = <ImageItem>[];
      final embeddings = <List<double>>[];
      int successCount = 0;
      int failedCount = 0;

      final imagesToProcess = allImages;

      // Process images in parallel batches for speed
      // Using thumbnails (200x200) instead of full images for faster loading
      const batchSize = 10; // Process 10 images concurrently

      for (var batchStart = 0; batchStart < imagesToProcess.length; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize).clamp(0, imagesToProcess.length);
        final batch = imagesToProcess.sublist(batchStart, batchEnd);

        // Process batch in parallel
        final futures = batch.map((image) async {
          try {
            // Use thumbnail instead of full image (200x200 vs 3000x4000 = 225x smaller)
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
            imagesToIndex.add(result.image);
            embeddings.add(result.embedding);
            successCount++;
          } else {
            failedCount++;
          }
        }

        // Progress update every batch
        debugPrint('ImageSearchService: Embedded $successCount/${imagesToProcess.length} images...');
      }

      // Index only successfully embedded images
      if (imagesToIndex.isNotEmpty) {
        await _annSearch.indexBatch(imagesToIndex, embeddings);
      }

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Indexed ${imagesToIndex.length} images in ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        'ImageSearchService: Successfully embedded: $successCount, Failed/Skipped: $failedCount',
      );

      final imagesWithThumbnails = await _withThumbnails(imagesToIndex);

      // Store indexed images and notify listeners
      _indexedImages = imagesWithThumbnails;
      _imagesLoadedController.add(imagesWithThumbnails);
      debugPrint('ImageSearchService: Gallery ready with ${imagesWithThumbnails.length} images with thumbnails');

      // Print summary of indexed images
      debugPrint('=== INDEXED IMAGES ===');
      debugPrint('Total images scanned: ${allImages.length}');
      debugPrint('Successfully indexed: ${imagesToIndex.length}');
      debugPrint('Failed/Skipped: $failedCount');
      if (imagesToIndex.length <= 50) {
        // Show first few if we have a small number
        for (var i = 0; i < imagesToIndex.length && i < 20; i++) {
          final img = imagesToIndex[i];
          debugPrint('  ${i + 1}. ID: ${img.id}, Path: ${img.path}');
        }
        if (imagesToIndex.length > 20) {
          debugPrint('  ... and ${imagesToIndex.length - 20} more');
        }
      }
      debugPrint('======================');

      // Face indexing (optional, non-blocking to main flow)
      await _indexFacesIfAvailable(imagesToIndex);
    } catch (e) {
      debugPrint('ImageSearchService: Failed to index images: $e');
      rethrow;
    }
  }

  /// Index faces in gallery images (optional, non-blocking).
  ///
  /// If the face service is not available, this is a no-op.
  /// Failures in face indexing do NOT affect the main search pipeline.
  Future<void> _indexFacesIfAvailable(List<ImageItem> images) async {
    final face = _faceService;
    if (face == null || !face.isAvailable) return;

    try {
      debugPrint('ImageSearchService: Starting face indexing for ${images.length} images...');
      final stopwatch = Stopwatch()..start();

      const batchSize = 10;
      int totalProcessed = 0;

      for (int start = 0; start < images.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, images.length);
        final batch = images.sublist(start, end);

        final entries = <MapEntry<String, Uint8List>>[];
        for (final image in batch) {
          try {
            final bytes = await _imageLoader.loadImageBytes(image.id);
            if (bytes != null && bytes.isNotEmpty) {
              entries.add(MapEntry(image.id, bytes));
            }
          } catch (_) {}
        }

        if (entries.isNotEmpty) {
          await face.indexImageBatch(entries);
        }

        totalProcessed += batch.length;
        if (totalProcessed % 100 == 0 || totalProcessed == images.length) {
          debugPrint('ImageSearchService: Face scan progress $totalProcessed/${images.length}');
        }

        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      face.finalizeClustering();

      stopwatch.stop();
      debugPrint('ImageSearchService: Face indexing complete in '
          '${stopwatch.elapsedMilliseconds}ms — '
          '${face.faceCount} faces, '
          '${face.personCount} persons');
    } catch (e) {
      // Face indexing failure is non-fatal
      debugPrint('ImageSearchService: Face indexing failed (non-fatal): $e');
    }
  }

  // ========== Model Management ==========

  /// Re-index all images with the current model
  ///
  /// Use this after switching models to regenerate all embeddings.
  /// This will take several minutes depending on dataset size.
  Future<void> reindexAllImages() async {
    if (!_isInitialized) {
      throw StateError('ImageSearchService not initialized');
    }

    debugPrint('ImageSearchService: Re-indexing all images with current model...');
    debugPrint('ImageSearchService: Current model: ${_embeddingService.modelVersion.name}');

    try {
      // Clear existing embeddings
      _annSearch.clearIndex();
      _indexedImages.clear();

      // Re-index with current model
      await _indexDeviceImages();

      debugPrint('ImageSearchService: Re-indexing complete');
      debugPrint('ImageSearchService: Total images indexed: ${_indexedImages.length}');
    } catch (e) {
      debugPrint('ImageSearchService: Failed to re-index: $e');
      rethrow;
    }
  }
}
