import 'dart:typed_data';

import 'ann_types.dart';
import 'ann_algorithm.dart';

/// Abstract interface for all ANN index implementations.
/// 
/// This interface defines the contract that both HNSW and IVF-PQ
/// (and any future algorithms) must implement.
/// 
/// Design principles:
/// - Algorithm-agnostic: No implementation details leak through
/// - Testable: Easy to mock for unit testing
/// - Async-ready: All I/O operations are async
/// - Resource-aware: Explicit dispose for cleanup
abstract class AnnIndex {
  /// The algorithm type this index uses
  AnnAlgorithm get algorithm;

  /// The distance metric used for comparisons
  DistanceMetric get metric;

  /// The dimensionality of vectors in this index
  int get dimension;

  /// The number of vectors currently in the index
  int get size;

  /// Whether the index is ready for queries
  bool get isReady;

  /// Maximum capacity of the index (if applicable)
  int? get maxCapacity;

  /// Loads an index from a file path.
  /// 
  /// Throws [AnnIndexException] if loading fails.
  Future<void> load(String path);

  /// Saves the index to a file path.
  /// 
  /// Throws [AnnIndexException] if saving fails.
  Future<void> save(String path);

  /// Searches for the k nearest neighbors of the query vector.
  /// 
  /// [query] must have length equal to [dimension].
  /// [k] is the number of neighbors to return.
  /// 
  /// Returns results sorted by distance (closest first).
  /// Throws [AnnIndexException] if search fails.
  Future<List<AnnSearchResult>> search(Float32List query, int k);

  /// Adds a single vector to the index.
  /// 
  /// [vector] must have length equal to [dimension].
  /// [id] is the label/identifier for this vector.
  /// 
  /// Throws [AnnIndexException] if the operation fails.
  /// Throws [UnsupportedError] if the algorithm doesn't support updates.
  Future<void> addVector(Float32List vector, int id);

  /// Adds multiple vectors to the index in batch.
  /// 
  /// More efficient than calling [addVector] repeatedly.
  /// 
  /// Throws [AnnIndexException] if the operation fails.
  /// Throws [UnsupportedError] if the algorithm doesn't support updates.
  Future<void> addVectors(List<Float32List> vectors, List<int> ids);

  /// Releases all resources held by this index.
  /// 
  /// After calling dispose, the index is no longer usable.
  void dispose();
}

/// Exception thrown by ANN index operations
class AnnIndexException implements Exception {
  final String message;
  final String? details;
  final Object? cause;

  const AnnIndexException(this.message, {this.details, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer('AnnIndexException: $message');
    if (details != null) buffer.write(' ($details)');
    if (cause != null) buffer.write('\nCaused by: $cause');
    return buffer.toString();
  }
}

/// Mixin providing common functionality for ANN index implementations
mixin AnnIndexValidation {
  int get dimension;
  bool get isReady;

  /// Validates that a query vector has the correct dimension
  void validateQuery(Float32List query) {
    if (query.length != dimension) {
      throw AnnIndexException(
        'Query dimension mismatch',
        details: 'Expected $dimension, got ${query.length}',
      );
    }
  }

  /// Validates that the index is ready for operations
  void validateReady() {
    if (!isReady) {
      throw AnnIndexException('Index is not ready');
    }
  }

  /// Validates k parameter
  void validateK(int k) {
    if (k <= 0) {
      throw AnnIndexException('k must be positive', details: 'Got $k');
    }
  }
}
