import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';

// Conditional import - don't import tflite on web
import 'embedding_service_stub.dart'
    if (dart.library.io) 'package:kitako_embedding/kitako_embedding.dart';

import 'model_download_service.dart';

/// Backend type for embedding generation
enum EmbeddingBackend {
  /// TFLite backend (original, may have op version issues)
  tflite,

  /// ONNX Runtime backend (more compatible)
  onnx,

  /// Mock backend for testing/fallback
  mock,
}

/// Service for generating text and image embeddings
///
/// This service wraps the kitako_embedding package and provides:
/// - Text normalization (Taglish support)
/// - Text embedding generation via SigLIP
/// - Image embedding generation via SigLIP
/// - Caching for repeated queries
/// - Support for both TFLite and ONNX backends
/// - Toggle between SigLIP-1 and SigLIP-2 models
///
/// Example usage:
/// ```dart
/// final embeddingService = EmbeddingService();
/// await embeddingService.initialize();
/// final embedding = await embeddingService.generateEmbedding('search query');
/// ```
class EmbeddingService {
  /// The underlying KitaKo embedding service (TFLite)
  KitakoEmbeddingService? _tfliteClient;

  /// The ONNX embedding service (alternative backend)
  OnnxEmbeddingService? _onnxClient;

  /// Model download service for ONNX models
  final ModelDownloadService _downloadService = ModelDownloadService();

  /// Current active backend
  EmbeddingBackend _activeBackend = EmbeddingBackend.mock;

  /// Current SigLIP model version
  SiglipModelVersion _modelVersion = SiglipModelVersion.siglip1;

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Taglish normalizer for preprocessing queries
  final TaglishNormalizer _normalizer = const TaglishNormalizer();

  /// Cache of recently generated embeddings
  final Map<String, List<double>> _embeddingCache = {};

  /// Maximum cache size
  static const int _maxCacheSize = 100;

  /// Embedding dimension (SigLIP)
  static const int embeddingDimension = 768;

  /// Asset paths for TFLite models
  static const String _imageModelAsset = 'assets/model/image_encoder/kitako_image_encoder_int8.tflite';
  static const String _textModelAsset = 'assets/model/text_encoder/kitako_text_encoder_dynamic.tflite';
  static const String _tokenizerAsset = 'assets/tokenizer/tokenizer.json';

  /// Asset paths for SigLIP-2 ONNX models (FP32)
  static const String _siglip2VisionAsset = 'assets/models/siglip2_vision_model_fp32.onnx';
  static const String _siglip2TextAsset = 'assets/models/siglip2_text_model_fp32.onnx';
  
  /// Asset path for SigLIP-2 tokenizer (256K vocabulary)
  static const String _siglip2TokenizerAsset = 'assets/models/tokenizer/tokenizer.json';

  /// Asset path for fine-tuned SigLIP tokenizer (256K vocabulary, from model folder)
  static const String _finetunedTokenizerAsset = 'assets/models/tokenizer/tokenizer.json';

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Current backend in use
  EmbeddingBackend get activeBackend => _activeBackend;

  /// Current SigLIP model version
  SiglipModelVersion get modelVersion => _modelVersion;

  /// Current model configuration
  SiglipModelConfig? get modelConfig => _onnxClient?.modelConfig;

  /// Whether text embedding is available
  bool get isTextReady {
    switch (_activeBackend) {
      case EmbeddingBackend.tflite:
        return _tfliteClient?.isTextEncoderReady ?? false;
      case EmbeddingBackend.onnx:
        return _onnxClient?.isTextEncoderReady ?? false;
      case EmbeddingBackend.mock:
        return true;
    }
  }

  /// Whether image embedding is available
  bool get isImageReady {
    switch (_activeBackend) {
      case EmbeddingBackend.tflite:
        return _tfliteClient?.isImageEncoderReady ?? false;
      case EmbeddingBackend.onnx:
        return _onnxClient?.isImageEncoderReady ?? false;
      case EmbeddingBackend.mock:
        return true;
    }
  }

  /// Initialize the embedding service
  ///
  /// Tries to load models in order:
  /// 1. Fine-tuned SigLIP (BEST - trained on Taglish)
  /// 2. SigLIP-1 ALIGNED (correctly aligned embeddings)
  /// 3. SigLIP-2 (downloaded)
  /// 4. SigLIP-2 (assets)
  /// 5. SigLIP-1 quantized (legacy)
  /// 6. TFLite
  /// 7. Mock
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // Copy any models sitting in /data/local/tmp/ into app storage first,
    // so all subsequent availability checks find them.
    debugPrint('EmbeddingService: Copying models from /data/local/tmp/ if present...');
    await _downloadService.copyModelsFromTmp();

    // 🔥 Try fine-tuned SigLIP first (BEST - trained on Taglish data)
    debugPrint('EmbeddingService: Checking for fine-tuned SigLIP models...');
    if (await _tryInitializeFinetunedSiglip()) {
      debugPrint('EmbeddingService: ✅ Using FINE-TUNED SigLIP (224x224, Taglish-trained)');
      return true;
    }

    // 🔥 Try SigLIP-1 ALIGNED (BEST - correctly aligned embeddings)
    debugPrint('EmbeddingService: Checking for SigLIP-1 ALIGNED models...');
    if (await _tryInitializeSiglip1Aligned()) {
      debugPrint('EmbeddingService: ✅ Using SigLIP-1 ALIGNED (224x224, correctly aligned embeddings)');
      return true;
    }

    // Try SigLIP-2 from downloaded models
    debugPrint('EmbeddingService: Checking for downloaded SigLIP-2...');
    if (await _tryInitializeSiglip2Downloaded()) {
      debugPrint('EmbeddingService: ✅ Using SigLIP-2 (256x256, 256K vocab, with projection) - DOWNLOADED');
      return true;
    }

    // Try SigLIP-2 from assets (fallback)
    debugPrint('EmbeddingService: Attempting to load SigLIP-2 from assets...');
    if (await initializeWithSiglip2()) {
      debugPrint('EmbeddingService: ✅ Using SigLIP-2 (256x256, 256K vocab, with projection) - FROM ASSETS');
      return true;
    }

    // Try ONNX backend (legacy SigLIP-1 quantized)
    if (await _tryInitializeOnnx()) {
      _activeBackend = EmbeddingBackend.onnx;
      _isInitialized = true;
      debugPrint('EmbeddingService: Initialized with ONNX backend (legacy)');
      return true;
    }

    // Try TFLite backend
    if (await _tryInitializeTflite()) {
      _activeBackend = EmbeddingBackend.tflite;
      _isInitialized = true;
      debugPrint('EmbeddingService: Initialized with TFLite backend');
      return true;
    }

    // Fall back to mock mode
    _activeBackend = EmbeddingBackend.mock;
    _isInitialized = true;
    debugPrint('EmbeddingService: Running in MOCK mode');
    return true;
  }

  /// Try to initialize with SigLIP-1 ALIGNED models (RECOMMENDED)
  /// These models have correctly aligned vision-text embeddings
  Future<bool> _tryInitializeSiglip1Aligned() async {
    try {
      // Check if aligned models are available
      final visionReady = await _downloadService.isModelAvailable('siglip1_vision_aligned');
      final textReady = await _downloadService.isModelAvailable('siglip1_text_aligned');

      if (!visionReady || !textReady) {
        debugPrint('EmbeddingService: SigLIP-1 ALIGNED models not available (vision: $visionReady, text: $textReady)');
        return false;
      }

      final visionPath = await _downloadService.getModelPath('siglip1_vision_aligned');
      final textPath = await _downloadService.getModelPath('siglip1_text_aligned');

      debugPrint('EmbeddingService: Loading SigLIP-1 ALIGNED from:');
      debugPrint('  Vision: $visionPath');
      debugPrint('  Text: $textPath');

      _onnxClient = OnnxEmbeddingService();
      await _onnxClient!.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: _tokenizerAsset,
        modelVersion: SiglipModelVersion.siglip1,
      );

      _activeBackend = EmbeddingBackend.onnx;
      _modelVersion = SiglipModelVersion.siglip1;
      _isInitialized = true;

      debugPrint('EmbeddingService: SigLIP-1 ALIGNED initialized successfully');
      debugPrint('  - Vision encoder ready: ${_onnxClient!.isImageEncoderReady}');
      debugPrint('  - Text encoder ready: ${_onnxClient!.isTextEncoderReady}');
      debugPrint('  - Model config: ${_onnxClient!.modelConfig}');

      // Clear embedding cache when switching models
      _embeddingCache.clear();

      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize SigLIP-1 ALIGNED: $e');
      debugPrint('Stack: $stack');
      _onnxClient?.dispose();
      _onnxClient = null;
      return false;
    }
  }

  /// Try to initialize with fine-tuned SigLIP models (BEST for Taglish)
  /// These models have been fine-tuned on KitaKo Taglish dataset
  Future<bool> _tryInitializeFinetunedSiglip() async {
    try {
      // Check if fine-tuned models are available
      final visionReady = await _downloadService.isModelAvailable('finetuned_vision');
      final textReady = await _downloadService.isModelAvailable('finetuned_text');

      if (!visionReady || !textReady) {
        debugPrint('EmbeddingService: Fine-tuned SigLIP models not available (vision: $visionReady, text: $textReady)');
        return false;
      }

      final visionPath = await _downloadService.getModelPath('finetuned_vision');
      final textPath = await _downloadService.getModelPath('finetuned_text');

      debugPrint('EmbeddingService: Loading FINE-TUNED SigLIP from:');
      debugPrint('  Vision: $visionPath');
      debugPrint('  Text: $textPath');

      _onnxClient = OnnxEmbeddingService();
      await _onnxClient!.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: _finetunedTokenizerAsset,
        modelVersion: SiglipModelVersion.finetunedSiglip,
      );

      _activeBackend = EmbeddingBackend.onnx;
      _modelVersion = SiglipModelVersion.finetunedSiglip;
      _isInitialized = true;

      debugPrint('EmbeddingService: Fine-tuned SigLIP initialized successfully');
      debugPrint('  - Vision encoder ready: ${_onnxClient!.isImageEncoderReady}');
      debugPrint('  - Text encoder ready: ${_onnxClient!.isTextEncoderReady}');
      debugPrint('  - Model config: ${_onnxClient!.modelConfig}');

      // Clear embedding cache when switching models
      _embeddingCache.clear();

      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize fine-tuned SigLIP: $e');
      debugPrint('Stack: $stack');
      _onnxClient?.dispose();
      _onnxClient = null;
      return false;
    }
  }

  /// Try to initialize with downloaded SigLIP-2 models
  Future<bool> _tryInitializeSiglip2Downloaded() async {
    try {
      // Check if SigLIP-2 models are downloaded
      final visionReady = await _downloadService.isModelAvailable('siglip2_vision');
      final textReady = await _downloadService.isModelAvailable('siglip2_text');

      if (!visionReady || !textReady) {
        debugPrint('EmbeddingService: SigLIP-2 models not available (vision: $visionReady, text: $textReady)');
        return false;
      }

      final visionPath = await _downloadService.getModelPath('siglip2_vision');
      final textPath = await _downloadService.getModelPath('siglip2_text');

      debugPrint('EmbeddingService: Loading SigLIP-2 from:');
      debugPrint('  Vision: $visionPath');
      debugPrint('  Text: $textPath');

      _onnxClient = OnnxEmbeddingService();
      await _onnxClient!.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: _siglip2TokenizerAsset,
        modelVersion: SiglipModelVersion.siglip2,
      );

      _activeBackend = EmbeddingBackend.onnx;
      _modelVersion = SiglipModelVersion.siglip2;
      _isInitialized = true;

      debugPrint('EmbeddingService: SigLIP-2 initialized successfully');
      debugPrint('  - Vision encoder ready: ${_onnxClient!.isImageEncoderReady}');
      debugPrint('  - Text encoder ready: ${_onnxClient!.isTextEncoderReady}');
      debugPrint('  - Model config: ${_onnxClient!.modelConfig}');

      // Clear embedding cache when switching models
      _embeddingCache.clear();

      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize downloaded SigLIP-2: $e');
      debugPrint('Stack: $stack');
      _onnxClient?.dispose();
      _onnxClient = null;
      return false;
    }
  }

  /// Try to initialize ONNX backend
  Future<bool> _tryInitializeOnnx() async {
    try {
      // First try to copy models from /data/local/tmp/ if they exist
      await _downloadService.copyModelsFromTmp();

      // Check if ONNX models are downloaded
      final visionReady = await _downloadService.isModelAvailable('vision_encoder');
      final textReady = await _downloadService.isModelAvailable('text_encoder');

      if (!visionReady || !textReady) {
        debugPrint('EmbeddingService: ONNX models not available');
        return false;
      }

      final visionPath = await _downloadService.getModelPath('vision_encoder');
      final textPath = await _downloadService.getModelPath('text_encoder');

      _onnxClient = OnnxEmbeddingService();
      await _onnxClient!.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: _tokenizerAsset,
      );

      debugPrint('EmbeddingService: ONNX backend initialized');
      debugPrint('  - Vision encoder ready: ${_onnxClient!.isImageEncoderReady}');
      debugPrint('  - Text encoder ready: ${_onnxClient!.isTextEncoderReady}');
      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize ONNX: $e');
      debugPrint('Stack: $stack');
      _onnxClient?.dispose();
      _onnxClient = null;
      return false;
    }
  }

  /// Try to initialize TFLite backend
  Future<bool> _tryInitializeTflite() async {
    try {
      debugPrint('EmbeddingService: Trying TFLite backend...');

      _tfliteClient = KitakoEmbeddingService();

      await _tfliteClient!.initialize(
        imageModelPath: _imageModelAsset,
        textModelPath: _textModelAsset,
        tokenizerPath: _tokenizerAsset,
      );

      debugPrint('EmbeddingService: TFLite backend initialized');
      debugPrint('  - Text encoder ready: ${_tfliteClient!.isTextEncoderReady}');
      debugPrint('  - Image encoder ready: ${_tfliteClient!.isImageEncoderReady}');
      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize TFLite: $e');
      debugPrint('Stack: $stack');
      _tfliteClient?.dispose();
      _tfliteClient = null;
      return false;
    }
  }

  /// Initialize specifically with ONNX backend after models are downloaded
  Future<bool> initializeWithOnnx() async {
    if (await _tryInitializeOnnx()) {
      _activeBackend = EmbeddingBackend.onnx;
      _isInitialized = true;
      return true;
    }
    return false;
  }

  /// Initialize with SigLIP-2 models
  ///
  /// This tries to load SigLIP-2 FP32 models in this order:
  /// 1. From downloaded/copied external files (/data/local/tmp/)
  /// 2. From bundled assets (if available)
  ///
  /// These models should have better multilingual support and semantic understanding.
  Future<bool> initializeWithSiglip2() async {
    // First try to copy models from /data/local/tmp/ if they exist
    await _downloadService.copyModelsFromTmp();

    // Try downloaded models first
    if (await _tryInitializeSiglip2Downloaded()) {
      return true;
    }

    // Fallback to assets
    try {
      debugPrint('EmbeddingService: Trying SigLIP-2 from assets...');

      _onnxClient = OnnxEmbeddingService();
      await _onnxClient!.initialize(
        visionModelPath: _siglip2VisionAsset,
        textModelPath: _siglip2TextAsset,
        tokenizerPath: _siglip2TokenizerAsset,
        modelVersion: SiglipModelVersion.siglip2,
      );

      _activeBackend = EmbeddingBackend.onnx;
      _modelVersion = SiglipModelVersion.siglip2;
      _isInitialized = true;

      debugPrint('EmbeddingService: SigLIP-2 initialized from assets');
      debugPrint('  - Vision encoder ready: ${_onnxClient!.isImageEncoderReady}');
      debugPrint('  - Text encoder ready: ${_onnxClient!.isTextEncoderReady}');
      debugPrint('  - Model config: ${_onnxClient!.modelConfig}');

      // Clear embedding cache when switching models
      _embeddingCache.clear();

      return true;
    } catch (e, stack) {
      debugPrint('EmbeddingService: Failed to initialize SigLIP-2: $e');
      debugPrint('Stack: $stack');
      _onnxClient?.dispose();
      _onnxClient = null;
      return false;
    }
  }

  /// Switch to a specific SigLIP model version
  ///
  /// [version] - The model version to switch to
  ///
  /// Returns `true` if the switch was successful
  Future<bool> switchToModel(SiglipModelVersion version) async {
    if (_modelVersion == version && _isInitialized) {
      debugPrint('EmbeddingService: Already using ${version.name}');
      return true;
    }

    debugPrint('EmbeddingService: Switching to ${version.name}...');

    // Dispose current client
    _onnxClient?.dispose();
    _onnxClient = null;
    _isInitialized = false;

    switch (version) {
      case SiglipModelVersion.siglip1:
        // Try downloaded SigLIP-1 models, then fallback
        return await initializeWithOnnx() || await _tryInitializeTflite();

      case SiglipModelVersion.siglip2:
        // Use SigLIP-2 from assets
        return await initializeWithSiglip2();

      case SiglipModelVersion.finetunedSiglip:
        // Use fine-tuned SigLIP from /data/local/tmp/ or app documents
        await _downloadService.copyModelsFromTmp();
        return await _tryInitializeFinetunedSiglip();
    }
  }

  /// Generate embedding for a text query
  ///
  /// Normalizes the query and converts it to a dense vector.
  /// Results are cached to improve performance.
  ///
  /// Parameters:
  /// - [query]: The text to embed
  ///
  /// Returns a list of doubles representing the embedding vector
  Future<List<double>> generateEmbedding(String query) async {
    if (!_isInitialized) {
      throw StateError(
        'EmbeddingService not initialized. Call initialize() first.',
      );
    }

    // Normalize query
    final normalizedQuery = _normalizeQuery(query);

    // Check cache
    if (_embeddingCache.containsKey(normalizedQuery)) {
      debugPrint('EmbeddingService: Cache hit for query: "$normalizedQuery"');
      return _embeddingCache[normalizedQuery]!;
    }

    try {
      List<double> embedding;

      switch (_activeBackend) {
        case EmbeddingBackend.onnx:
          if (_onnxClient != null && _onnxClient!.isTextEncoderReady) {
            final float32Embedding = _onnxClient!.embedText(normalizedQuery);
            embedding = float32Embedding.toList();
            debugPrint('EmbeddingService: Generated ONNX embedding for: "$normalizedQuery"');
          } else {
            embedding = _generateMockEmbedding(normalizedQuery);
            debugPrint('EmbeddingService: ONNX fallback to mock for: "$normalizedQuery"');
          }
          break;

        case EmbeddingBackend.tflite:
          if (_tfliteClient != null && _tfliteClient!.isTextEncoderReady) {
            final float32Embedding = _tfliteClient!.embedText(normalizedQuery);
            embedding = float32Embedding.toList();
            debugPrint('EmbeddingService: Generated TFLite embedding for: "$normalizedQuery"');
          } else {
            embedding = _generateMockEmbedding(normalizedQuery);
            debugPrint('EmbeddingService: TFLite fallback to mock for: "$normalizedQuery"');
          }
          break;

        case EmbeddingBackend.mock:
          embedding = _generateMockEmbedding(normalizedQuery);
          debugPrint('EmbeddingService: Generated MOCK embedding for: "$normalizedQuery"');
          break;
      }

      // Cache the result
      _cacheEmbedding(normalizedQuery, embedding);

      return embedding;
    } catch (e) {
      debugPrint('EmbeddingService: Failed to generate embedding: $e');
      // Fall back to mock on error
      final mockEmbedding = _generateMockEmbedding(normalizedQuery);
      _cacheEmbedding(normalizedQuery, mockEmbedding);
      return mockEmbedding;
    }
  }

  /// Generate embedding for an image
  ///
  /// Parameters:
  /// - [imageBytes]: Raw image bytes (JPEG, PNG, etc.)
  ///
  /// Returns a normalized 768-dimensional embedding vector
  Future<List<double>> generateImageEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized) {
      throw StateError(
        'EmbeddingService not initialized. Call initialize() first.',
      );
    }

    try {
      switch (_activeBackend) {
        case EmbeddingBackend.onnx:
          if (_onnxClient != null && _onnxClient!.isImageEncoderReady) {
            final float32Embedding = _onnxClient!.embedImage(imageBytes);
            debugPrint('EmbeddingService: Generated ONNX image embedding');
            return float32Embedding.toList();
          }
          break;

        case EmbeddingBackend.tflite:
          if (_tfliteClient != null && _tfliteClient!.isImageEncoderReady) {
            final float32Embedding = _tfliteClient!.embedImage(imageBytes);
            debugPrint('EmbeddingService: Generated TFLite image embedding');
            return float32Embedding.toList();
          }
          break;

        case EmbeddingBackend.mock:
          break;
      }

      // Fall back to mock embedding
      debugPrint('EmbeddingService: Generated MOCK image embedding');
      return _generateMockEmbedding('image_${imageBytes.hashCode}');
    } catch (e) {
      debugPrint('EmbeddingService: Failed to generate image embedding: $e');
      return _generateMockEmbedding('image_${imageBytes.hashCode}');
    }
  }

  /// Generate embeddings for multiple queries in batch
  Future<List<List<double>>> generateBatchEmbeddings(
    List<String> queries,
  ) async {
    final embeddings = <List<double>>[];
    for (final query in queries) {
      final embedding = await generateEmbedding(query);
      embeddings.add(embedding);
    }
    return embeddings;
  }

  /// Compute similarity between two embeddings
  double computeSimilarity(List<double> a, List<double> b) {
    switch (_activeBackend) {
      case EmbeddingBackend.onnx:
        if (_onnxClient != null) {
          return _onnxClient!.cosineSimilarity(
            Float32List.fromList(a),
            Float32List.fromList(b),
          );
        }
        break;
      case EmbeddingBackend.tflite:
        if (_tfliteClient != null) {
          return _tfliteClient!.cosineSimilarity(
            Float32List.fromList(a),
            Float32List.fromList(b),
          );
        }
        break;
      case EmbeddingBackend.mock:
        break;
    }
    return _cosineSimilarity(a, b);
  }

  /// Normalize a text query using TaglishNormalizer
  String _normalizeQuery(String query) {
    final normalized = _normalizer.normalize(query);
    if (normalized != query) {
      debugPrint('EmbeddingService: Normalized "$query" → "$normalized"');
    }
    return normalized;
  }

  /// Cache an embedding result (LRU eviction)
  void _cacheEmbedding(String query, List<double> embedding) {
    if (_embeddingCache.length >= _maxCacheSize) {
      final firstKey = _embeddingCache.keys.first;
      _embeddingCache.remove(firstKey);
    }
    _embeddingCache[query] = embedding;
  }

  /// Clear the embedding cache
  void clearCache() {
    _embeddingCache.clear();
    debugPrint('EmbeddingService: Cache cleared');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _embeddingCache.length,
      'maxSize': _maxCacheSize,
      'utilization': _embeddingCache.length / _maxCacheSize,
      'backend': _activeBackend.name,
      'isTextReady': isTextReady,
      'isImageReady': isImageReady,
    };
  }

  /// Dispose of resources
  void dispose() {
    _tfliteClient?.dispose();
    _tfliteClient = null;
    _onnxClient?.dispose();
    _onnxClient = null;
    clearCache();
    _isInitialized = false;
    _activeBackend = EmbeddingBackend.mock;
    debugPrint('EmbeddingService: Disposed');
  }

  // ========== Fallback Mock Implementation ==========

  /// Generate a mock embedding vector (deterministic based on hash)
  List<double> _generateMockEmbedding(String input) {
    final hash = input.hashCode;
    final random = _SeededRandom(hash);
    return List.generate(
      embeddingDimension,
      (index) => (random.nextDouble() * 2) - 1,
    );
  }

  /// Cosine similarity fallback
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    final denominator = _sqrt(normA) * _sqrt(normB);
    return denominator == 0 ? 0.0 : dot / denominator;
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

/// Simple seeded random for deterministic mock embeddings
class _SeededRandom {
  int _seed;
  _SeededRandom(this._seed);

  double nextDouble() {
    _seed = ((_seed * 1103515245) + 12345) & 0x7fffffff;
    return _seed / 0x7fffffff;
  }
}
