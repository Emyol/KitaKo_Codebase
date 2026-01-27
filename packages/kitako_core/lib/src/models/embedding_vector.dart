import 'dart:math' as math;
import 'dart:typed_data';

/// Represents an embedding vector with utility methods.
///
/// Wraps a Float32List with common operations for similarity computation.
class EmbeddingVector {
  /// The raw embedding data
  final Float32List data;

  /// The dimension of this embedding
  int get dimension => data.length;

  const EmbeddingVector(this.data);

  /// Creates an embedding vector from a list of doubles
  factory EmbeddingVector.fromList(List<double> values) {
    return EmbeddingVector(Float32List.fromList(values));
  }

  /// Creates a zero vector of the given dimension
  factory EmbeddingVector.zeros(int dimension) {
    return EmbeddingVector(Float32List(dimension));
  }

  /// Creates a random normalized vector (for testing)
  factory EmbeddingVector.random(int dimension) {
    final random = math.Random();
    final data = Float32List(dimension);
    
    double norm = 0.0;
    for (int i = 0; i < dimension; i++) {
      data[i] = random.nextDouble() * 2 - 1; // Range [-1, 1]
      norm += data[i] * data[i];
    }
    
    // Normalize
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < dimension; i++) {
        data[i] /= norm;
      }
    }
    
    return EmbeddingVector(data);
  }

  /// Returns the L2 norm (magnitude) of this vector
  double get norm {
    double sum = 0.0;
    for (final value in data) {
      sum += value * value;
    }
    return math.sqrt(sum);
  }

  /// Returns whether this vector is L2-normalized (norm ≈ 1)
  bool get isNormalized {
    final n = norm;
    return (n - 1.0).abs() < 0.001;
  }

  /// Returns a new L2-normalized version of this vector
  EmbeddingVector normalized() {
    final n = norm;
    if (n == 0) return this;
    
    final result = Float32List(dimension);
    for (int i = 0; i < dimension; i++) {
      result[i] = data[i] / n;
    }
    return EmbeddingVector(result);
  }

  /// Computes the dot product with another vector
  double dot(EmbeddingVector other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Dimension mismatch: $dimension vs ${other.dimension}');
    }
    
    double sum = 0.0;
    for (int i = 0; i < dimension; i++) {
      sum += data[i] * other.data[i];
    }
    return sum;
  }

  /// Computes cosine similarity with another vector
  ///
  /// Returns a value between -1 and 1, where 1 means identical direction.
  double cosineSimilarity(EmbeddingVector other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Dimension mismatch: $dimension vs ${other.dimension}');
    }
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < dimension; i++) {
      dotProduct += data[i] * other.data[i];
      normA += data[i] * data[i];
      normB += other.data[i] * other.data[i];
    }
    
    if (normA == 0 || normB == 0) return 0.0;
    
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  /// Computes Euclidean (L2) distance to another vector
  double l2Distance(EmbeddingVector other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Dimension mismatch: $dimension vs ${other.dimension}');
    }
    
    double sum = 0.0;
    for (int i = 0; i < dimension; i++) {
      final diff = data[i] - other.data[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  /// Computes Inner Product distance (for normalized vectors, this = 1 - cosine)
  double ipDistance(EmbeddingVector other) {
    return 1.0 - dot(other);
  }

  /// Element-wise addition
  EmbeddingVector operator +(EmbeddingVector other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Dimension mismatch');
    }
    
    final result = Float32List(dimension);
    for (int i = 0; i < dimension; i++) {
      result[i] = data[i] + other.data[i];
    }
    return EmbeddingVector(result);
  }

  /// Scalar multiplication
  EmbeddingVector operator *(double scalar) {
    final result = Float32List(dimension);
    for (int i = 0; i < dimension; i++) {
      result[i] = data[i] * scalar;
    }
    return EmbeddingVector(result);
  }

  @override
  String toString() =>
      'EmbeddingVector(dim: $dimension, norm: ${norm.toStringAsFixed(4)})';
}

/// Extension to convert Float32List to EmbeddingVector
extension Float32ListEmbedding on Float32List {
  EmbeddingVector toEmbedding() => EmbeddingVector(this);
}
