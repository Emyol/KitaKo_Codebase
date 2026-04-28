import 'dart:io';
import 'dart:typed_data';

import '../core/ann_algorithm.dart';
import '../core/ann_config.dart';
import '../core/ann_index.dart';
import '../core/ann_types.dart';
import 'inverted_file.dart';
import 'product_quantizer.dart';

/// IVF-PQ implementation of the AnnIndex interface
/// 
/// Uses Inverted File with Product Quantization for approximate nearest
/// neighbor search. This is a pure Dart implementation that trades some
/// accuracy for memory efficiency and fast search.
/// 
/// **Characteristics:**
/// - Requires training on representative data
/// - Memory efficient due to vector compression
/// - Fast search with controllable accuracy (via nprobe)
/// - Does NOT support incremental updates after training
/// 
/// **Usage:**
/// ```dart
/// final config = IvfPqConfig.siglip768();
/// final index = IvfPqAnnIndex(config: config);
/// 
/// // Train on representative data
/// await index.train(trainingVectors);
/// 
/// // Add vectors
/// await index.addVectors(vectors, ids);
/// 
/// // Search
/// final results = await index.search(query, k: 10);
/// ```
class IvfPqAnnIndex extends AnnIndex with AnnIndexValidation {
  final IvfPqConfig _config;
  ProductQuantizer? _pq;
  InvertedFile? _ivf;
  bool _isTrained = false;
  
  /// Maps internal sequential IDs to user-provided IDs
  final Map<int, int> _idMapping = {};
  int _nextInternalId = 0;

  IvfPqAnnIndex({required IvfPqConfig config}) : _config = config;

  @override
  AnnAlgorithm get algorithm => AnnAlgorithm.ivfpq;

  @override
  DistanceMetric get metric => DistanceMetric.l2;

  @override
  int get dimension => _config.dimension;

  @override
  int get size => _ivf?.size ?? 0;

  @override
  bool get isReady => _isTrained && _ivf != null;

  @override
  int? get maxCapacity => null; // IVF-PQ doesn't have a fixed capacity

  /// Whether the index has been trained
  bool get isTrained => _isTrained;

  /// Trains the index on representative data
  /// 
  /// This must be called before adding vectors. The training data should be
  /// representative of the vectors that will be indexed.
  /// 
  /// [data] - List of training vectors, each with dimension [dimension]
  /// [seed] - Optional random seed for reproducibility
  Future<void> train(List<Float32List> data, {int? seed}) async {
    if (data.isEmpty) {
      throw AnnIndexException('Training data cannot be empty');
    }
    
    for (final vector in data) {
      if (vector.length != dimension) {
        throw AnnIndexException(
          'Vector dimension mismatch',
          details: 'Expected $dimension, got ${vector.length}',
        );
      }
    }

    // Initialize Product Quantizer (untrained — InvertedFile.train() will
    // train it on residuals after fitting the coarse quantizer).
    _pq = ProductQuantizer(
      dimension: dimension,
      numSubquantizers: _config.numSubquantizers,
      numCentroids: _config.numCentroidsPerSubquantizer,
    );

    // Initialize and train Inverted File.
    // This also trains the PQ on residuals (vector − cluster_centroid),
    // ensuring the codebooks match the actual residual distribution.
    _ivf = InvertedFile(
      numClusters: _config.numClusters,
      dimension: dimension,
    );

    _ivf!.train(
      data,
      pq: _pq!,
      maxIterations: _config.trainingIterations,
      seed: seed,
    );

    _isTrained = true;
  }

  @override
  Future<void> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw AnnIndexException('Index file not found: $path');
    }

    try {
      final bytes = await file.readAsBytes();
      _deserialize(bytes);
    } catch (e) {
      throw AnnIndexException('Failed to load index: $e');
    }
  }

  @override
  Future<void> save(String path) async {
    if (!isReady) {
      throw AnnIndexException('Cannot save untrained index');
    }

    try {
      final bytes = _serialize();
      final file = File(path);
      await file.writeAsBytes(bytes);
    } catch (e) {
      throw AnnIndexException('Failed to save index: $e');
    }
  }

  @override
  Future<List<AnnSearchResult>> search(
    Float32List query,
    int k,
  ) async {
    if (!isReady) {
      throw AnnIndexException('Index not loaded or trained');
    }
    
    validateQuery(query);
    validateK(k);

    final results = _ivf!.search(
      query,
      k: k,
      nprobe: _config.numProbes,
    );

    return results.map((r) {
      final externalId = _idMapping[r.$1] ?? r.$1;
      return AnnSearchResult(
        id: externalId,
        distance: r.$2,
      );
    }).toList();
  }

  @override
  Future<void> addVector(Float32List vector, int id) async {
    if (!_isTrained) {
      throw AnnIndexException(
        'IVF-PQ index must be trained before adding vectors. '
        'Call train() first with representative data.',
      );
    }
    
    if (vector.length != dimension) {
      throw AnnIndexException(
        'Vector dimension mismatch',
        details: 'Expected $dimension, got ${vector.length}',
      );
    }

    final internalId = _nextInternalId++;
    _idMapping[internalId] = id;
    _ivf!.add(internalId, vector);
  }

  @override
  Future<void> addVectors(List<Float32List> vectors, List<int> ids) async {
    if (!_isTrained) {
      throw AnnIndexException(
        'IVF-PQ index must be trained before adding vectors. '
        'Call train() first with representative data.',
      );
    }
    
    if (vectors.length != ids.length) {
      throw AnnIndexException(
        'Vectors and IDs length mismatch',
        details: '${vectors.length} vectors vs ${ids.length} ids',
      );
    }
    
    for (final vector in vectors) {
      if (vector.length != dimension) {
        throw AnnIndexException(
          'Vector dimension mismatch',
          details: 'Expected $dimension, got ${vector.length}',
        );
      }
    }

    for (int i = 0; i < vectors.length; i++) {
      final internalId = _nextInternalId++;
      _idMapping[internalId] = ids[i];
      _ivf!.add(internalId, vectors[i]);
    }
  }

  @override
  void dispose() {
    _pq = null;
    _ivf = null;
    _isTrained = false;
    _idMapping.clear();
    _nextInternalId = 0;
  }

  /// Returns statistics about the index
  Map<String, dynamic> getStatistics() {
    if (!isReady) {
      return {'status': 'not_loaded'};
    }

    final clusterSizes = _ivf!.clusterSizes;
    final nonEmptyClusters = clusterSizes.where((s) => s > 0).length;
    final avgClusterSize = size / nonEmptyClusters;
    final maxClusterSize = clusterSizes.reduce((a, b) => a > b ? a : b);
    final minClusterSize = clusterSizes.where((s) => s > 0).reduce((a, b) => a < b ? a : b);

    return {
      'total_vectors': size,
      'num_clusters': _config.numClusters,
      'non_empty_clusters': nonEmptyClusters,
      'avg_cluster_size': avgClusterSize,
      'max_cluster_size': maxClusterSize,
      'min_cluster_size': minClusterSize,
      'num_subquantizers': _config.numSubquantizers,
      'num_centroids_per_sq': _config.numCentroidsPerSubquantizer,
      'num_probes': _config.numProbes,
      'compression_ratio': dimension * 4 / _config.numSubquantizers,
    };
  }

  Uint8List _serialize() {
    final pqBytes = _pq!.serialize();
    final ivfBytes = _ivf!.serialize();
    
    // Serialize ID mapping
    final mappingSize = _idMapping.length * 8; // 2 ints per entry
    
    // Header: [magic:4][version:4][pqLen:4][ivfLen:4][mappingLen:4][nextId:4]
    final headerSize = 24;
    final totalSize = headerSize + pqBytes.length + ivfBytes.length + mappingSize;
    
    final buffer = Uint8List(totalSize);
    final data = ByteData.sublistView(buffer);
    
    data.setUint32(0, 0x49565051, Endian.little); // "IVPQ" magic
    data.setUint32(4, 1, Endian.little); // version
    data.setInt32(8, pqBytes.length, Endian.little);
    data.setInt32(12, ivfBytes.length, Endian.little);
    data.setInt32(16, _idMapping.length, Endian.little);
    data.setInt32(20, _nextInternalId, Endian.little);
    
    int offset = headerSize;
    buffer.setRange(offset, offset + pqBytes.length, pqBytes);
    offset += pqBytes.length;
    
    buffer.setRange(offset, offset + ivfBytes.length, ivfBytes);
    offset += ivfBytes.length;
    
    // Write ID mapping
    for (final entry in _idMapping.entries) {
      data.setInt32(offset, entry.key, Endian.little);
      data.setInt32(offset + 4, entry.value, Endian.little);
      offset += 8;
    }
    
    return buffer;
  }

  void _deserialize(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    
    final magic = data.getUint32(0, Endian.little);
    if (magic != 0x49565051) {
      throw AnnIndexException('Invalid IVF-PQ index file format');
    }
    
    final version = data.getUint32(4, Endian.little);
    if (version != 1) {
      throw AnnIndexException('Unsupported IVF-PQ index version: $version');
    }
    
    final pqLen = data.getInt32(8, Endian.little);
    final ivfLen = data.getInt32(12, Endian.little);
    final mappingLen = data.getInt32(16, Endian.little);
    _nextInternalId = data.getInt32(20, Endian.little);
    
    int offset = 24;
    
    final pqBytes = Uint8List.sublistView(bytes, offset, offset + pqLen);
    _pq = ProductQuantizer.deserialize(pqBytes);
    offset += pqLen;
    
    final ivfBytes = Uint8List.sublistView(bytes, offset, offset + ivfLen);
    _ivf = InvertedFile.deserialize(ivfBytes);
    offset += ivfLen;
    
    // Read ID mapping
    _idMapping.clear();
    for (int i = 0; i < mappingLen; i++) {
      final internalId = data.getInt32(offset, Endian.little);
      final externalId = data.getInt32(offset + 4, Endian.little);
      _idMapping[internalId] = externalId;
      offset += 8;
    }
    
    _isTrained = true;
  }
}
