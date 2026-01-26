import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kitako_ffi/kitako_ffi.dart';

import 'ann_client.dart';

/// Local ANN client implementation using native HNSW via FFI.
///
/// This client provides fast on-device approximate nearest neighbor search
/// using the HNSW algorithm. It loads pre-built indexes from disk and
/// supports configurable accuracy/speed tradeoffs via the efSearch parameter.
///
/// Example:
/// ```dart
/// final client = LocalAnnClient(config: AnnClientConfig.siglip768);
/// await client.loadIndex('/path/to/index.bin');
///
/// final results = await client.search(queryEmbedding, k: 10);
/// for (final result in results) {
///   print('ID: ${result.id}, Similarity: ${result.similarity}');
/// }
///
/// client.dispose();
/// ```
class LocalAnnClient implements AnnClient {
  final AnnClientConfig config;
  final KitakoFfi _ffi;

  /// Native handle to the HNSW index (opaque pointer)
  ffi.Pointer<ffi.Void>? _handle;

  bool _isLoaded = false;

  /// Creates a new LocalAnnClient with the given configuration.
  ///
  /// The client is not ready until [loadIndex] is called.
  LocalAnnClient({
    required this.config,
    KitakoFfi? ffi,
  }) : _ffi = ffi ?? KitakoFfi() {
    // Create the native handle
    _handle = _ffi.annCreate(config.dimension, config.spaceType);
  }

  @override
  bool get isLoaded => _isLoaded;

  @override
  int get dimension => config.dimension;

  @override
  int get itemCount {
    if (_handle == null) return 0;
    final count = _ffi.annGetCount(_handle!);
    return count >= 0 ? count : 0;
  }

  @override
  Future<void> loadIndex(String indexPath) async {
    if (_handle == null) {
      throw StateError('Client has been disposed');
    }

    // Load index in a separate isolate for large files
    // For now, load synchronously (fast for pre-loaded indexes)
    try {
      debugPrint('LocalAnnClient: Loading index from $indexPath');
      _ffi.annLoad(_handle!, indexPath);
      _isLoaded = true;

      // Set default efSearch
      _ffi.annSetEf(_handle!, config.defaultEfSearch);

      debugPrint(
        'LocalAnnClient: Index loaded successfully. '
        'Items: $itemCount, Dim: ${_ffi.annGetDim(_handle!)}',
      );
    } catch (e) {
      _isLoaded = false;
      debugPrint('LocalAnnClient: Failed to load index: $e');
      rethrow;
    }
  }

  @override
  Future<List<AnnSearchResult>> search(
    Float32List query, {
    required int k,
    int? efSearch,
  }) async {
    if (_handle == null) {
      throw StateError('Client has been disposed');
    }

    if (!_isLoaded) {
      throw StateError('Index not loaded. Call loadIndex() first.');
    }

    if (query.length != config.dimension) {
      throw ArgumentError(
        'Query dimension (${query.length}) does not match '
        'index dimension (${config.dimension})',
      );
    }

    // Optionally set efSearch for this query
    if (efSearch != null) {
      _ffi.annSetEf(_handle!, efSearch);
    }

    try {
      // Perform the search
      final results = _ffi.annSearch(_handle!, query, k);

      // Reset efSearch to default if it was overridden
      if (efSearch != null) {
        _ffi.annSetEf(_handle!, config.defaultEfSearch);
      }

      return results;
    } catch (e) {
      debugPrint('LocalAnnClient: Search failed: $e');
      rethrow;
    }
  }

  /// Builds a new index from the given embeddings.
  ///
  /// This is typically done offline, but can be used for small indexes.
  ///
  /// [embeddings] is a map of ID -> embedding vector.
  /// [M] is the HNSW M parameter (default: 16).
  /// [efConstruction] is the construction accuracy (default: 200).
  Future<void> buildIndex(
    Map<int, Float32List> embeddings, {
    int M = 16,
    int efConstruction = 200,
  }) async {
    if (_handle == null) {
      throw StateError('Client has been disposed');
    }

    if (embeddings.isEmpty) {
      throw ArgumentError('Cannot build index with no embeddings');
    }

    // Validate dimensions
    for (final entry in embeddings.entries) {
      if (entry.value.length != config.dimension) {
        throw ArgumentError(
          'Embedding ${entry.key} has wrong dimension '
          '(${entry.value.length} vs ${config.dimension})',
        );
      }
    }

    debugPrint(
      'LocalAnnClient: Building index with ${embeddings.length} items '
      '(M=$M, efConstruction=$efConstruction)',
    );

    // Initialize the index
    _ffi.annInitIndex(
      _handle!,
      maxElements: embeddings.length,
      M: M,
      efConstruction: efConstruction,
    );

    // Add all items
    int count = 0;
    for (final entry in embeddings.entries) {
      _ffi.annAddItem(_handle!, entry.value, entry.key);
      count++;

      // Log progress for large indexes
      if (count % 1000 == 0) {
        debugPrint('LocalAnnClient: Added $count/${embeddings.length} items');
      }
    }

    _isLoaded = true;
    _ffi.annSetEf(_handle!, config.defaultEfSearch);

    debugPrint('LocalAnnClient: Index built successfully. Items: $itemCount');
  }

  /// Saves the current index to disk.
  Future<void> saveIndex(String indexPath) async {
    if (_handle == null) {
      throw StateError('Client has been disposed');
    }

    if (!_isLoaded) {
      throw StateError('No index to save. Build or load an index first.');
    }

    debugPrint('LocalAnnClient: Saving index to $indexPath');
    _ffi.annSave(_handle!, indexPath);
    debugPrint('LocalAnnClient: Index saved successfully');
  }

  @override
  void dispose() {
    if (_handle != null) {
      _ffi.annFree(_handle!);
      _handle = null;
      _isLoaded = false;
      debugPrint('LocalAnnClient: Disposed');
    }
  }
}
