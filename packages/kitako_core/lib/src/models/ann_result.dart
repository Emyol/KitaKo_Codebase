/// Represents a single ANN search result with ID and distance.
///
/// For Inner Product space with normalized vectors:
/// - distance = 1 - cosine_similarity
/// - similarity = 1 - distance = cosine_similarity
/// - Lower distance = more similar
class AnnResult {
  /// The ID of the matched item in the index
  final int id;

  /// The distance to the query vector
  ///
  /// For normalized vectors with Inner Product space:
  /// distance = 1 - cosine_similarity
  final double distance;

  const AnnResult({
    required this.id,
    required this.distance,
  });

  /// The similarity score (for normalized vectors)
  ///
  /// similarity = 1 - distance = cosine_similarity
  double get similarity => 1.0 - distance;

  /// Creates an AnnResult from raw search output
  factory AnnResult.fromRaw(int id, double distance) {
    return AnnResult(id: id, distance: distance);
  }

  @override
  String toString() =>
      'AnnResult(id: $id, similarity: ${similarity.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnResult &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          distance == other.distance;

  @override
  int get hashCode => id.hashCode ^ distance.hashCode;
}

/// Represents a batch of ANN search results
class AnnResultBatch {
  /// The query ID or index (for batch queries)
  final int queryIndex;

  /// The results for this query, sorted by similarity (highest first)
  final List<AnnResult> results;

  const AnnResultBatch({
    required this.queryIndex,
    required this.results,
  });

  /// The top result (most similar), or null if empty
  AnnResult? get topResult => results.isNotEmpty ? results.first : null;

  /// The IDs of all results
  List<int> get ids => results.map((r) => r.id).toList();

  /// The similarities of all results
  List<double> get similarities => results.map((r) => r.similarity).toList();

  @override
  String toString() =>
      'AnnResultBatch(query: $queryIndex, results: ${results.length})';
}
