import 'dart:math';
import 'dart:typed_data';

/// K-means clustering algorithm for training quantizers
/// 
/// This is a pure Dart implementation optimized for the IVF-PQ use case.
class KMeans {
  final int numClusters;
  final int maxIterations;
  final double tolerance;
  final Random _random;

  /// Cluster centroids after training [numClusters x dimension]
  List<Float32List>? _centroids;

  KMeans({
    required this.numClusters,
    this.maxIterations = 25,
    this.tolerance = 1e-4,
    int? seed,
  }) : _random = Random(seed ?? DateTime.now().millisecondsSinceEpoch);

  /// The trained centroids
  List<Float32List>? get centroids => _centroids;

  /// Whether the model has been trained
  bool get isTrained => _centroids != null;

  /// Trains the k-means model on the provided data
  /// 
  /// [data] is a list of vectors, each with the same dimension.
  /// Returns the final inertia (sum of squared distances to centroids).
  double train(List<Float32List> data) {
    if (data.isEmpty) {
      throw ArgumentError('Training data cannot be empty');
    }
    if (data.length < numClusters) {
      throw ArgumentError(
        'Need at least $numClusters samples, got ${data.length}',
      );
    }

    final dimension = data[0].length;
    
    // Initialize centroids using k-means++ initialization
    _centroids = _initializeCentroidsPlusPlus(data, dimension);

    double previousInertia = double.infinity;
    
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      // Assignment step: assign each point to nearest centroid
      final assignments = List<int>.filled(data.length, 0);
      final clusterSizes = List<int>.filled(numClusters, 0);
      
      for (int i = 0; i < data.length; i++) {
        assignments[i] = _findNearestCentroid(data[i]);
        clusterSizes[assignments[i]]++;
      }

      // Update step: compute new centroids
      final newCentroids = List.generate(
        numClusters,
        (_) => Float32List(dimension),
      );

      for (int i = 0; i < data.length; i++) {
        final cluster = assignments[i];
        for (int d = 0; d < dimension; d++) {
          newCentroids[cluster][d] += data[i][d];
        }
      }

      // Divide by cluster size to get mean
      for (int c = 0; c < numClusters; c++) {
        if (clusterSizes[c] > 0) {
          for (int d = 0; d < dimension; d++) {
            newCentroids[c][d] /= clusterSizes[c];
          }
        } else {
          // Empty cluster: reinitialize to random point
          final randomIdx = _random.nextInt(data.length);
          newCentroids[c] = Float32List.fromList(data[randomIdx]);
        }
      }

      // Compute inertia
      double inertia = 0;
      for (int i = 0; i < data.length; i++) {
        inertia += _squaredDistance(data[i], newCentroids[assignments[i]]);
      }

      _centroids = newCentroids;

      // Check convergence
      if ((previousInertia - inertia).abs() < tolerance * previousInertia) {
        break;
      }
      previousInertia = inertia;
    }

    return previousInertia;
  }

  /// Finds the index of the nearest centroid for a given vector
  int predict(Float32List vector) {
    if (!isTrained) {
      throw StateError('Model must be trained before prediction');
    }
    return _findNearestCentroid(vector);
  }

  /// Finds the indices of the k nearest centroids
  List<int> predictTopK(Float32List vector, int k) {
    if (!isTrained) {
      throw StateError('Model must be trained before prediction');
    }
    
    final distances = <MapEntry<int, double>>[];
    for (int c = 0; c < numClusters; c++) {
      distances.add(MapEntry(c, _squaredDistance(vector, _centroids![c])));
    }
    
    distances.sort((a, b) => a.value.compareTo(b.value));
    return distances.take(k).map((e) => e.key).toList();
  }

  /// K-means++ initialization for better initial centroids
  List<Float32List> _initializeCentroidsPlusPlus(
    List<Float32List> data,
    int dimension,
  ) {
    final centroids = <Float32List>[];
    
    // First centroid: random point
    centroids.add(Float32List.fromList(data[_random.nextInt(data.length)]));

    // Remaining centroids: weighted by squared distance to nearest centroid
    final distances = List<double>.filled(data.length, double.infinity);
    
    for (int c = 1; c < numClusters; c++) {
      // Update distances to nearest centroid
      double totalDist = 0;
      for (int i = 0; i < data.length; i++) {
        final dist = _squaredDistance(data[i], centroids.last);
        if (dist < distances[i]) {
          distances[i] = dist;
        }
        totalDist += distances[i];
      }

      // Sample proportional to squared distance
      double target = _random.nextDouble() * totalDist;
      double cumulative = 0;
      int selectedIdx = 0;
      for (int i = 0; i < data.length; i++) {
        cumulative += distances[i];
        if (cumulative >= target) {
          selectedIdx = i;
          break;
        }
      }

      centroids.add(Float32List.fromList(data[selectedIdx]));
    }

    return centroids;
  }

  int _findNearestCentroid(Float32List vector) {
    int nearest = 0;
    double minDist = double.infinity;
    
    for (int c = 0; c < numClusters; c++) {
      final dist = _squaredDistance(vector, _centroids![c]);
      if (dist < minDist) {
        minDist = dist;
        nearest = c;
      }
    }
    
    return nearest;
  }

  static double _squaredDistance(Float32List a, Float32List b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sum;
  }

  /// Serializes the trained model to bytes
  Uint8List serialize() {
    if (!isTrained) {
      throw StateError('Model must be trained before serialization');
    }

    final dimension = _centroids![0].length;
    // Format: [numClusters:4][dimension:4][centroids:numClusters*dimension*4]
    final bytes = ByteData(8 + numClusters * dimension * 4);
    bytes.setInt32(0, numClusters, Endian.little);
    bytes.setInt32(4, dimension, Endian.little);
    
    int offset = 8;
    for (final centroid in _centroids!) {
      for (final value in centroid) {
        bytes.setFloat32(offset, value, Endian.little);
        offset += 4;
      }
    }
    
    return bytes.buffer.asUint8List();
  }

  /// Deserializes a trained model from bytes
  static KMeans deserialize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final numClusters = data.getInt32(0, Endian.little);
    final dimension = data.getInt32(4, Endian.little);
    
    final kmeans = KMeans(numClusters: numClusters);
    kmeans._centroids = List.generate(numClusters, (c) {
      final centroid = Float32List(dimension);
      final baseOffset = 8 + c * dimension * 4;
      for (int d = 0; d < dimension; d++) {
        centroid[d] = data.getFloat32(baseOffset + d * 4, Endian.little);
      }
      return centroid;
    });
    
    return kmeans;
  }
}
