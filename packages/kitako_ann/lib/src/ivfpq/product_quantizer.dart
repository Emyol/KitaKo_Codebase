import 'dart:typed_data';

import 'kmeans.dart';

/// Product Quantizer for vector compression
/// 
/// Divides vectors into M sub-vectors and quantizes each independently
/// using a separate codebook. This allows for efficient storage and
/// asymmetric distance computation.
class ProductQuantizer {
  /// Number of subquantizers (M)
  final int numSubquantizers;
  
  /// Number of centroids per subquantizer (K, typically 256)
  final int numCentroids;
  
  /// Original vector dimension
  final int dimension;
  
  /// Dimension of each subvector (dimension / numSubquantizers)
  final int subvectorDimension;
  
  /// Codebooks for each subquantizer [M x K x subvectorDimension]
  List<KMeans>? _codebooks;

  ProductQuantizer({
    required this.dimension,
    required this.numSubquantizers,
    this.numCentroids = 256,
  }) : subvectorDimension = dimension ~/ numSubquantizers {
    if (dimension % numSubquantizers != 0) {
      throw ArgumentError(
        'Dimension ($dimension) must be divisible by numSubquantizers ($numSubquantizers)',
      );
    }
    if (numCentroids > 256) {
      throw ArgumentError(
        'numCentroids cannot exceed 256 for uint8 codes',
      );
    }
  }

  /// Whether the quantizer has been trained
  bool get isTrained => _codebooks != null;

  /// Trains the product quantizer on the provided data
  /// 
  /// [data] is a list of vectors, each with dimension [dimension].
  /// [maxIterations] controls k-means iterations per subquantizer.
  void train(
    List<Float32List> data, {
    int maxIterations = 25,
    int? seed,
  }) {
    if (data.isEmpty) {
      throw ArgumentError('Training data cannot be empty');
    }
    if (data[0].length != dimension) {
      throw ArgumentError(
        'Vector dimension ${data[0].length} != expected $dimension',
      );
    }
    if (data.length < numCentroids) {
      throw ArgumentError(
        'Need at least $numCentroids training samples, got ${data.length}',
      );
    }

    _codebooks = List.generate(numSubquantizers, (m) {
      // Extract sub-vectors for this subquantizer
      final subvectors = data.map((v) => _extractSubvector(v, m)).toList();
      
      final kmeans = KMeans(
        numClusters: numCentroids,
        maxIterations: maxIterations,
        seed: seed != null ? seed + m : null,
      );
      kmeans.train(subvectors);
      
      return kmeans;
    });
  }

  /// Encodes a vector into PQ codes
  /// 
  /// Returns a Uint8List of length [numSubquantizers], where each byte
  /// is the index of the nearest centroid in the corresponding codebook.
  Uint8List encode(Float32List vector) {
    _checkTrained();
    if (vector.length != dimension) {
      throw ArgumentError(
        'Vector dimension ${vector.length} != expected $dimension',
      );
    }

    final codes = Uint8List(numSubquantizers);
    for (int m = 0; m < numSubquantizers; m++) {
      final subvector = _extractSubvector(vector, m);
      codes[m] = _codebooks![m].predict(subvector);
    }
    return codes;
  }

  /// Encodes multiple vectors into PQ codes
  /// 
  /// Returns a list of Uint8List codes.
  List<Uint8List> encodeBatch(List<Float32List> vectors) {
    return vectors.map(encode).toList();
  }

  /// Decodes PQ codes back to an approximate vector
  /// 
  /// This is lossy - the decoded vector is an approximation of the original.
  Float32List decode(Uint8List codes) {
    _checkTrained();
    if (codes.length != numSubquantizers) {
      throw ArgumentError(
        'Codes length ${codes.length} != numSubquantizers $numSubquantizers',
      );
    }

    final vector = Float32List(dimension);
    for (int m = 0; m < numSubquantizers; m++) {
      final centroid = _codebooks![m].centroids![codes[m]];
      final offset = m * subvectorDimension;
      for (int d = 0; d < subvectorDimension; d++) {
        vector[offset + d] = centroid[d];
      }
    }
    return vector;
  }

  /// Pre-computes distance table for asymmetric distance computation
  /// 
  /// Returns a [numSubquantizers x numCentroids] table where
  /// table[m][k] = squared distance from query subvector m to centroid k.
  /// This allows O(M) distance computation instead of O(D).
  List<Float32List> computeDistanceTable(Float32List query) {
    _checkTrained();
    if (query.length != dimension) {
      throw ArgumentError(
        'Query dimension ${query.length} != expected $dimension',
      );
    }

    return List.generate(numSubquantizers, (m) {
      final subquery = _extractSubvector(query, m);
      final distances = Float32List(numCentroids);
      
      for (int k = 0; k < numCentroids; k++) {
        distances[k] = _squaredDistance(
          subquery,
          _codebooks![m].centroids![k],
        );
      }
      
      return distances;
    });
  }

  /// Computes asymmetric squared distance using pre-computed table
  /// 
  /// Much faster than decoding and computing full distance.
  double computeAsymmetricDistance(
    List<Float32List> distanceTable,
    Uint8List codes,
  ) {
    double distance = 0;
    for (int m = 0; m < numSubquantizers; m++) {
      distance += distanceTable[m][codes[m]];
    }
    return distance;
  }

  /// Serializes the trained quantizer to bytes
  Uint8List serialize() {
    _checkTrained();
    
    // Serialize each codebook
    final codebookBytes = _codebooks!.map((k) => k.serialize()).toList();
    
    // Header: [dimension:4][numSubquantizers:4][numCentroids:4][codebookLengths:M*4]
    final headerSize = 12 + numSubquantizers * 4;
    final totalSize = headerSize + codebookBytes.fold<int>(0, (s, b) => s + b.length);
    
    final bytes = ByteData(totalSize);
    bytes.setInt32(0, dimension, Endian.little);
    bytes.setInt32(4, numSubquantizers, Endian.little);
    bytes.setInt32(8, numCentroids, Endian.little);
    
    int offset = 12;
    for (final cb in codebookBytes) {
      bytes.setInt32(offset, cb.length, Endian.little);
      offset += 4;
    }
    
    final result = bytes.buffer.asUint8List();
    for (final cb in codebookBytes) {
      result.setRange(offset, offset + cb.length, cb);
      offset += cb.length;
    }
    
    return result;
  }

  /// Deserializes a trained quantizer from bytes
  static ProductQuantizer deserialize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final dimension = data.getInt32(0, Endian.little);
    final numSubquantizers = data.getInt32(4, Endian.little);
    final numCentroids = data.getInt32(8, Endian.little);
    
    final pq = ProductQuantizer(
      dimension: dimension,
      numSubquantizers: numSubquantizers,
      numCentroids: numCentroids,
    );
    
    // Read codebook lengths
    final codebookLengths = <int>[];
    int offset = 12;
    for (int m = 0; m < numSubquantizers; m++) {
      codebookLengths.add(data.getInt32(offset, Endian.little));
      offset += 4;
    }
    
    // Deserialize codebooks
    pq._codebooks = List.generate(numSubquantizers, (m) {
      final cbBytes = Uint8List.sublistView(
        bytes,
        offset,
        offset + codebookLengths[m],
      );
      offset += codebookLengths[m];
      return KMeans.deserialize(cbBytes);
    });
    
    return pq;
  }

  Float32List _extractSubvector(Float32List vector, int m) {
    final start = m * subvectorDimension;
    return Float32List.sublistView(vector, start, start + subvectorDimension);
  }

  void _checkTrained() {
    if (!isTrained) {
      throw StateError('ProductQuantizer must be trained first');
    }
  }

  static double _squaredDistance(Float32List a, Float32List b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sum;
  }
}
