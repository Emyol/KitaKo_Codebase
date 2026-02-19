import 'dart:typed_data';

import 'kmeans.dart';
import 'product_quantizer.dart';

/// An entry in the inverted file, containing vector ID and PQ codes
class IvfEntry {
  /// Original vector ID
  final int id;
  
  /// PQ-compressed representation
  final Uint8List codes;

  const IvfEntry({required this.id, required this.codes});
}

/// Inverted File structure for IVF-PQ index
/// 
/// Partitions the vector space into clusters using coarse quantization.
/// Each cluster maintains an inverted list of vectors assigned to it.
class InvertedFile {
  /// Number of clusters (centroids)
  final int numClusters;
  
  /// Original vector dimension
  final int dimension;
  
  /// Coarse quantizer for cluster assignment
  KMeans? _coarseQuantizer;
  
  /// Product quantizer for residual compression
  ProductQuantizer? _pq;
  
  /// Inverted lists: cluster_id -> list of (id, codes)
  late List<List<IvfEntry>> _invertedLists;
  
  /// Total number of vectors stored
  int _numVectors = 0;

  InvertedFile({
    required this.numClusters,
    required this.dimension,
  }) {
    _invertedLists = List.generate(numClusters, (_) => <IvfEntry>[]);
  }

  /// Whether the structure has been trained
  bool get isTrained => _coarseQuantizer != null && _pq != null;

  /// Total number of vectors in the index
  int get size => _numVectors;

  /// Number of vectors in each cluster
  List<int> get clusterSizes =>
      _invertedLists.map((list) => list.length).toList();

  /// Trains the inverted file structure
  /// 
  /// [data] - Training vectors
  /// [pq] - Pre-trained product quantizer for residual encoding
  /// [maxIterations] - K-means iterations for coarse quantizer
  void train(
    List<Float32List> data, {
    required ProductQuantizer pq,
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
    if (data.length < numClusters) {
      throw ArgumentError(
        'Need at least $numClusters training samples, got ${data.length}',
      );
    }
    if (!pq.isTrained) {
      throw ArgumentError('ProductQuantizer must be trained first');
    }
    if (pq.dimension != dimension) {
      throw ArgumentError(
        'PQ dimension ${pq.dimension} != IVF dimension $dimension',
      );
    }

    _pq = pq;
    
    // Train coarse quantizer
    _coarseQuantizer = KMeans(
      numClusters: numClusters,
      maxIterations: maxIterations,
      seed: seed,
    );
    _coarseQuantizer!.train(data);
  }

  /// Adds a vector to the index
  /// 
  /// [id] - Unique identifier for the vector
  /// [vector] - The vector to add
  void add(int id, Float32List vector) {
    _checkTrained();
    if (vector.length != dimension) {
      throw ArgumentError(
        'Vector dimension ${vector.length} != expected $dimension',
      );
    }

    // Find nearest cluster
    final clusterId = _coarseQuantizer!.predict(vector);
    
    // Compute residual: vector - centroid
    final residual = _computeResidual(vector, clusterId);
    
    // Encode residual using PQ
    final codes = _pq!.encode(residual);
    
    // Add to inverted list
    _invertedLists[clusterId].add(IvfEntry(id: id, codes: codes));
    _numVectors++;
  }

  /// Adds multiple vectors to the index
  void addBatch(List<int> ids, List<Float32List> vectors) {
    if (ids.length != vectors.length) {
      throw ArgumentError('ids and vectors must have same length');
    }
    for (int i = 0; i < ids.length; i++) {
      add(ids[i], vectors[i]);
    }
  }

  /// Searches for the k nearest neighbors
  /// 
  /// [query] - Query vector
  /// [k] - Number of neighbors to return
  /// [nprobe] - Number of clusters to search (higher = more accurate but slower)
  /// 
  /// Returns list of (id, distance) pairs sorted by distance.
  List<(int id, double distance)> search(
    Float32List query, {
    required int k,
    required int nprobe,
  }) {
    _checkTrained();
    if (query.length != dimension) {
      throw ArgumentError(
        'Query dimension ${query.length} != expected $dimension',
      );
    }
    if (nprobe > numClusters) {
      nprobe = numClusters;
    }

    // Find nprobe nearest clusters
    final nearestClusters = _coarseQuantizer!.predictTopK(query, nprobe);
    
    // Collect candidates from selected clusters
    final candidates = <(int id, double distance)>[];
    
    for (final clusterId in nearestClusters) {
      if (_invertedLists[clusterId].isEmpty) continue;
      
      // Compute residual query for this cluster
      final residualQuery = _computeResidual(query, clusterId);
      
      // Pre-compute distance table
      final distTable = _pq!.computeDistanceTable(residualQuery);
      
      // Score all vectors in this cluster
      for (final entry in _invertedLists[clusterId]) {
        final distance = _pq!.computeAsymmetricDistance(distTable, entry.codes);
        candidates.add((entry.id, distance));
      }
    }

    // Sort by distance and take top k
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    return candidates.take(k).toList();
  }

  /// Searches with diagnostic metrics for IVF-PQ optimization
  ///
  /// Returns results plus detailed metrics about the search:
  /// - clustersProbed: how many non-empty clusters were actually searched
  /// - distanceComputations: total PQ distance lookups performed
  /// - totalCandidatesInProbedClusters: total vectors in probed clusters
  /// - probedClusterSizes: size of each probed cluster
  ({
    List<(int id, double distance)> results,
    int clustersProbed,
    int distanceComputations,
    int totalCandidatesInProbedClusters,
    List<int> probedClusterSizes,
  }) searchWithMetrics(
    Float32List query, {
    required int k,
    required int nprobe,
  }) {
    _checkTrained();
    if (query.length != dimension) {
      throw ArgumentError(
        'Query dimension ${query.length} != expected $dimension',
      );
    }
    if (nprobe > numClusters) {
      nprobe = numClusters;
    }

    final nearestClusters = _coarseQuantizer!.predictTopK(query, nprobe);

    final candidates = <(int id, double distance)>[];
    int distanceComputations = 0;
    int totalCandidatesInProbedClusters = 0;
    final probedClusterSizes = <int>[];
    int actualClustersProbed = 0;

    for (final clusterId in nearestClusters) {
      final clusterSize = _invertedLists[clusterId].length;
      probedClusterSizes.add(clusterSize);
      if (clusterSize == 0) continue;

      actualClustersProbed++;
      totalCandidatesInProbedClusters += clusterSize;

      final residualQuery = _computeResidual(query, clusterId);
      final distTable = _pq!.computeDistanceTable(residualQuery);

      for (final entry in _invertedLists[clusterId]) {
        final distance = _pq!.computeAsymmetricDistance(distTable, entry.codes);
        candidates.add((entry.id, distance));
        distanceComputations++;
      }
    }

    candidates.sort((a, b) => a.$2.compareTo(b.$2));

    return (
      results: candidates.take(k).toList(),
      clustersProbed: actualClustersProbed,
      distanceComputations: distanceComputations,
      totalCandidatesInProbedClusters: totalCandidatesInProbedClusters,
      probedClusterSizes: probedClusterSizes,
    );
  }

  /// Serializes the inverted file to bytes
  Uint8List serialize() {
    _checkTrained();
    
    final coarseBytes = _coarseQuantizer!.serialize();
    final pqBytes = _pq!.serialize();
    
    // Calculate total size for inverted lists
    int listsSize = 0;
    for (final list in _invertedLists) {
      // [listSize:4] + entries * (id:4 + codes:numSubquantizers)
      listsSize += 4 + list.length * (4 + _pq!.numSubquantizers);
    }
    
    // Header: [numClusters:4][dimension:4][numVectors:4]
    //         [coarseBytesLen:4][pqBytesLen:4]
    final headerSize = 20;
    final totalSize = headerSize + coarseBytes.length + pqBytes.length + listsSize;
    
    final buffer = Uint8List(totalSize);
    final data = ByteData.sublistView(buffer);
    
    data.setInt32(0, numClusters, Endian.little);
    data.setInt32(4, dimension, Endian.little);
    data.setInt32(8, _numVectors, Endian.little);
    data.setInt32(12, coarseBytes.length, Endian.little);
    data.setInt32(16, pqBytes.length, Endian.little);
    
    int offset = headerSize;
    buffer.setRange(offset, offset + coarseBytes.length, coarseBytes);
    offset += coarseBytes.length;
    
    buffer.setRange(offset, offset + pqBytes.length, pqBytes);
    offset += pqBytes.length;
    
    // Write inverted lists
    for (final list in _invertedLists) {
      data.setInt32(offset, list.length, Endian.little);
      offset += 4;
      for (final entry in list) {
        data.setInt32(offset, entry.id, Endian.little);
        offset += 4;
        buffer.setRange(offset, offset + entry.codes.length, entry.codes);
        offset += entry.codes.length;
      }
    }
    
    return buffer;
  }

  /// Deserializes an inverted file from bytes
  static InvertedFile deserialize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    
    final numClusters = data.getInt32(0, Endian.little);
    final dimension = data.getInt32(4, Endian.little);
    final numVectors = data.getInt32(8, Endian.little);
    final coarseBytesLen = data.getInt32(12, Endian.little);
    final pqBytesLen = data.getInt32(16, Endian.little);
    
    int offset = 20;
    
    final coarseBytes = Uint8List.sublistView(bytes, offset, offset + coarseBytesLen);
    offset += coarseBytesLen;
    
    final pqBytes = Uint8List.sublistView(bytes, offset, offset + pqBytesLen);
    offset += pqBytesLen;
    
    final ivf = InvertedFile(numClusters: numClusters, dimension: dimension);
    ivf._coarseQuantizer = KMeans.deserialize(coarseBytes);
    ivf._pq = ProductQuantizer.deserialize(pqBytes);
    ivf._numVectors = numVectors;
    
    // Read inverted lists
    final numSubquantizers = ivf._pq!.numSubquantizers;
    for (int c = 0; c < numClusters; c++) {
      final listSize = data.getInt32(offset, Endian.little);
      offset += 4;
      
      for (int i = 0; i < listSize; i++) {
        final id = data.getInt32(offset, Endian.little);
        offset += 4;
        final codes = Uint8List.sublistView(bytes, offset, offset + numSubquantizers);
        offset += numSubquantizers;
        ivf._invertedLists[c].add(IvfEntry(id: id, codes: Uint8List.fromList(codes)));
      }
    }
    
    return ivf;
  }

  Float32List _computeResidual(Float32List vector, int clusterId) {
    final centroid = _coarseQuantizer!.centroids![clusterId];
    final residual = Float32List(dimension);
    for (int i = 0; i < dimension; i++) {
      residual[i] = vector[i] - centroid[i];
    }
    return residual;
  }

  void _checkTrained() {
    if (!isTrained) {
      throw StateError('InvertedFile must be trained first');
    }
  }
}
