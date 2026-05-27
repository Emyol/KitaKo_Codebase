import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:kitako_normalizer/kitako_normalizer.dart';

// Conditional import - don't import native packages on web
import 'embedding_service_stub.dart'
    if (dart.library.io) 'package:kitako_embedding/kitako_embedding.dart';
// Re-export types so consumers get them from the same conditional source
export 'embedding_service_stub.dart'
    if (dart.library.io) 'package:kitako_embedding/kitako_embedding.dart'
    show SiglipModelVersion, SiglipModelConfig, ModelVariant;

import 'model_download_service.dart';

/// Backend type for embedding generation
enum EmbeddingBackend {
  /// ONNX Runtime backend
  onnx,

  /// No model loaded
  mock,
}

/// Service for generating text and image embeddings
///
/// This service wraps the kitako_embedding package and provides:
/// - Text normalization (Taglish support)
/// - Text embedding generation via SigLIP-2 / Kitako ONNX models
/// - Image embedding generation via SigLIP-2 / Kitako ONNX models
/// - Caching for repeated queries
/// - Model variant switching (Kitako INT8, SigLIP-2 Baseline)
class EmbeddingService {
  /// The ONNX embedding service
  OnnxEmbeddingService? _onnxClient;

  /// Model download service for ONNX models
  final ModelDownloadService _downloadService = ModelDownloadService();

  /// Current active backend
  EmbeddingBackend _activeBackend = EmbeddingBackend.mock;

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

  // Tokenizer path is resolved at runtime via _downloadService.getTokenizerPath().

  /// Current active model variant
  ModelVariant? _activeVariant;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Current backend in use
  EmbeddingBackend get activeBackend => _activeBackend;

  /// Current SigLIP model version (always siglip2 now)
  SiglipModelVersion get modelVersion => SiglipModelVersion.siglip2;

  /// Current active model variant
  ModelVariant? get activeVariant => _activeVariant;

  /// Current model configuration
  SiglipModelConfig? get modelConfig => _onnxClient?.modelConfig;

  /// Active execution provider for each encoder ('nnapi', 'coreml', 'xnnpack', 'cpu').
  /// Returns 'cpu' when no ONNX client is active.
  String get imageEp => _onnxClient?.imageEp ?? 'cpu';
  String get textEp => _onnxClient?.textEp ?? 'cpu';

  /// Returns the byte-fallback ratio for the given text. Returns 0.0 if no
  /// ONNX backend is loaded (assumes the query is valid).
  double byteFallbackRatio(String text) =>
      _onnxClient?.byteFallbackRatio(text) ?? 0.0;

  /// Whether text embedding is available (requires a real model)
  bool get isTextReady {
    if (_activeBackend == EmbeddingBackend.onnx) {
      return _onnxClient?.isTextEncoderReady ?? false;
    }
    return false;
  }

  /// Whether image embedding is available (requires a real model)
  bool get isImageReady {
    if (_activeBackend == EmbeddingBackend.onnx) {
      return _onnxClient?.isImageEncoderReady ?? false;
    }
    return false;
  }

  /// Initialize the embedding service
  ///
  /// Tries to load models in order:
  /// 1. Kitako INT8 (best for mobile - fast, small footprint)
  /// 2. SigLIP-2 Baseline (external/downloaded)
  ///
  /// On Android, copies models from /data/local/tmp/ if pushed via ADB.
  ///
  /// Returns `true` if a real model was loaded successfully
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    debugPrint('EmbeddingService: Starting initialization...');

    // On Android, try to copy models from ADB push location first
    try {
      await _downloadService.copyModelsFromTmp();
    } catch (e) {
      debugPrint('EmbeddingService: copyModelsFromTmp: $e');
    }

    // Try Kitako FP32 (FP32 vision + FP32 text) — highest quality, dev-only
    debugPrint('EmbeddingService: Checking for Kitako FP32 (FP32 vision + FP32 text)...');
    if (await _tryInitializeModel('kitako_vision_fp32', 'kitako_text_fp32', ModelVariant.kitakoFp32)) {
      return true;
    }

    // Try Kitako Mixed (FP32 vision + INT8 text) — primary config
    debugPrint('EmbeddingService: Checking for Kitako Mixed (FP32 vision + INT8 text)...');
    if (await _tryInitializeModel('kitako_vision_fp32', 'kitako_text_int8', ModelVariant.kitakoMixed)) {
      return true;
    }

    // Try all-INT8 as fallback
    debugPrint('EmbeddingService: Checking for Kitako INT8 (all-quantized fallback)...');
    if (await _tryInitializeModel('kitako_vision_int8', 'kitako_text_int8', ModelVariant.kitakoInt8)) {
      return true;
    }

    // Try SigLIP-2 Baseline from downloaded/external models
    debugPrint('EmbeddingService: Checking for SigLIP-2 Baseline...');
    if (await _tryInitializeModel('siglip2_vision', 'siglip2_text', ModelVariant.siglip2Baseline)) {
      return true;
    }

    // No real model found
    _activeBackend = EmbeddingBackend.mock;
    _isInitialized = false;
    debugPrint('EmbeddingService: ✗ No ONNX model found.');
    debugPrint('EmbeddingService: For Android, push models via ADB:');
    debugPrint('  adb push models/kitako_image_encoder_int8.onnx /data/local/tmp/');
    debugPrint('  adb push models/kitako_text_encoder_int8.onnx /data/local/tmp/');
    debugPrint('EmbeddingService: For desktop, place models in models/ in workspace root.');
    return false;
  }

  /// Try to initialize with a specific model pair.
  ///
  /// Checks availability, resolves paths, loads ONNX sessions + tokenizer.
  /// Returns `true` on success.
  Future<bool> _tryInitializeModel(
    String visionKey,
    String textKey,
    ModelVariant variant,
  ) async {
    try {
      final visionReady = await _downloadService.isModelAvailable(visionKey);
      final textReady = await _downloadService.isModelAvailable(textKey);

      if (!visionReady || !textReady) {
        debugPrint('EmbeddingService: ${variant.displayName} not available (vision: $visionReady, text: $textReady)');
        return false;
      }

      final visionPath = await _downloadService.getModelPath(visionKey);
      final textPath = await _downloadService.getModelPath(textKey);
      final tokenizerPath = await _downloadService.getTokenizerPath();

      debugPrint('EmbeddingService: Loading ${variant.displayName} from:');
      debugPrint('  Vision: $visionPath');
      debugPrint('  Text: $textPath');
      debugPrint('  Tokenizer: $tokenizerPath');

      _onnxClient = OnnxEmbeddingService();
      await _onnxClient!.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: tokenizerPath,
        modelVersion: SiglipModelVersion.siglip2,
      );

      _activeBackend = EmbeddingBackend.onnx;
      _activeVariant = variant;
      _isInitialized = true;
      _embeddingCache.clear();

      debugPrint('EmbeddingService: ${variant.displayName} initialized successfully');
      debugPrint('  - Vision encoder ready: ${_onnxClient!.isImageEncoderReady}');
      debugPrint('  - Text encoder ready: ${_onnxClient!.isTextEncoderReady}');
      debugPrint('  - Model config: ${_onnxClient!.modelConfig}');

      return true;
    } catch (e, stack) {
      debugPrint('╔══ EmbeddingService INIT ERROR ══╗');
      debugPrint('║ Model: ${variant.displayName}');
      debugPrint('║ Error: $e');
      debugPrint('║ Stack: $stack');
      debugPrint('╚════════════════════════════════╝');
      _onnxClient?.dispose();
      _onnxClient = null;
      return false;
    }
  }

  /// Whether both model files required for [variant] exist on disk.
  ///
  /// This does not attempt to open them — use [switchToVariant] for that.
  Future<bool> isVariantAvailable(ModelVariant variant) async {
    final visionReady = await _downloadService.isModelAvailable(variant.visionEncoderId);
    final textReady = await _downloadService.isModelAvailable(variant.textEncoderId);
    return visionReady && textReady;
  }

  /// Switch to a specific model variant
  ///
  /// [variant] - The model variant to use (from ModelVariant enum)
  ///
  /// Returns `true` if the switch was successful
  Future<bool> switchToVariant(ModelVariant variant) async {
    if (_activeVariant == variant && _isInitialized) {
      debugPrint('EmbeddingService: Already using ${variant.displayName}');
      return true;
    }

    debugPrint('EmbeddingService: Switching to ${variant.displayName}...');

    // Dispose current client and reset all state
    _onnxClient?.dispose();
    _onnxClient = null;
    _isInitialized = false;
    _activeBackend = EmbeddingBackend.mock;
    _activeVariant = null;
    _embeddingCache.clear();

    bool success = false;
    switch (variant) {
      case ModelVariant.kitakoFp32:
        success = await _tryInitializeModel('kitako_vision_fp32', 'kitako_text_fp32', variant);
        break;
      case ModelVariant.kitakoMixed:
        success = await _tryInitializeModel('kitako_vision_fp32', 'kitako_text_int8', variant);
        break;
      case ModelVariant.kitakoInt8:
        success = await _tryInitializeModel('kitako_vision_int8', 'kitako_text_int8', variant);
        break;
      case ModelVariant.siglip2Baseline:
        success = await _tryInitializeModel('siglip2_vision', 'siglip2_text', variant);
        break;
    }

    if (!success) {
      _activeBackend = EmbeddingBackend.mock;
      _activeVariant = null;
      _isInitialized = false;
      debugPrint('EmbeddingService: Failed to switch to ${variant.displayName}');
    }

    return success;
  }

  /// Generate embedding for a text query
  ///
  /// Normalizes the query and converts it to a dense vector.
  /// Results are cached to improve performance.
  Future<List<double>> generateEmbedding(String query) async {
    if (!_isInitialized || _activeBackend != EmbeddingBackend.onnx) {
      throw StateError(
        'EmbeddingService not initialized. No ONNX model is loaded.',
      );
    }

    // Normalize query (text-speak cleanup)
    final normalizedQuery = _normalizeQuery(query);

    // Check cache
    if (_embeddingCache.containsKey(normalizedQuery)) {
      return _embeddingCache[normalizedQuery]!;
    }

    if (_onnxClient == null || !_onnxClient!.isTextEncoderReady) {
      throw StateError('ONNX text encoder not ready.');
    }

    final float32Embedding = await _onnxClient!.embedText(normalizedQuery);
    final embedding = float32Embedding.toList();

    _cacheEmbedding(normalizedQuery, embedding);

    return embedding;
  }

  /// Generate embedding for an image
  ///
  /// Returns a normalized 768-dimensional embedding vector.
  /// Throws [StateError] if the image encoder is not ready.
  Future<List<double>> generateImageEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized || _activeBackend != EmbeddingBackend.onnx) {
      throw StateError(
        'EmbeddingService not initialized. No ONNX model is loaded.',
      );
    }

    if (_onnxClient == null || !_onnxClient!.isImageEncoderReady) {
      throw StateError('ONNX image encoder not ready.');
    }

    final float32Embedding = await _onnxClient!.embedImage(imageBytes);
    return float32Embedding.toList();
  }

  /// Generate embedding from pre-decoded RGBA bytes.
  ///
  /// Skips the full-resolution JPEG decode step — use this when the caller
  /// already holds pixels downscaled via [dart:ui.instantiateImageCodec].
  Future<List<double>> generateImageEmbeddingFromRgba(
      Uint8List rgba, int width, int height) async {
    if (!_isInitialized || _activeBackend != EmbeddingBackend.onnx) {
      throw StateError(
        'EmbeddingService not initialized. No ONNX model is loaded.',
      );
    }

    if (_onnxClient == null || !_onnxClient!.isImageEncoderReady) {
      throw StateError('ONNX image encoder not ready.');
    }

    final float32Embedding =
        await _onnxClient!.embedImageFromRgba(rgba, width, height);
    return float32Embedding.toList();
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
    if (_onnxClient != null) {
      return _onnxClient!.cosineSimilarity(
        Float32List.fromList(a),
        Float32List.fromList(b),
      );
    }
    return _cosineSimilarity(a, b);
  }

  /// Normalize a text query using TaglishNormalizer
  String _normalizeQuery(String query) {
    final normalized = _normalizer.normalize(query);
    if (normalized != query) {
      debugPrint('EmbeddingService: Normalized "$query" -> "$normalized"');
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
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _embeddingCache.length,
      'maxSize': _maxCacheSize,
      'utilization': _embeddingCache.length / _maxCacheSize,
      'backend': _activeBackend.name,
      'variant': _activeVariant?.name,
      'isTextReady': isTextReady,
      'isImageReady': isImageReady,
    };
  }

  /// Dispose of resources
  void dispose() {
    _onnxClient?.dispose();
    _onnxClient = null;
    _embeddingCache.clear();
    _isInitialized = false;
    _activeBackend = EmbeddingBackend.mock;
    _activeVariant = null;
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
