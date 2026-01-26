/// KitaKo ANN (Approximate Nearest Neighbor) Package
///
/// Provides multiple ANN algorithms for the KitaKo multimodal image
/// retrieval application, with clean abstractions for easy switching.
///
/// ## Core Abstractions
/// - [AnnIndex]: Abstract interface all ANN implementations follow
/// - [AnnConfig]: Base configuration class with algorithm-specific subclasses
/// - [AnnFactory]: Factory for creating index instances
/// - [AnnAlgorithm]: Enum of supported algorithms (HNSW, IVF-PQ)
///
/// ## Implementations
/// - [HnswAnnIndex]: Graph-based HNSW using native FFI
/// - [IvfPqAnnIndex]: Pure Dart IVF-PQ with product quantization
///
/// ## Legacy API (deprecated)
/// - [AnnClient]: Abstract interface for ANN operations
/// - [LocalAnnClient]: Native FFI-based implementation using HNSW
/// - [AnnSearchService]: High-level service for search operations
/// - [IndexManager]: Handles index file loading and lifecycle
///
/// ## Usage
/// ```dart
/// // Using the new abstraction
/// final config = HnswConfig.siglip768();
/// final index = AnnFactory.create(config);
/// await index.load('path/to/index');
/// final results = await index.search(queryVector, k: 10);
///
/// // Or toggle between algorithms
/// final algorithm = AnnAlgorithm.ivfpq;
/// final index = algorithm.createIndex(dimension: 768);
/// ```
library kitako_ann;

// New unified API
export 'src/core/core.dart';
export 'src/hnsw/hnsw.dart';
export 'src/ivfpq/ivfpq.dart';

// Legacy API (will be deprecated)
export 'src/ann_client.dart';
export 'src/local_ann_client.dart';
export 'src/ann_search_service.dart';
export 'src/index_manager.dart';

// Re-export commonly used types from kitako_ffi
export 'package:kitako_ffi/kitako_ffi.dart'
    show AnnSpaceType, AnnError;


