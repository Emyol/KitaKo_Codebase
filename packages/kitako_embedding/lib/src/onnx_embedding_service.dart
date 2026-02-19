import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'image_preprocessor.dart';
import 'onnx_siglip_inference.dart';
import 'siglip_model_config.dart';
import 'siglip_tokenizer.dart';

/// ONNX-based embedding service for KitaKo.
///
/// This provides the same interface as [KitakoEmbeddingService] but uses
/// ONNX Runtime instead of TFLite, which avoids op version compatibility issues.
///
/// Supports multiple SigLIP model versions (SigLIP-1, SigLIP-2).
class OnnxEmbeddingService {
  final OnnxSiglipInference _inference = OnnxSiglipInference();
  final SiglipTokenizer _tokenizer = SiglipTokenizer();

  bool _isInitialized = false;

  /// Whether the service is fully initialized
  bool get isInitialized => _isInitialized;

  /// Whether the image encoder is ready
  bool get isImageEncoderReady => _inference.isVisionReady;

  /// Whether the text encoder is ready
  bool get isTextEncoderReady => _inference.isTextReady && _tokenizer.isLoaded;

  /// Get current model configuration
  SiglipModelConfig get modelConfig => _inference.config;

  /// Get current model version
  SiglipModelVersion get modelVersion => _inference.modelVersion;

  /// Initialize the ONNX Runtime environment.
  /// Must be called before loading models.
  ///
  /// [modelVersion] - Which SigLIP model version to use (defaults to SigLIP-1)
  void initRuntime({SiglipModelVersion modelVersion = SiglipModelVersion.siglip1}) {
    _inference.initialize(modelVersion: modelVersion);
  }

  /// Initializes the embedding service with model paths.
  ///
  /// [visionModelPath] - Path to the vision encoder ONNX model
  /// [textModelPath] - Path to the text encoder ONNX model
  /// [tokenizerPath] - Path to the tokenizer.json file
  /// [modelVersion] - Which SigLIP model version to use (defaults to SigLIP-1)
  Future<void> initialize({
    required String visionModelPath,
    required String textModelPath,
    required String tokenizerPath,
    SiglipModelVersion modelVersion = SiglipModelVersion.siglip1,
  }) async {
    // Initialize runtime with model version if not already done
    try {
      _inference.initialize(modelVersion: modelVersion);
    } catch (_) {
      // Already initialized
    }

    // Load models
    await _inference.loadVisionModel(visionModelPath);
    await _inference.loadTextModel(textModelPath);

    // Load tokenizer
    await _tokenizer.loadFromFile(tokenizerPath);

    _isInitialized = true;
    debugPrint('OnnxEmbeddingService: Initialized successfully');
    debugPrint('OnnxEmbeddingService: Model version: ${_inference.modelVersion.name}');
    debugPrint('OnnxEmbeddingService: Config: ${_inference.config}');
  }

  /// Generates an embedding for an image.
  ///
  /// [imageBytes] - Raw image bytes (JPEG, PNG, etc.)
  ///
  /// Returns a normalized 768-dimensional embedding vector.
  Float32List embedImage(Uint8List imageBytes) {
    _ensureImageReady();

    // Preprocess the image - need NCHW format for ONNX
    final preprocessed = _preprocessImageForOnnx(imageBytes);

    // Run inference
    final embedding = _inference.embedImage(preprocessed);

    // L2 normalize the embedding
    return _l2Normalize(embedding);
  }

  /// Preprocess image bytes to ONNX format based on current model config.
  /// Uses the image size from the model configuration (e.g., 224 for SigLIP-1, 256 for SigLIP-2).
  Float32List _preprocessImageForOnnx(Uint8List imageBytes) {
    final config = _inference.config;
    
    // First get the standard preprocessing (NHWC format) with correct size
    final nhwc = ImagePreprocessor.preprocessImage(
      imageBytes,
      targetSize: config.imageSize,
    );

    // Convert from NHWC [1, size, size, 3] to NCHW [1, 3, size, size]
    return _nhwcToNchw(nhwc, config.imageSize, config.imageSize, config.imageChannels);
  }

  /// Convert NHWC to NCHW format.
  Float32List _nhwcToNchw(Float32List nhwc, int height, int width, int channels) {
    final nchw = Float32List(nhwc.length);

    for (int c = 0; c < channels; c++) {
      for (int h = 0; h < height; h++) {
        for (int w = 0; w < width; w++) {
          final nhwcIndex = h * width * channels + w * channels + c;
          final nchwIndex = c * height * width + h * width + w;
          nchw[nchwIndex] = nhwc[nhwcIndex];
        }
      }
    }

    return nchw;
  }

  /// Generates an embedding for preprocessed image data (NCHW format).
  Float32List embedPreprocessedImage(Float32List preprocessedImage) {
    _ensureImageReady();
    final embedding = _inference.embedImage(preprocessedImage);
    return _l2Normalize(embedding);
  }

  /// Generates an embedding for text.
  ///
  /// [text] - Input text to embed
  ///
  /// Returns a normalized 768-dimensional embedding vector.
  Float32List embedText(String text) {
    _ensureTextReady();

    // Tokenize the text
    final tokens = _tokenizer.encode(text);

    // Run inference
    final embedding = _inference.embedText(tokens);

    // L2 normalize the embedding
    return _l2Normalize(embedding);
  }

  /// Generates embeddings for multiple texts (batch).
  List<Float32List> embedTexts(List<String> texts) {
    return texts.map(embedText).toList();
  }

  /// Computes similarity between an image and text.
  double computeSimilarity(Uint8List imageBytes, String text) {
    final imageEmbedding = embedImage(imageBytes);
    final textEmbedding = embedText(text);
    return cosineSimilarity(imageEmbedding, textEmbedding);
  }

  /// Computes similarity between two embeddings.
  double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError('Embedding dimensions must match');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = _sqrt(normA) * _sqrt(normB);
    if (denominator == 0) return 0.0;

    return dotProduct / denominator;
  }

  /// Finds the best matching text for an image from candidates.
  (int index, double score) findBestTextMatch(
    Uint8List imageBytes,
    List<String> candidates,
  ) {
    final imageEmbedding = embedImage(imageBytes);

    int bestIndex = -1;
    double bestScore = double.negativeInfinity;

    for (int i = 0; i < candidates.length; i++) {
      final textEmbedding = embedText(candidates[i]);
      final score = cosineSimilarity(imageEmbedding, textEmbedding);

      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return (bestIndex, bestScore);
  }

  /// Releases all resources.
  void dispose() {
    _inference.dispose();
    _isInitialized = false;
  }

  void _ensureImageReady() {
    if (!_inference.isVisionReady) {
      throw StateError('Vision encoder not loaded. Call initialize() first.');
    }
  }

  void _ensureTextReady() {
    if (!_inference.isTextReady || !_tokenizer.isLoaded) {
      throw StateError(
        'Text encoder or tokenizer not loaded. Call initialize() first.',
      );
    }
  }

  /// L2 normalizes an embedding vector.
  Float32List _l2Normalize(Float32List embedding) {
    double norm = 0.0;
    for (final value in embedding) {
      norm += value * value;
    }
    norm = _sqrt(norm);

    if (norm == 0) return embedding;

    final normalized = Float32List(embedding.length);
    for (int i = 0; i < embedding.length; i++) {
      normalized[i] = embedding[i] / norm;
    }
    return normalized;
  }

  /// Simple sqrt implementation
  double _sqrt(double x) {
    if (x < 0) return double.nan;
    if (x == 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}
