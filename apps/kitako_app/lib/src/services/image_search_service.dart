import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';
import '../models/search_models.dart';
import 'image_loader_service.dart';
import 'embedding_service.dart';
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

  /// Current search state
  SearchState _currentState = const SearchState();

  /// Stream of search state changes
  Stream<SearchState> get searchStateStream => _searchStateController.stream;

  /// Current search state (read-only)
  SearchState get currentState => _currentState;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  // ========== Configuration ==========

  /// Number of top results to return
  int topK = 10;

  /// Minimum similarity score (0.0 to 1.0)
  double similarityThreshold = 0.5;

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

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      // Step 3: Update state with results
      if (matchingImages.isEmpty) {
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
            result: SearchResult(images: matchingImages, query: query),
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

  /// Get all loaded images
  List<ImageItem> getAllImages() {
    return _imageLoader.getAllImages();
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
    };
  }

  // ========== Cleanup ==========

  /// Dispose of all resources
  void dispose() {
    _searchStateController.close();
    _imageLoader.dispose();
    _embeddingService.dispose();
    _annSearch.dispose();
    _isInitialized = false;
    debugPrint('ImageSearchService: Disposed');
  }

  // ========== Private Methods ==========

  /// Update search state and notify listeners
  void _updateState(SearchState newState) {
    _currentState = newState;
    _searchStateController.add(newState);
  }

  /// Index all device images
  ///
  /// This is called automatically on initialization if autoIndex is true.
  /// You can also call this manually after loading new images.
  Future<void> _indexDeviceImages() async {
    try {
      final images = await _imageLoader.loadDeviceImages();

      if (images.isEmpty) {
        debugPrint('ImageSearchService: No images to index');
        return;
      }

      debugPrint('ImageSearchService: Indexing ${images.length} images...');
      final stopwatch = Stopwatch()..start();

      // TODO: Generate actual image embeddings
      // For now, generate random embeddings for mock implementation
      final embeddings = <List<double>>[];
      for (var i = 0; i < images.length; i++) {
        // In real implementation, this would:
        // 1. Load the image file
        // 2. Run it through the embedding model
        // 3. Get the feature vector

        // Mock: Generate random embedding (must match EmbeddingService dimension)
        final mockEmbedding = List.generate(
          EmbeddingService.embeddingDimension, // 768 for SigLIP
          (index) => (index * 0.01) % 1.0,
        );
        embeddings.add(mockEmbedding);
      }

      // Index all images
      await _annSearch.indexBatch(images, embeddings);

      stopwatch.stop();
      debugPrint(
        'ImageSearchService: Indexed ${images.length} images in ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('ImageSearchService: Failed to index images: $e');
      rethrow;
    }
  }
}
