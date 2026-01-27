import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kitako_ffi/kitako_ffi.dart';

import 'ann_client.dart';
import 'index_manager.dart';
import 'local_ann_client.dart';

/// High-level search result with optional metadata
class SearchResult {
  /// The ID of the matched item
  final int id;

  /// The distance to the query (lower = more similar)
  final double distance;

  /// Similarity score (1 - distance for normalized vectors)
  double get similarity => 1.0 - distance;

  /// Optional metadata associated with this result
  final Map<String, dynamic>? metadata;

  const SearchResult({
    required this.id,
    required this.distance,
    this.metadata,
  });

  @override
  String toString() =>
      'SearchResult(id: $id, similarity: ${similarity.toStringAsFixed(4)})';
}

/// High-level ANN search service for KitaKo.
///
/// This service provides:
/// - Automatic index loading and lifecycle management
/// - Easy-to-use search API
/// - Integration with metadata storage
/// - Configurable search parameters
///
/// Example:
/// ```dart
/// final service = AnnSearchService();
/// await service.initialize(
///   indexPath: '/path/to/index.bin',
///   config: AnnClientConfig.siglip768,
/// );
///
/// final results = await service.search(queryEmbedding, k: 10);
/// ```
class AnnSearchService {
  AnnClient? _client;
  IndexManager? _indexManager;

  bool _isInitialized = false;

  /// Whether the service is initialized and ready for queries
  bool get isInitialized => _isInitialized;

  /// The number of items in the loaded index
  int get indexSize => _client?.itemCount ?? 0;

  /// Default number of results to return
  int defaultK = 10;

  /// Default efSearch parameter (accuracy/speed tradeoff)
  int defaultEfSearch = 100;

  /// Minimum similarity threshold (results below this are filtered out)
  double? similarityThreshold;

  /// Initializes the search service with the given index.
  ///
  /// [indexPath] is the path to the HNSW index file.
  /// [config] specifies the index configuration (dimension, space type).
  Future<void> initialize({
    required String indexPath,
    AnnClientConfig config = AnnClientConfig.siglip768,
  }) async {
    if (_isInitialized) {
      debugPrint('AnnSearchService: Already initialized, reinitializing...');
      dispose();
    }

    try {
      debugPrint('AnnSearchService: Initializing with index: $indexPath');

      // Create the client
      _client = LocalAnnClient(config: config);

      // Load the index
      await _client!.loadIndex(indexPath);

      _isInitialized = true;
      defaultEfSearch = config.defaultEfSearch;

      debugPrint(
        'AnnSearchService: Initialized successfully. '
        'Index size: $indexSize items',
      );
    } catch (e) {
      debugPrint('AnnSearchService: Initialization failed: $e');
      _isInitialized = false;
      _client?.dispose();
      _client = null;
      rethrow;
    }
  }

  /// Initializes the service using an IndexManager for asset handling.
  ///
  /// This is the recommended method for Flutter apps where the index
  /// is bundled as an asset.
  Future<void> initializeWithManager({
    required IndexManager indexManager,
    AnnClientConfig config = AnnClientConfig.siglip768,
  }) async {
    _indexManager = indexManager;

    // Ensure the index is available on the file system
    final indexPath = await _indexManager!.getIndexPath();

    await initialize(indexPath: indexPath, config: config);
  }

  /// Searches for similar items to the query embedding.
  ///
  /// [query] is the embedding vector to search for.
  /// [k] is the number of results to return (default: [defaultK]).
  /// [efSearch] optionally overrides the search accuracy parameter.
  /// [threshold] optionally filters results below this similarity.
  ///
  /// Returns a list of [SearchResult] sorted by similarity (highest first).
  Future<List<SearchResult>> search(
    Float32List query, {
    int? k,
    int? efSearch,
    double? threshold,
  }) async {
    if (!_isInitialized || _client == null) {
      throw StateError(
        'AnnSearchService not initialized. Call initialize() first.',
      );
    }

    final effectiveK = k ?? defaultK;
    final effectiveThreshold = threshold ?? similarityThreshold;

    try {
      // Perform the search
      final results = await _client!.search(
        query,
        k: effectiveK,
        efSearch: efSearch ?? defaultEfSearch,
      );

      // Convert to SearchResult and optionally filter by threshold
      final searchResults = <SearchResult>[];
      for (final result in results) {
        final similarity = result.similarity;

        // Filter by threshold if specified
        if (effectiveThreshold != null && similarity < effectiveThreshold) {
          continue;
        }

        searchResults.add(SearchResult(
          id: result.id,
          distance: result.distance,
        ));
      }

      return searchResults;
    } catch (e) {
      debugPrint('AnnSearchService: Search failed: $e');
      rethrow;
    }
  }

  /// Searches and returns raw ANN results (IDs and distances).
  ///
  /// Use this for maximum performance when you don't need the
  /// [SearchResult] wrapper.
  Future<List<AnnSearchResult>> searchRaw(
    Float32List query, {
    int? k,
    int? efSearch,
  }) async {
    if (!_isInitialized || _client == null) {
      throw StateError(
        'AnnSearchService not initialized. Call initialize() first.',
      );
    }

    return _client!.search(
      query,
      k: k ?? defaultK,
      efSearch: efSearch ?? defaultEfSearch,
    );
  }

  /// Searches for similar items and returns IDs only.
  ///
  /// Efficient when you only need IDs to fetch metadata separately.
  Future<List<int>> searchIds(
    Float32List query, {
    int? k,
    int? efSearch,
  }) async {
    final results = await searchRaw(query, k: k, efSearch: efSearch);
    return results.map((r) => r.id).toList();
  }

  /// Releases all resources.
  void dispose() {
    _client?.dispose();
    _client = null;
    _isInitialized = false;
    debugPrint('AnnSearchService: Disposed');
  }
}
