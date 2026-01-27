/// Supported ANN algorithm types
enum AnnAlgorithm {
  /// Hierarchical Navigable Small World graph
  /// - Pros: Fast search, good recall, supports incremental updates
  /// - Cons: Higher memory usage, slower index building
  hnsw,

  /// Inverted File with Product Quantization
  /// - Pros: Lower memory usage, good for large-scale
  /// - Cons: Requires training, approximate distances
  ivfpq,
}

/// Extension for algorithm metadata
extension AnnAlgorithmExt on AnnAlgorithm {
  String get displayName {
    switch (this) {
      case AnnAlgorithm.hnsw:
        return 'HNSW';
      case AnnAlgorithm.ivfpq:
        return 'IVF-PQ';
    }
  }

  String get description {
    switch (this) {
      case AnnAlgorithm.hnsw:
        return 'Hierarchical Navigable Small World - Fast graph-based search';
      case AnnAlgorithm.ivfpq:
        return 'Inverted File with Product Quantization - Memory-efficient search';
    }
  }

  /// Whether this algorithm requires training data
  bool get requiresTraining {
    switch (this) {
      case AnnAlgorithm.hnsw:
        return false;
      case AnnAlgorithm.ivfpq:
        return true;
    }
  }

  /// Whether this algorithm supports incremental updates
  bool get supportsIncrementalUpdate {
    switch (this) {
      case AnnAlgorithm.hnsw:
        return true;
      case AnnAlgorithm.ivfpq:
        return false; // Would need re-training
    }
  }
}
