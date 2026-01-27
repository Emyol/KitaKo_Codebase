import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ============================================================================
// Native Type Definitions for Dummy Embed
// ============================================================================

typedef _NativeDummyEmbed = ffi.Void Function(
  ffi.Pointer<ffi.Float> out,
  ffi.Int32 outLen,
);
typedef _DartDummyEmbed = void Function(
  ffi.Pointer<ffi.Float> out,
  int outLen,
);

// ============================================================================
// Native Type Definitions for ANN
// ============================================================================

// kitako_ann_create(int32_t dim, int32_t space_type) -> void*
typedef _NativeAnnCreate = ffi.Pointer<ffi.Void> Function(
  ffi.Int32 dim,
  ffi.Int32 spaceType,
);
typedef _DartAnnCreate = ffi.Pointer<ffi.Void> Function(
  int dim,
  int spaceType,
);

// kitako_ann_load(void* handle, const char* index_path) -> int32_t
typedef _NativeAnnLoad = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<Utf8> indexPath,
);
typedef _DartAnnLoad = int Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<Utf8> indexPath,
);

// kitako_ann_search(handle, query, k, out_ids, out_distances) -> int32_t
typedef _NativeAnnSearch = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Float> query,
  ffi.Int32 k,
  ffi.Pointer<ffi.Int64> outIds,
  ffi.Pointer<ffi.Float> outDistances,
);
typedef _DartAnnSearch = int Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Float> query,
  int k,
  ffi.Pointer<ffi.Int64> outIds,
  ffi.Pointer<ffi.Float> outDistances,
);

// kitako_ann_get_count(handle) -> int64_t
typedef _NativeAnnGetCount = ffi.Int64 Function(ffi.Pointer<ffi.Void> handle);
typedef _DartAnnGetCount = int Function(ffi.Pointer<ffi.Void> handle);

// kitako_ann_get_dim(handle) -> int32_t
typedef _NativeAnnGetDim = ffi.Int32 Function(ffi.Pointer<ffi.Void> handle);
typedef _DartAnnGetDim = int Function(ffi.Pointer<ffi.Void> handle);

// kitako_ann_set_ef(handle, ef) -> int32_t
typedef _NativeAnnSetEf = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Int32 ef,
);
typedef _DartAnnSetEf = int Function(ffi.Pointer<ffi.Void> handle, int ef);

// kitako_ann_free(handle) -> void
typedef _NativeAnnFree = ffi.Void Function(ffi.Pointer<ffi.Void> handle);
typedef _DartAnnFree = void Function(ffi.Pointer<ffi.Void> handle);

// kitako_ann_get_error() -> const char*
typedef _NativeAnnGetError = ffi.Pointer<Utf8> Function();
typedef _DartAnnGetError = ffi.Pointer<Utf8> Function();

// Index building functions
typedef _NativeAnnInitIndex = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Int64 maxElements,
  ffi.Int32 M,
  ffi.Int32 efConstruction,
);
typedef _DartAnnInitIndex = int Function(
  ffi.Pointer<ffi.Void> handle,
  int maxElements,
  int M,
  int efConstruction,
);

typedef _NativeAnnAddItem = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Float> data,
  ffi.Int64 id,
);
typedef _DartAnnAddItem = int Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<ffi.Float> data,
  int id,
);

typedef _NativeAnnSave = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<Utf8> indexPath,
);
typedef _DartAnnSave = int Function(
  ffi.Pointer<ffi.Void> handle,
  ffi.Pointer<Utf8> indexPath,
);

// ============================================================================
// Space Types (matching C enum)
// ============================================================================

/// Distance space type for ANN index
enum AnnSpaceType {
  /// Inner Product (for L2-normalized vectors, IP distance = 1 - cosine similarity)
  innerProduct(0),

  /// Euclidean (L2) distance
  l2(1),

  /// Cosine similarity (normalizes vectors internally)
  cosine(2);

  final int value;
  const AnnSpaceType(this.value);
}

/// Error codes from ANN operations
enum AnnError {
  ok(0),
  nullHandle(1),
  io(2),
  invalidParam(3),
  notLoaded(4),
  internal(5);

  final int code;
  const AnnError(this.code);

  static AnnError fromCode(int code) {
    return AnnError.values.firstWhere(
      (e) => e.code == code,
      orElse: () => AnnError.internal,
    );
  }
}

// ============================================================================
// Search Result
// ============================================================================

/// Result from an ANN search query
class AnnSearchResult {
  /// The ID of the matched item
  final int id;

  /// The distance to the query (lower = more similar for IP space)
  final double distance;

  /// Similarity score (1 - distance for normalized vectors)
  double get similarity => 1.0 - distance;

  const AnnSearchResult({required this.id, required this.distance});

  @override
  String toString() => 'AnnSearchResult(id: $id, distance: $distance)';
}

// ============================================================================
// Main FFI Class
// ============================================================================

class KitakoFfi {
  late final ffi.DynamicLibrary _lib;

  // Dummy embed function
  late final _DartDummyEmbed _dummyEmbed;

  // ANN functions (nullable - may not be available if hnswlib not compiled)
  _DartAnnCreate? _annCreate;
  _DartAnnLoad? _annLoad;
  _DartAnnSearch? _annSearch;
  _DartAnnGetCount? _annGetCount;
  _DartAnnGetDim? _annGetDim;
  _DartAnnSetEf? _annSetEf;
  _DartAnnFree? _annFree;
  _DartAnnGetError? _annGetError;
  _DartAnnInitIndex? _annInitIndex;
  _DartAnnAddItem? _annAddItem;
  _DartAnnSave? _annSave;

  /// Whether ANN functions are available (hnswlib compiled in native library)
  bool get isAnnAvailable => _annCreate != null;

  KitakoFfi() {
    _lib = _loadLibrary();
    _bindFunctions();
  }

  ffi.DynamicLibrary _loadLibrary() {
    // Try platform-specific library first, then fall back to process() where
    // appropriate. This makes desktop dev runs less brittle.
    try {
      if (Platform.isAndroid) {
        return ffi.DynamicLibrary.open('libkitako_ffi.so');
      } else if (Platform.isWindows) {
        return ffi.DynamicLibrary.open('kitako_ffi.dll');
      } else if (Platform.isMacOS) {
        return ffi.DynamicLibrary.open('libkitako_ffi.dylib');
      } else if (Platform.isLinux) {
        return ffi.DynamicLibrary.open('libkitako_ffi.so');
      } else if (Platform.isIOS) {
        return ffi.DynamicLibrary.process();
      } else {
        return ffi.DynamicLibrary.process();
      }
    } catch (e) {
      // Fallback: try to use the process' symbols if available.
      try {
        return ffi.DynamicLibrary.process();
      } catch (_) {
        rethrow;
      }
    }
  }

  void _bindFunctions() {
    // Bind dummy embed (required)
    try {
      _dummyEmbed = _lib
          .lookup<ffi.NativeFunction<_NativeDummyEmbed>>('kitako_dummy_embed')
          .asFunction();
    } catch (e) {
      throw UnsupportedError(
        'Failed to locate native symbol "kitako_dummy_embed": $e',
      );
    }

    // Bind ANN functions (optional - may not be compiled)
    try {
      _annCreate = _lib
          .lookup<ffi.NativeFunction<_NativeAnnCreate>>('kitako_ann_create')
          .asFunction();

      _annLoad = _lib
          .lookup<ffi.NativeFunction<_NativeAnnLoad>>('kitako_ann_load')
          .asFunction();

      _annSearch = _lib
          .lookup<ffi.NativeFunction<_NativeAnnSearch>>('kitako_ann_search')
          .asFunction();

      _annGetCount = _lib
          .lookup<ffi.NativeFunction<_NativeAnnGetCount>>('kitako_ann_get_count')
          .asFunction();

      _annGetDim = _lib
          .lookup<ffi.NativeFunction<_NativeAnnGetDim>>('kitako_ann_get_dim')
          .asFunction();

      _annSetEf = _lib
          .lookup<ffi.NativeFunction<_NativeAnnSetEf>>('kitako_ann_set_ef')
          .asFunction();

      _annFree = _lib
          .lookup<ffi.NativeFunction<_NativeAnnFree>>('kitako_ann_free')
          .asFunction();

      _annGetError = _lib
          .lookup<ffi.NativeFunction<_NativeAnnGetError>>('kitako_ann_get_error')
          .asFunction();

      _annInitIndex = _lib
          .lookup<ffi.NativeFunction<_NativeAnnInitIndex>>('kitako_ann_init_index')
          .asFunction();

      _annAddItem = _lib
          .lookup<ffi.NativeFunction<_NativeAnnAddItem>>('kitako_ann_add_item')
          .asFunction();

      _annSave = _lib
          .lookup<ffi.NativeFunction<_NativeAnnSave>>('kitako_ann_save')
          .asFunction();
    } catch (e) {
      // ANN functions not available - hnswlib not compiled
      // This is OK for basic FFI testing
      _annCreate = null;
      _annLoad = null;
      _annSearch = null;
      _annGetCount = null;
      _annGetDim = null;
      _annSetEf = null;
      _annFree = null;
      _annGetError = null;
      _annInitIndex = null;
      _annAddItem = null;
      _annSave = null;
    }
  }

  // ==========================================================================
  // Dummy Embed (existing functionality)
  // ==========================================================================

  Float32List dummyEmbedding768() {
    final outPtr = calloc<ffi.Float>(768);
    try {
      _dummyEmbed(outPtr, 768);
      final view = outPtr.asTypedList(768);
      return Float32List.fromList(view);
    } finally {
      calloc.free(outPtr);
    }
  }

  // ==========================================================================
  // ANN Index Handle Management
  // ==========================================================================

  void _checkAnnAvailable() {
    if (!isAnnAvailable) {
      throw UnsupportedError(
        'ANN functions not available. Native library was compiled without hnswlib support.',
      );
    }
  }

  /// Creates a new ANN index handle.
  ///
  /// [dim] is the embedding dimension (e.g., 768 for SigLIP).
  /// [spaceType] determines the distance metric.
  ///
  /// Returns an opaque handle pointer, or throws on failure.
  ffi.Pointer<ffi.Void> annCreate(int dim, AnnSpaceType spaceType) {
    _checkAnnAvailable();
    final handle = _annCreate!(dim, spaceType.value);
    if (handle == ffi.nullptr) {
      throw StateError('Failed to create ANN index: ${_getLastError()}');
    }
    return handle;
  }

  /// Loads a pre-built HNSW index from the specified path.
  ///
  /// The index file must have been created with the same dimension
  /// and space type as this handle.
  void annLoad(ffi.Pointer<ffi.Void> handle, String indexPath) {
    _checkAnnAvailable();
    final pathPtr = indexPath.toNativeUtf8();
    try {
      final result = _annLoad!(handle, pathPtr);
      if (result != 0) {
        throw StateError(
          'Failed to load ANN index (error $result): ${_getLastError()}',
        );
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Searches for the k nearest neighbors of the query vector.
  ///
  /// Returns a list of [AnnSearchResult] sorted by distance (closest first).
  List<AnnSearchResult> annSearch(
    ffi.Pointer<ffi.Void> handle,
    Float32List query,
    int k,
  ) {
    _checkAnnAvailable();
    if (k <= 0) {
      throw ArgumentError('k must be positive');
    }

    // Allocate native buffers
    final queryPtr = calloc<ffi.Float>(query.length);
    final idsPtr = calloc<ffi.Int64>(k);
    final distancesPtr = calloc<ffi.Float>(k);

    try {
      // Copy query to native memory
      for (int i = 0; i < query.length; i++) {
        queryPtr[i] = query[i];
      }

      // Execute search
      final result = _annSearch!(handle, queryPtr, k, idsPtr, distancesPtr);
      if (result != 0) {
        throw StateError(
          'ANN search failed (error $result): ${_getLastError()}',
        );
      }

      // Extract results
      final results = <AnnSearchResult>[];
      for (int i = 0; i < k; i++) {
        final id = idsPtr[i];
        final distance = distancesPtr[i];

        // Skip invalid results (marked with id=-1)
        if (id >= 0) {
          results.add(AnnSearchResult(id: id, distance: distance));
        }
      }

      return results;
    } finally {
      calloc.free(queryPtr);
      calloc.free(idsPtr);
      calloc.free(distancesPtr);
    }
  }

  /// Gets the number of items in the loaded index.
  int annGetCount(ffi.Pointer<ffi.Void> handle) {
    _checkAnnAvailable();
    return _annGetCount!(handle);
  }

  /// Gets the embedding dimension of the index.
  int annGetDim(ffi.Pointer<ffi.Void> handle) {
    _checkAnnAvailable();
    return _annGetDim!(handle);
  }

  /// Sets the ef (search) parameter for query-time accuracy/speed tradeoff.
  ///
  /// Higher ef = more accurate but slower. Default is typically 50-200.
  void annSetEf(ffi.Pointer<ffi.Void> handle, int ef) {
    _checkAnnAvailable();
    final result = _annSetEf!(handle, ef);
    if (result != 0) {
      throw StateError('Failed to set ef: ${_getLastError()}');
    }
  }

  /// Frees all resources associated with the index handle.
  void annFree(ffi.Pointer<ffi.Void> handle) {
    _checkAnnAvailable();
    _annFree!(handle);
  }

  /// Gets the last error message (for debugging).
  String _getLastError() {
    if (_annGetError == null) return 'ANN not available';
    final errorPtr = _annGetError!();
    if (errorPtr == ffi.nullptr) {
      return 'Unknown error';
    }
    return errorPtr.toDartString();
  }

  // ==========================================================================
  // Index Building API
  // ==========================================================================

  /// Initializes an empty index for building.
  ///
  /// [maxElements] is the maximum capacity of the index.
  /// [M] is the HNSW M parameter (default: 16, higher = more accurate but slower).
  /// [efConstruction] is the construction ef (default: 200).
  void annInitIndex(
    ffi.Pointer<ffi.Void> handle, {
    required int maxElements,
    int M = 16,
    int efConstruction = 200,
  }) {
    _checkAnnAvailable();
    final result = _annInitIndex!(handle, maxElements, M, efConstruction);
    if (result != 0) {
      throw StateError('Failed to init index: ${_getLastError()}');
    }
  }

  /// Adds a single vector to the index with the given ID.
  void annAddItem(ffi.Pointer<ffi.Void> handle, Float32List data, int id) {
    _checkAnnAvailable();
    final dataPtr = calloc<ffi.Float>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        dataPtr[i] = data[i];
      }

      final result = _annAddItem!(handle, dataPtr, id);
      if (result != 0) {
        throw StateError('Failed to add item: ${_getLastError()}');
      }
    } finally {
      calloc.free(dataPtr);
    }
  }

  /// Saves the index to the specified path.
  void annSave(ffi.Pointer<ffi.Void> handle, String indexPath) {
    _checkAnnAvailable();
    final pathPtr = indexPath.toNativeUtf8();
    try {
      final result = _annSave!(handle, pathPtr);
      if (result != 0) {
        throw StateError('Failed to save index: ${_getLastError()}');
      }
    } finally {
      calloc.free(pathPtr);
    }
  }
}

