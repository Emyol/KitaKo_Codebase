import 'dart:math' show sqrt;
import 'dart:typed_data';

/// Result from an ANN search operation
/// 
/// This is algorithm-agnostic and used by all implementations.
class AnnSearchResult {
  /// The ID/label of the matched item
  final int id;

  /// The distance/dissimilarity score (lower is better for most metrics)
  final double distance;

  const AnnSearchResult({
    required this.id,
    required this.distance,
  });

  @override
  String toString() => 'AnnSearchResult(id: $id, distance: $distance)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnSearchResult &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          distance == other.distance;

  @override
  int get hashCode => id.hashCode ^ distance.hashCode;
}

/// Distance/similarity metrics for vector comparison
enum DistanceMetric {
  /// Euclidean distance (L2 norm)
  /// Lower values = more similar
  l2,

  /// Inner product (dot product)
  /// Higher values = more similar (for normalized vectors)
  /// Note: We store 1-IP as distance so lower = more similar
  innerProduct,

  /// Cosine similarity (uses IP internally with normalization)
  /// Higher values = more similar
  cosine,
}

/// Extension for distance metric utilities
extension DistanceMetricExt on DistanceMetric {
  /// Whether vectors should be normalized for this metric
  bool get requiresNormalization {
    switch (this) {
      case DistanceMetric.l2:
        return false;
      case DistanceMetric.innerProduct:
        return false; // Recommended but not required
      case DistanceMetric.cosine:
        return true;
    }
  }

  /// Compute distance between two vectors
  double compute(Float32List a, Float32List b) {
    assert(a.length == b.length, 'Vector dimensions must match');
    
    switch (this) {
      case DistanceMetric.l2:
        return _l2Distance(a, b);
      case DistanceMetric.innerProduct:
        return _ipDistance(a, b);
      case DistanceMetric.cosine:
        return _cosineDistance(a, b);
    }
  }

  static double _l2Distance(Float32List a, Float32List b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sum; // Squared L2 for efficiency
  }

  static double _ipDistance(Float32List a, Float32List b) {
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return 1.0 - dot; // Convert similarity to distance
  }

  static double _cosineDistance(Float32List a, Float32List b) {
    double dot = 0;
    double normA = 0;
    double normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 1.0;
    return 1.0 - (dot / (sqrt(normA) * sqrt(normB)));
  }
}
