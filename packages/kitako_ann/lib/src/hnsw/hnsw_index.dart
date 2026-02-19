import 'dart:ffi' as ffi_dart show Pointer, Void;
import 'dart:typed_data';

import 'package:kitako_ffi/kitako_ffi.dart' as ffi;

import '../core/core.dart';

/// HNSW-based ANN index implementation using native FFI.
/// 
/// This implementation wraps the kitako_ffi package which provides
/// a C++ HNSW implementation via FFI.
class HnswAnnIndex extends AnnIndex with AnnIndexValidation {
  final HnswConfig _config;
  ffi.KitakoFfi? _ffi;
  ffi_dart.Pointer<ffi_dart.Void>? _handle;
  bool _isReady = false;
  int _size = 0;

  HnswAnnIndex({required HnswConfig config}) : _config = config {
    _config.validate();
  }

  /// Creates an HNSW index with default SigLIP-768 configuration
  factory HnswAnnIndex.siglip768({int maxElements = 100000}) {
    return HnswAnnIndex(config: HnswConfig.siglip768(maxElements: maxElements));
  }

  @override
  AnnAlgorithm get algorithm => AnnAlgorithm.hnsw;

  @override
  DistanceMetric get metric => _config.metric;

  @override
  int get dimension => _config.dimension;

  @override
  int get size => _size;

  @override
  bool get isReady => _isReady;

  @override
  int? get maxCapacity => _config.maxElements;

  /// The underlying FFI instance (for advanced usage)
  ffi.KitakoFfi? get ffiInstance => _ffi;

  /// Initializes the index for building (not loading from file)
  Future<void> initialize() async {
    if (_isReady) return;

    _ffi = ffi.KitakoFfi();
    if (!_ffi!.isAnnAvailable) {
      throw AnnIndexException(
        'HNSW native library not available',
        details: 'Ensure kitako_ffi is properly compiled with hnswlib',
      );
    }

    try {
      _handle = _ffi!.annCreate(
        _config.dimension,
        _metricToSpaceType(_config.metric),
      );

      _ffi!.annInitIndex(
        _handle!,
        maxElements: _config.maxElements,
        M: _config.m,
        efConstruction: _config.efConstruction,
      );

      _ffi!.annSetEf(_handle!, _config.efSearch);
      _isReady = true;
    } catch (e) {
      _cleanup();
      throw AnnIndexException('Failed to initialize HNSW index', cause: e);
    }
  }

  @override
  Future<void> load(String path) async {
    _ffi = ffi.KitakoFfi();
    if (!_ffi!.isAnnAvailable) {
      throw AnnIndexException('HNSW native library not available');
    }

    try {
      _handle = _ffi!.annCreate(
        _config.dimension,
        _metricToSpaceType(_config.metric),
      );

      _ffi!.annLoad(_handle!, path);
      _size = _ffi!.annGetCount(_handle!);
      _ffi!.annSetEf(_handle!, _config.efSearch);
      _isReady = true;
    } catch (e) {
      _cleanup();
      throw AnnIndexException('Failed to load HNSW index', details: path, cause: e);
    }
  }

  @override
  Future<void> save(String path) async {
    validateReady();
    try {
      _ffi!.annSave(_handle!, path);
    } catch (e) {
      throw AnnIndexException('Failed to save HNSW index', details: path, cause: e);
    }
  }

  @override
  Future<List<AnnSearchResult>> search(Float32List query, int k) async {
    validateReady();
    validateQuery(query);
    validateK(k);

    try {
      final results = _ffi!.annSearch(_handle!, query, k);
      return results
          .map((r) => AnnSearchResult(id: r.id, distance: r.distance))
          .toList();
    } catch (e) {
      throw AnnIndexException('Search failed', cause: e);
    }
  }

  @override
  Future<void> addVector(Float32List vector, int id) async {
    validateReady();
    if (vector.length != dimension) {
      throw AnnIndexException(
        'Vector dimension mismatch',
        details: 'Expected $dimension, got ${vector.length}',
      );
    }

    try {
      _ffi!.annAddItem(_handle!, vector, id);
      _size++;
    } catch (e) {
      throw AnnIndexException('Failed to add vector', cause: e);
    }
  }

  @override
  Future<void> addVectors(List<Float32List> vectors, List<int> ids) async {
    if (vectors.length != ids.length) {
      throw AnnIndexException(
        'Vectors and IDs count mismatch',
        details: 'Vectors: ${vectors.length}, IDs: ${ids.length}',
      );
    }

    for (int i = 0; i < vectors.length; i++) {
      await addVector(vectors[i], ids[i]);
    }
  }

  /// Sets the ef search parameter for query-time accuracy/speed tradeoff
  void setEfSearch(int ef) {
    if (_handle != null && _ffi != null) {
      _ffi!.annSetEf(_handle!, ef);
    }
  }

  /// Gets the current ef parameter value
  int getEfSearch() {
    if (_handle != null && _ffi != null) {
      return _ffi!.annGetEf(_handle!);
    }
    return -1;
  }

  /// Resets distance computation and hop counters to zero.
  /// Call before search to get per-search metrics.
  void resetMetrics() {
    if (_handle != null && _ffi != null) {
      _ffi!.annResetMetrics(_handle!);
    }
  }

  /// Gets the number of distance computations in the last search.
  /// Compare with [size] to see if HNSW is doing approximate search
  /// (distComps << size) or brute force (distComps >= size).
  int getDistanceComputations() {
    if (_handle != null && _ffi != null) {
      return _ffi!.annGetDistanceComputations(_handle!);
    }
    return -1;
  }

  /// Gets the number of graph hops in the last search.
  int getHops() {
    if (_handle != null && _ffi != null) {
      return _ffi!.annGetHops(_handle!);
    }
    return -1;
  }

  /// Gets the maximum level (number of layers) in the HNSW graph.
  int getMaxLevel() {
    if (_handle != null && _ffi != null) {
      return _ffi!.annGetMaxLevel(_handle!);
    }
    return -1;
  }

  /// Searches with metrics tracking and returns both results and metrics.
  Future<({List<AnnSearchResult> results, int distanceComputations, int hops, int efUsed})>
      searchWithMetrics(Float32List query, int k) async {
    validateReady();
    validateQuery(query);
    validateK(k);

    resetMetrics();
    final results = await search(query, k);
    final distComps = getDistanceComputations();
    final hops = getHops();
    final ef = getEfSearch();

    return (results: results, distanceComputations: distComps, hops: hops, efUsed: ef);
  }

  @override
  void dispose() {
    _cleanup();
  }

  void _cleanup() {
    if (_handle != null && _ffi != null) {
      try {
        _ffi!.annFree(_handle!);
      } catch (_) {}
    }
    _handle = null;
    _ffi = null;
    _isReady = false;
    _size = 0;
  }

  ffi.AnnSpaceType _metricToSpaceType(DistanceMetric metric) {
    switch (metric) {
      case DistanceMetric.l2:
        return ffi.AnnSpaceType.l2;
      case DistanceMetric.innerProduct:
        return ffi.AnnSpaceType.innerProduct;
      case DistanceMetric.cosine:
        return ffi.AnnSpaceType.cosine;
    }
  }
}
