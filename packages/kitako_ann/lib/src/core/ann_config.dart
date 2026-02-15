import 'ann_algorithm.dart';
import 'ann_types.dart';

/// Base configuration for all ANN index types
abstract class AnnConfig {
  /// The algorithm to use
  AnnAlgorithm get algorithm;

  /// Vector dimensionality
  final int dimension;

  /// Distance metric
  final DistanceMetric metric;

  const AnnConfig({
    required this.dimension,
    this.metric = DistanceMetric.innerProduct,
  });

  /// Validates the configuration
  void validate() {
    if (dimension <= 0) {
      throw ArgumentError('Dimension must be positive');
    }
    if (dimension > 4096) {
      throw ArgumentError('Dimension too large (max 4096)');
    }
  }
}

/// Configuration for HNSW index
class HnswConfig extends AnnConfig {
  @override
  AnnAlgorithm get algorithm => AnnAlgorithm.hnsw;

  /// Number of bi-directional links per node (M parameter)
  /// Higher = better recall, more memory, slower build
  final int m;

  /// Size of dynamic candidate list during construction
  /// Higher = better quality, slower build
  final int efConstruction;

  /// Size of dynamic candidate list during search
  /// Higher = better recall, slower search
  final int efSearch;

  /// Maximum number of elements in the index
  final int maxElements;

  const HnswConfig({
    required super.dimension,
    super.metric,
    this.m = 16,
    this.efConstruction = 200,
    this.efSearch = 100,
    this.maxElements = 100000,
  });

  /// Default configuration for SigLIP-768 embeddings
  factory HnswConfig.siglip768({int maxElements = 100000}) {
    return HnswConfig(
      dimension: 768,
      metric: DistanceMetric.innerProduct,
      maxElements: maxElements,
    );
  }

  @override
  void validate() {
    super.validate();
    if (m < 2 || m > 100) {
      throw ArgumentError('M must be between 2 and 100');
    }
    if (efConstruction < m) {
      throw ArgumentError('efConstruction must be >= M');
    }
    if (maxElements <= 0) {
      throw ArgumentError('maxElements must be positive');
    }
  }

  HnswConfig copyWith({
    int? dimension,
    DistanceMetric? metric,
    int? m,
    int? efConstruction,
    int? efSearch,
    int? maxElements,
  }) {
    return HnswConfig(
      dimension: dimension ?? this.dimension,
      metric: metric ?? this.metric,
      m: m ?? this.m,
      efConstruction: efConstruction ?? this.efConstruction,
      efSearch: efSearch ?? this.efSearch,
      maxElements: maxElements ?? this.maxElements,
    );
  }
}

/// Configuration for IVF-PQ index
class IvfPqConfig extends AnnConfig {
  @override
  AnnAlgorithm get algorithm => AnnAlgorithm.ivfpq;

  /// Number of clusters (inverted lists)
  /// Typically sqrt(N) to 4*sqrt(N) where N is dataset size
  final int numClusters;

  /// Number of subquantizers (subspaces)
  /// Must evenly divide dimension
  final int numSubquantizers;

  /// Number of centroids per subquantizer (typically 256 for 8-bit codes)
  final int numCentroidsPerSubquantizer;

  /// Number of clusters to probe during search
  /// Higher = better recall, slower search
  final int numProbes;

  /// Number of k-means iterations for training
  final int trainingIterations;

  const IvfPqConfig({
    required super.dimension,
    super.metric,
    this.numClusters = 256,
    this.numSubquantizers = 8,
    this.numCentroidsPerSubquantizer = 256,
    this.numProbes = 8,
    this.trainingIterations = 25,
  });

  /// Default configuration for SigLIP-768 embeddings
  factory IvfPqConfig.siglip768({int numClusters = 256}) {
    return IvfPqConfig(
      dimension: 768,
      metric: DistanceMetric.innerProduct,
      numClusters: numClusters,
      numSubquantizers: 96, // 768 / 96 = 8 dimensions per subquantizer
      numCentroidsPerSubquantizer: 256,
    );
  }

  /// Bits per code (log2 of centroids per subquantizer)
  int get bitsPerCode {
    int bits = 0;
    int n = numCentroidsPerSubquantizer;
    while (n > 1) {
      bits++;
      n ~/= 2;
    }
    return bits;
  }

  /// Bytes needed to store one PQ code
  int get bytesPerCode => (numSubquantizers * bitsPerCode + 7) ~/ 8;

  /// Dimension of each subspace
  int get subspaceDimension {
    if (dimension % numSubquantizers != 0) {
      throw StateError(
        'Dimension ($dimension) must be divisible by numSubquantizers ($numSubquantizers)',
      );
    }
    return dimension ~/ numSubquantizers;
  }

  @override
  void validate() {
    super.validate();
    if (numClusters <= 0) {
      throw ArgumentError('numClusters must be positive');
    }
    if (numSubquantizers <= 0) {
      throw ArgumentError('numSubquantizers must be positive');
    }
    if (dimension % numSubquantizers != 0) {
      throw ArgumentError(
        'Dimension ($dimension) must be divisible by numSubquantizers ($numSubquantizers)',
      );
    }
    if (numCentroidsPerSubquantizer <= 0 || numCentroidsPerSubquantizer > 256) {
      throw ArgumentError('numCentroidsPerSubquantizer must be between 1 and 256 (uint8 PQ codes)');
    }
    if (numProbes <= 0 || numProbes > numClusters) {
      throw ArgumentError('numProbes must be between 1 and numClusters');
    }
  }

  IvfPqConfig copyWith({
    int? dimension,
    DistanceMetric? metric,
    int? numClusters,
    int? numSubquantizers,
    int? numCentroidsPerSubquantizer,
    int? numProbes,
    int? trainingIterations,
  }) {
    return IvfPqConfig(
      dimension: dimension ?? this.dimension,
      metric: metric ?? this.metric,
      numClusters: numClusters ?? this.numClusters,
      numSubquantizers: numSubquantizers ?? this.numSubquantizers,
      numCentroidsPerSubquantizer: numCentroidsPerSubquantizer ?? this.numCentroidsPerSubquantizer,
      numProbes: numProbes ?? this.numProbes,
      trainingIterations: trainingIterations ?? this.trainingIterations,
    );
  }
}
