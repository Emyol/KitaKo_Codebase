import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kitako_core/kitako_core.dart';

/// DBSCAN (Density-Based Spatial Clustering of Applications with Noise)
/// implementation for grouping face embeddings into person clusters.
///
/// This is a pure Dart implementation — no external dependencies needed.
///
/// ## Why DBSCAN?
/// - No need to specify the number of people upfront
/// - Handles noise (outlier faces that don't match anyone)
/// - Works well with cosine distance on normalized embeddings
///
/// ## Parameters
/// - [eps]: Maximum cosine distance for two faces to be "same person"
///   (0.6 is a good default; lower = stricter)
/// - [minPoints]: Minimum faces to form a cluster
///   (2 = at least 2 photos of the same person)
///
/// ## Graceful Degradation
/// If clustering fails, it returns each face in its own cluster
/// (every face is an "unknown" person). The app still functions.
class FaceDbscan {
  /// Maximum cosine distance threshold for same-person grouping.
  final double eps;

  /// Minimum number of points to form a dense cluster.
  final int minPoints;

  const FaceDbscan({
    this.eps = kFaceClusteringThreshold,
    this.minPoints = kFaceClusteringMinPoints,
  });

  /// Cluster face embeddings into groups.
  ///
  /// Parameters:
  /// - [embeddings]: List of L2-normalized face embeddings (512-dim)
  /// - [faceIds]: Corresponding face IDs (same length as embeddings)
  ///
  /// Returns a map of cluster ID → list of face IDs.
  /// Cluster ID -1 is noise (unmatched faces).
  FaceClusterResult cluster(
    List<Float32List> embeddings,
    List<String> faceIds,
  ) {
    if (embeddings.length != faceIds.length) {
      throw const FaceClusteringException(
          'Embeddings and faceIds must have same length');
    }

    if (embeddings.isEmpty) {
      return const FaceClusterResult(
        clusterAssignments: {},
        clusters: {},
        noise: [],
      );
    }

    try {
      return _runDbscan(embeddings, faceIds);
    } catch (e) {
      debugPrint('FaceDbscan: Clustering failed, returning all as noise: $e');
      // Graceful fallback: every face is noise
      return FaceClusterResult(
        clusterAssignments: {for (final id in faceIds) id: -1},
        clusters: {},
        noise: List<String>.from(faceIds),
      );
    }
  }

  /// Core DBSCAN algorithm.
  FaceClusterResult _runDbscan(
    List<Float32List> embeddings,
    List<String> faceIds,
  ) {
    final n = embeddings.length;
    final labels = List<int>.filled(n, -2); // -2 = unvisited, -1 = noise
    int currentCluster = 0;

    // Pre-compute pairwise distances (for small N this is fine;
    // for large N, use HNSW-accelerated neighbor lookups)
    late final List<List<int>> neighborhoods;
    if (n <= 5000) {
      neighborhoods = _precomputeNeighborhoods(embeddings);
    } else {
      // For very large sets, compute neighbors on-the-fly
      neighborhoods = List.generate(n, (_) => <int>[]);
    }

    for (int i = 0; i < n; i++) {
      if (labels[i] != -2) continue; // Already visited

      final neighbors = n <= 5000
          ? neighborhoods[i]
          : _getNeighbors(embeddings, i);

      if (neighbors.length < minPoints) {
        labels[i] = -1; // Mark as noise
        continue;
      }

      // Start a new cluster
      labels[i] = currentCluster;

      // Expand cluster
      final seedSet = List<int>.from(neighbors);
      final seedSeen = Set<int>.from(neighbors);
      int seedIdx = 0;

      while (seedIdx < seedSet.length) {
        final q = seedSet[seedIdx];
        seedIdx++;

        if (labels[q] == -1) {
          labels[q] = currentCluster; // Noise becomes border point
        }
        if (labels[q] != -2) continue; // Already processed

        labels[q] = currentCluster;

        final qNeighbors = n <= 5000
            ? neighborhoods[q]
            : _getNeighbors(embeddings, q);

        if (qNeighbors.length >= minPoints) {
          for (final neighbor in qNeighbors) {
            if (!seedSeen.contains(neighbor)) {
              seedSeen.add(neighbor);
              seedSet.add(neighbor);
            }
          }
        }
      }

      currentCluster++;
    }

    // Build result
    final clusterAssignments = <String, int>{};
    final clusters = <int, List<String>>{};
    final noise = <String>[];

    for (int i = 0; i < n; i++) {
      final label = labels[i];
      clusterAssignments[faceIds[i]] = label;

      if (label == -1) {
        noise.add(faceIds[i]);
      } else {
        clusters.putIfAbsent(label, () => []).add(faceIds[i]);
      }
    }

    debugPrint('FaceDbscan: Found ${clusters.length} clusters, '
        '${noise.length} noise points from $n faces');

    return FaceClusterResult(
      clusterAssignments: clusterAssignments,
      clusters: clusters,
      noise: noise,
    );
  }

  /// Pre-compute all neighborhoods (for N <= 5000).
  List<List<int>> _precomputeNeighborhoods(List<Float32List> embeddings) {
    final n = embeddings.length;
    final neighborhoods = List.generate(n, (_) => <int>[]);

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final dist = _cosineDistance(embeddings[i], embeddings[j]);
        if (dist <= eps) {
          neighborhoods[i].add(j);
          neighborhoods[j].add(i);
        }
      }
    }

    return neighborhoods;
  }

  /// Get neighbors of point [idx] within eps distance.
  List<int> _getNeighbors(List<Float32List> embeddings, int idx) {
    final neighbors = <int>[];
    final target = embeddings[idx];

    for (int j = 0; j < embeddings.length; j++) {
      if (j == idx) continue;
      if (_cosineDistance(target, embeddings[j]) <= eps) {
        neighbors.add(j);
      }
    }

    return neighbors;
  }

  /// Cosine distance between two L2-normalized vectors.
  ///
  /// For normalized vectors: cosine_distance = 1 - dot_product
  double _cosineDistance(Float32List a, Float32List b) {
    double dot = 0.0;
    final len = math.min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return 1.0 - dot;
  }

  /// Compute the centroid (mean) embedding for a cluster.
  ///
  /// Returns an L2-normalized centroid.
  static Float32List computeCentroid(List<Float32List> embeddings) {
    if (embeddings.isEmpty) return Float32List(0);
    if (embeddings.length == 1) return embeddings.first;

    final dim = embeddings.first.length;
    final centroid = Float32List(dim);

    for (final emb in embeddings) {
      for (int i = 0; i < dim; i++) {
        centroid[i] += emb[i];
      }
    }

    // Average
    for (int i = 0; i < dim; i++) {
      centroid[i] /= embeddings.length;
    }

    // L2 normalize
    double norm = 0.0;
    for (final v in centroid) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < dim; i++) {
        centroid[i] /= norm;
      }
    }

    return centroid;
  }
}

/// Result of face clustering.
class FaceClusterResult {
  /// Map of faceId → cluster label (-1 = noise, >=0 = cluster)
  final Map<String, int> clusterAssignments;

  /// Map of cluster label → list of face IDs in that cluster
  final Map<int, List<String>> clusters;

  /// Face IDs classified as noise (not belonging to any cluster)
  final List<String> noise;

  const FaceClusterResult({
    required this.clusterAssignments,
    required this.clusters,
    required this.noise,
  });

  /// Number of identified person clusters
  int get clusterCount => clusters.length;

  /// Total number of clustered faces (excluding noise)
  int get clusteredFaceCount =>
      clusters.values.fold(0, (sum, list) => sum + list.length);

  @override
  String toString() =>
      'FaceClusterResult(clusters: $clusterCount, noise: ${noise.length})';
}
