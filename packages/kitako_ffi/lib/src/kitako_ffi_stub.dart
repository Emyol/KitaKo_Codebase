import 'dart:typed_data';

// Stub implementation used on platforms that don't support dart:ffi (web).

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

/// Stub handle type for web
class _StubHandle {
  final int dim;
  final AnnSpaceType spaceType;
  final List<(int id, Float32List data)> items = [];

  _StubHandle(this.dim, this.spaceType);
}

/// Stub implementation for platforms without FFI support (web).
/// Provides a brute-force fallback for testing/development.
class KitakoFfi {
  final Map<int, _StubHandle> _handles = {};
  int _nextHandleId = 1;

  /// Whether ANN functions are available (always false for web stub)
  bool get isAnnAvailable => false;

  /// Returns a deterministic dummy embedding for platforms without FFI.
  Float32List dummyEmbedding768() {
    final out = Float32List(768);
    for (var i = 0; i < 768; i++) {
      out[i] = (i % 100) / 100.0;
    }
    return out;
  }

  // ==========================================================================
  // ANN Stub Implementation (brute-force for web)
  // ==========================================================================

  /// Creates a stub ANN handle.
  /// Returns a fake pointer (int cast to dynamic for type compatibility).
  dynamic annCreate(int dim, AnnSpaceType spaceType) {
    final handleId = _nextHandleId++;
    _handles[handleId] = _StubHandle(dim, spaceType);
    return handleId;
  }

  /// Stub load - does nothing on web (index must be built in memory).
  void annLoad(dynamic handle, String indexPath) {
    // Web stub: cannot load from file system
    // In a real web implementation, you might fetch from IndexedDB or network
    throw UnsupportedError(
      'ANN index loading is not supported on web. '
      'Use annInitIndex and annAddItem to build an in-memory index.',
    );
  }

  /// Brute-force search implementation for web.
  List<AnnSearchResult> annSearch(dynamic handle, Float32List query, int k) {
    final handleId = handle as int;
    final stub = _handles[handleId];
    if (stub == null) {
      throw StateError('Invalid handle');
    }

    if (stub.items.isEmpty) {
      return [];
    }

    // Compute distances to all items
    final distances = <(int id, double distance)>[];
    for (final item in stub.items) {
      final dist = _computeDistance(query, item.$2, stub.spaceType);
      distances.add((item.$1, dist));
    }

    // Sort by distance (ascending)
    distances.sort((a, b) => a.$2.compareTo(b.$2));

    // Return top k
    return distances
        .take(k)
        .map((d) => AnnSearchResult(id: d.$1, distance: d.$2))
        .toList();
  }

  double _computeDistance(Float32List a, Float32List b, AnnSpaceType space) {
    double result = 0.0;

    switch (space) {
      case AnnSpaceType.innerProduct:
      case AnnSpaceType.cosine:
        // Inner product distance = 1 - dot(a, b)
        for (int i = 0; i < a.length; i++) {
          result += a[i] * b[i];
        }
        return 1.0 - result;

      case AnnSpaceType.l2:
        // L2 squared distance
        for (int i = 0; i < a.length; i++) {
          final diff = a[i] - b[i];
          result += diff * diff;
        }
        return result;
    }
  }

  /// Gets the count of items in the stub index.
  int annGetCount(dynamic handle) {
    final handleId = handle as int;
    final stub = _handles[handleId];
    return stub?.items.length ?? -1;
  }

  /// Gets the dimension of the stub index.
  int annGetDim(dynamic handle) {
    final handleId = handle as int;
    final stub = _handles[handleId];
    return stub?.dim ?? -1;
  }

  /// Stub: ef parameter is ignored in brute-force search.
  void annSetEf(dynamic handle, int ef) {
    // No-op for brute force
  }

  /// Frees the stub handle.
  void annFree(dynamic handle) {
    final handleId = handle as int;
    _handles.remove(handleId);
  }

  /// Initializes an in-memory index for building.
  void annInitIndex(
    dynamic handle, {
    required int maxElements,
    int M = 16,
    int efConstruction = 200,
  }) {
    // Stub: already initialized on create
  }

  /// Adds an item to the in-memory index.
  void annAddItem(dynamic handle, Float32List data, int id) {
    final handleId = handle as int;
    final stub = _handles[handleId];
    if (stub == null) {
      throw StateError('Invalid handle');
    }

    // For cosine space, normalize the vector
    Float32List normalizedData = data;
    if (stub.spaceType == AnnSpaceType.cosine) {
      double norm = 0.0;
      for (int i = 0; i < data.length; i++) {
        norm += data[i] * data[i];
      }
      norm = _sqrt(norm);
      if (norm > 0) {
        normalizedData = Float32List(data.length);
        for (int i = 0; i < data.length; i++) {
          normalizedData[i] = data[i] / norm;
        }
      }
    }

    stub.items.add((id, Float32List.fromList(normalizedData)));
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  /// Stub: cannot save to file system on web.
  void annSave(dynamic handle, String indexPath) {
    throw UnsupportedError('ANN index saving is not supported on web.');
  }

  // Metrics API stubs

  /// Stub: returns item count (brute force = all items visited).
  int annGetDistanceComputations(dynamic handle) {
    final handleId = handle as int;
    final stub = _handles[handleId];
    return stub?.items.length ?? -1;
  }

  /// Stub: returns 0 hops (brute force has no graph traversal).
  int annGetHops(dynamic handle) => 0;

  /// Stub: no-op.
  void annResetMetrics(dynamic handle) {}

  /// Stub: returns -1 (no ef parameter in brute force).
  int annGetEf(dynamic handle) => -1;

  /// Stub: returns -1 (no graph levels in brute force).
  int annGetMaxLevel(dynamic handle) => -1;
}

