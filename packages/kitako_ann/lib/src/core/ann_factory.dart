import 'dart:math' show sqrt;

import 'ann_algorithm.dart';
import 'ann_config.dart';
import 'ann_index.dart';
import '../hnsw/hnsw_index.dart';
import '../ivfpq/ivfpq_index.dart';

/// Factory for creating ANN index instances
/// 
/// This factory provides a unified way to create different ANN implementations
/// based on configuration. It supports toggling between algorithms at runtime.
/// 
/// **Usage:**
/// ```dart
/// // Create HNSW index
/// final hnswConfig = HnswConfig.siglip768();
/// final hnswIndex = AnnFactory.create(hnswConfig);
/// 
/// // Create IVF-PQ index
/// final ivfpqConfig = IvfPqConfig.siglip768();
/// final ivfpqIndex = AnnFactory.create(ivfpqConfig);
/// 
/// // Or use the algorithm enum
/// final index = AnnFactory.createForAlgorithm(
///   AnnAlgorithm.hnsw,
///   dimension: 768,
/// );
/// ```
class AnnFactory {
  AnnFactory._(); // Private constructor to prevent instantiation

  /// Creates an ANN index based on the provided configuration
  /// 
  /// The configuration type determines which implementation is created:
  /// - [HnswConfig] -> [HnswAnnIndex]
  /// - [IvfPqConfig] -> [IvfPqAnnIndex]
  static AnnIndex create(AnnConfig config) {
    return switch (config) {
      HnswConfig c => HnswAnnIndex(config: c),
      IvfPqConfig c => IvfPqAnnIndex(config: c),
      _ => throw ArgumentError('Unsupported config type: ${config.runtimeType}'),
    };
  }

  /// Creates an ANN index for the specified algorithm with default config
  /// 
  /// [algorithm] - The algorithm to use
  /// [dimension] - Vector dimension (default: 768 for SigLIP)
  /// [options] - Optional algorithm-specific parameters
  static AnnIndex createForAlgorithm(
    AnnAlgorithm algorithm, {
    int dimension = 768,
    Map<String, dynamic>? options,
  }) {
    return switch (algorithm) {
      AnnAlgorithm.hnsw => _createHnsw(dimension, options),
      AnnAlgorithm.ivfpq => _createIvfPq(dimension, options),
    };
  }

  /// Creates an ANN index from a saved file
  /// 
  /// Automatically detects the algorithm type from the file format.
  /// Note: Currently this requires passing the config since the file
  /// format detection is not yet implemented.
  static Future<AnnIndex> loadFromFile(
    String path,
    AnnConfig config,
  ) async {
    final index = create(config);
    await index.load(path);
    return index;
  }

  /// Returns the recommended configuration for a given algorithm and use case
  /// 
  /// [algorithm] - The algorithm to configure
  /// [vectorCount] - Expected number of vectors (affects memory/quality tradeoffs)
  /// [dimension] - Vector dimension
  /// [priority] - 'speed', 'quality', or 'balanced'
  static AnnConfig getRecommendedConfig(
    AnnAlgorithm algorithm, {
    required int vectorCount,
    int dimension = 768,
    String priority = 'balanced',
  }) {
    return switch (algorithm) {
      AnnAlgorithm.hnsw => _getHnswConfig(vectorCount, dimension, priority),
      AnnAlgorithm.ivfpq => _getIvfPqConfig(vectorCount, dimension, priority),
    };
  }

  static HnswAnnIndex _createHnsw(int dimension, Map<String, dynamic>? options) {
    final config = HnswConfig(
      dimension: dimension,
      m: options?['m'] ?? 16,
      efConstruction: options?['efConstruction'] ?? 200,
      efSearch: options?['efSearch'] ?? 50,
      maxElements: options?['maxElements'] ?? 100000,
    );
    return HnswAnnIndex(config: config);
  }

  static IvfPqAnnIndex _createIvfPq(int dimension, Map<String, dynamic>? options) {
    // Default to 8 subquantizers if dimension is divisible by 8
    // Otherwise calculate appropriate number
    int numSubquantizers = 8;
    if (dimension % 8 != 0) {
      // Find largest divisor <= 96
      for (int d = 96; d >= 1; d--) {
        if (dimension % d == 0) {
          numSubquantizers = d;
          break;
        }
      }
    }

    final config = IvfPqConfig(
      dimension: dimension,
      numClusters: options?['numClusters'] ?? 256,
      numSubquantizers: options?['numSubquantizers'] ?? numSubquantizers,
      numCentroidsPerSubquantizer: options?['numCentroidsPerSubquantizer'] ?? 256,
      numProbes: options?['numProbes'] ?? 8,
      trainingIterations: options?['trainingIterations'] ?? 25,
    );
    return IvfPqAnnIndex(config: config);
  }

  static HnswConfig _getHnswConfig(int vectorCount, int dimension, String priority) {
    // Adjust parameters based on priority and scale
    final (m, efConstruction, efSearch) = switch (priority) {
      'speed' => (8, 100, 20),
      'quality' => (32, 400, 100),
      _ => (16, 200, 50), // balanced
    };

    return HnswConfig(
      dimension: dimension,
      m: m,
      efConstruction: efConstruction,
      efSearch: efSearch,
      maxElements: vectorCount,
    );
  }

  static IvfPqConfig _getIvfPqConfig(int vectorCount, int dimension, String priority) {
    // Number of clusters: sqrt(n) is a common heuristic
    int numClusters = sqrt((vectorCount > 0 ? vectorCount : 10000).toDouble()).toInt();
    numClusters = numClusters.clamp(16, 4096);
    
    // Round to nearest power of 2 for efficiency
    numClusters = _nearestPowerOf2(numClusters);

    // Calculate subquantizers based on dimension
    int numSubquantizers = 8;
    if (dimension % 96 == 0) {
      numSubquantizers = 96; // Maximizes compression
    } else if (dimension % 8 == 0) {
      numSubquantizers = dimension ~/ 8;
      if (numSubquantizers > 96) numSubquantizers = 96;
    }

    final numProbes = switch (priority) {
      'speed' => (numClusters * 0.01).toInt().clamp(1, 8),
      'quality' => (numClusters * 0.1).toInt().clamp(8, 64),
      _ => (numClusters * 0.03).toInt().clamp(4, 16), // balanced
    };

    return IvfPqConfig(
      dimension: dimension,
      numClusters: numClusters,
      numSubquantizers: numSubquantizers,
      numCentroidsPerSubquantizer: 256,
      numProbes: numProbes,
      trainingIterations: priority == 'quality' ? 50 : 25,
    );
  }

  static int _nearestPowerOf2(int n) {
    int power = 1;
    while (power < n) {
      power *= 2;
    }
    // Return the closer one
    if (power - n > n - power ~/ 2) {
      return power ~/ 2;
    }
    return power;
  }
}

/// Extension methods for convenient algorithm creation
extension AnnAlgorithmFactory on AnnAlgorithm {
  /// Creates an index using this algorithm with default configuration
  AnnIndex createIndex({
    int dimension = 768,
    Map<String, dynamic>? options,
  }) {
    return AnnFactory.createForAlgorithm(
      this,
      dimension: dimension,
      options: options,
    );
  }

  /// Gets the recommended configuration for this algorithm
  AnnConfig getRecommendedConfig({
    required int vectorCount,
    int dimension = 768,
    String priority = 'balanced',
  }) {
    return AnnFactory.getRecommendedConfig(
      this,
      vectorCount: vectorCount,
      dimension: dimension,
      priority: priority,
    );
  }
}
