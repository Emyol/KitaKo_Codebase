import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';

// Conditional imports for non-web platforms
import 'ann_search_service_stub.dart'
    if (dart.library.io) 'ann_search_service_io.dart' as platform;

/// Service for Approximate Nearest Neighbor (ANN) search
///
/// This service wraps the kitako_ann package and provides:
/// - HNSW-based vector similarity search via native FFI
/// - Fallback to brute-force search when native isn't available
/// - Index management and lifecycle
///
/// Example usage:
/// ```dart
/// final annService = ANNSearchService();
/// await annService.initialize();
/// final results = await annService.searchSimilar(queryEmbedding, k: 10);
/// ```
class ANNSearchService {
  /// The real ANN search service from kitako_ann
  platform.AnnClientWrapper? _annClient;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Whether we're using native HNSW or fallback
  bool _usingNativeHnsw = false;

  /// Fallback: Index of image embeddings (brute-force)
  final Map<String, List<double>> _imageEmbeddings = {};

  /// Metadata for indexed images
  final Map<String, ImageItem> _imageMetadata = {};

  /// ID to index mapping for native HNSW
  final Map<int, String> _hnswIdToImageId = {};
  final Map<String, int> _imageIdToHnswId = {};
  int _nextHnswId = 0;

  /// Number of top results to return by default
  static const int defaultTopK = 30;

  /// Similarity threshold (0.0 to 1.0)
  static const double similarityThreshold = 0.3;

  /// Asset paths
  static const String _indexAsset = 'assets/index/ann_index.bin';

  /// Whether native HNSW is being used
  bool get usingNativeHnsw => _usingNativeHnsw;

  /// Initialize the ANN search service
  ///
  /// Attempts to load native HNSW index, falls back to brute-force if unavailable.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('ANNSearchService: Initializing...');

      // Check if native ANN is supported on this platform
      if (!platform.AnnPlatformHelper.isSupported) {
        debugPrint('ANNSearchService: Native not supported on this platform');
        _usingNativeHnsw = false;
      } else {
        // Try to load native HNSW index
        try {
          await _initializeNativeHnsw();
          _usingNativeHnsw = true;
          debugPrint('ANNSearchService: Using native HNSW index');
        } catch (e) {
          debugPrint('ANNSearchService: Native HNSW unavailable: $e');
          debugPrint('ANNSearchService: Using brute-force fallback');
          _usingNativeHnsw = false;
        }
      }

      _isInitialized = true;
      debugPrint('ANNSearchService: Initialized successfully (native: $_usingNativeHnsw)');
      return true;
    } catch (e) {
      debugPrint('ANNSearchService: Failed to initialize: $e');
      return false;
    }
  }

  /// Initialize native HNSW from bundled assets
  Future<void> _initializeNativeHnsw() async {
    // Copy index from assets to file system (native FFI needs file path)
    final indexPath = await platform.AnnPlatformHelper.copyAssetToFile(
      _indexAsset,
      'ann_index.bin',
    );

    // If no valid index file, skip native initialization
    if (indexPath == null) {
      throw StateError('No pre-built ANN index available');
    }

    _annClient = await platform.AnnPlatformHelper.createClient(
      indexPath: indexPath,
    );

    debugPrint('ANNSearchService: Loaded HNSW index with ${_annClient!.indexSize} items');
  }

  /// Index an image with its embedding
  Future<void> indexImage(ImageItem image, List<double> embedding) async {
    if (!_isInitialized) {
      throw StateError(
        'ANNSearchService not initialized. Call initialize() first.',
      );
    }

    // Store in local maps (for metadata lookup and brute-force fallback)
    _imageEmbeddings[image.id] = embedding;
    _imageMetadata[image.id] = image;

    // Map IDs for potential native HNSW use
    if (!_imageIdToHnswId.containsKey(image.id)) {
      _imageIdToHnswId[image.id] = _nextHnswId;
      _hnswIdToImageId[_nextHnswId] = image.id;
      _nextHnswId++;
    }

    debugPrint('ANNSearchService: Indexed image ${image.id}');
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
      await indexImage(images[i], embeddings[i]);
    }

    debugPrint('ANNSearchService: Indexed ${images.length} images');
  }

  /// Search for similar images
  ///
  /// Uses native HNSW if available, falls back to brute-force.
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

      if (_usingNativeHnsw && _annClient != null && _annClient!.indexSize > 0) {
        // Use native HNSW search
        results = await _searchNativeHnsw(queryEmbedding, k, effectiveThreshold);
      } else {
        // Fall back to brute-force
        results = _bruteForceSearch(queryEmbedding, k, effectiveThreshold);
      }

      stopwatch.stop();
      debugPrint(
        'ANNSearchService: Search completed in ${stopwatch.elapsedMilliseconds}ms, '
        'found ${results.length} results (native: $_usingNativeHnsw)',
      );

      return results;
    } catch (e) {
      debugPrint('ANNSearchService: Search failed: $e');
      // Fall back to brute force on error
      return _bruteForceSearch(queryEmbedding, k, effectiveThreshold);
    }
  }

  /// Search using native HNSW
  Future<List<ImageItem>> _searchNativeHnsw(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) async {
    final searchResults = await _annClient!.search(
      queryEmbedding,
      k: k,
      threshold: threshold,
    );

    final results = <ImageItem>[];
    for (final result in searchResults) {
      final imageId = _hnswIdToImageId[result.id];
      if (imageId != null && _imageMetadata.containsKey(imageId)) {
        results.add(_imageMetadata[imageId]!);
      }
    }

    return results;
  }

  /// Get the total number of indexed images
  int get indexSize => _imageMetadata.length;

  /// Get native index size
  int get nativeIndexSize => _annClient?.indexSize ?? 0;

  /// Check if an image is indexed
  bool isIndexed(String imageId) => _imageMetadata.containsKey(imageId);
q
  /// Get all indexed images
  List<ImageItem> getAllIndexedImages() {
    return _imageMetadata.values.toList();
  }

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
    _hnswIdToImageId.clear();
    _imageIdToHnswId.clear();
    _nextHnswId = 0;
    debugPrint('ANNSearchService: Index cleared');
  }

  /// Get index statistics
  Map<String, dynamic> getIndexStats() {
    return {
      'totalImages': _imageMetadata.length,
      'totalEmbeddings': _imageEmbeddings.length,
      'nativeIndexSize': _annClient?.indexSize ?? 0,
      'usingNativeHnsw': _usingNativeHnsw,
      'dimensionality': _imageEmbeddings.isEmpty
          ? 0
          : _imageEmbeddings.values.first.length,
    };
  }

  /// Dispose of resources
  void dispose() {
    _annClient?.dispose();
    _annClient = null;
    clearIndex();
    _isInitialized = false;
    debugPrint('ANNSearchService: Disposed');
  }

  // ========== Brute-Force Fallback ==========

  /// Brute force similarity search
  List<ImageItem> _bruteForceSearch(
    List<double> queryEmbedding,
    int k,
    double threshold,
  ) {
    debugPrint('ANNSearchService: Brute force search starting...');
    debugPrint('ANNSearchService: Query embedding length: ${queryEmbedding.length}');
    debugPrint('ANNSearchService: Indexed images: ${_imageEmbeddings.length}');
    debugPrint('ANNSearchService: Threshold: $threshold');
    
    final similarities = <String, double>{};
    double maxSimilarity = double.negativeInfinity;
    double minSimilarity = double.infinity;

    for (final entry in _imageEmbeddings.entries) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.value);
      if (similarity > maxSimilarity) maxSimilarity = similarity;
      if (similarity < minSimilarity) minSimilarity = similarity;
      
      // For testing: use threshold 0.0 to see all results
      if (similarity >= 0.0) {
        similarities[entry.key] = similarity;
      }
    }

    debugPrint('ANNSearchService: Similarity range: $minSimilarity to $maxSimilarity');
    debugPrint('ANNSearchService: Images passing threshold: ${similarities.length}');

    final sortedIds = similarities.keys.toList()
      ..sort((a, b) => similarities[b]!.compareTo(similarities[a]!));

    // Log top 5 similarities
    final top5 = sortedIds.take(5);
    for (final id in top5) {
      debugPrint('ANNSearchService: Top result: $id = ${similarities[id]}');
    }

    final topK = sortedIds.take(k);
    return topK.map((id) => _imageMetadata[id]!).toList();
  }

  /// Calculate cosine similarity between two vectors
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
