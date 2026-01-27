import 'dart:typed_data';

import 'package:kitako_ffi/kitako_ffi.dart';

/// Abstract interface for ANN (Approximate Nearest Neighbor) operations.
///
/// This interface allows for different implementations:
/// - [LocalAnnClient]: Native FFI-based HNSW implementation
/// - Future: Remote/server-based implementation
/// - Testing: Mock implementation
abstract class AnnClient {
  /// Whether the index is loaded and ready for queries
  bool get isLoaded;

  /// The embedding dimension the index was created with
  int get dimension;

  /// The number of items in the index
  int get itemCount;

  /// Loads an index from the specified path.
  ///
  /// Throws [StateError] if loading fails.
  Future<void> loadIndex(String indexPath);

  /// Searches for the k nearest neighbors of the query vector.
  ///
  /// [query] must have the same dimension as the index.
  /// [k] is the number of results to return.
  /// [efSearch] optionally overrides the search accuracy parameter.
  ///
  /// Returns results sorted by distance (closest first).
  Future<List<AnnSearchResult>> search(
    Float32List query, {
    required int k,
    int? efSearch,
  });

  /// Releases resources held by the client.
  void dispose();
}

/// Configuration for creating an ANN client
class AnnClientConfig {
  /// The embedding dimension (e.g., 768 for SigLIP)
  final int dimension;

  /// The distance metric to use
  final AnnSpaceType spaceType;

  /// Default efSearch value for queries (higher = more accurate but slower)
  final int defaultEfSearch;

  const AnnClientConfig({
    required this.dimension,
    this.spaceType = AnnSpaceType.innerProduct,
    this.defaultEfSearch = 100,
  });

  /// Default configuration for SigLIP-768 embeddings
  static const siglip768 = AnnClientConfig(
    dimension: 768,
    spaceType: AnnSpaceType.innerProduct, // Use IP for L2-normalized vectors
    defaultEfSearch: 100,
  );
}
