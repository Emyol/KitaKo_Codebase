import 'dart:typed_data';

/// Stub implementation for web platform where tflite_flutter is not available.
/// This file is used via conditional imports when running on web.
/// All methods throw UnsupportedError - the EmbeddingService falls back to mock mode.

class KitakoEmbeddingService {
  /// Whether the service is fully initialized
  bool get isInitialized => false;

  /// Whether the image encoder is ready
  bool get isImageEncoderReady => false;

  /// Whether the text encoder is ready
  bool get isTextEncoderReady => false;

  /// Initialize the service - throws on web
  Future<void> initialize({
    required String imageModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    throw UnsupportedError(
      'KitakoEmbeddingService is not supported on web platform. '
      'TFLite requires native binaries which are not available in browsers.',
    );
  }

  /// Initialize from file paths - throws on web
  Future<void> initializeFromFiles({
    required String imageModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed text - throws on web
  Float32List embedText(String text) {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed image - throws on web
  Float32List embedImage(Uint8List imageBytes) {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed preprocessed image - throws on web
  Float32List embedPreprocessedImage(Float32List preprocessedImage) {
    throw UnsupportedError('Not supported on web');
  }

  /// Compute cosine similarity
  double cosineSimilarity(Float32List a, Float32List b) {
    throw UnsupportedError('Not supported on web');
  }

  /// Dispose resources
  void dispose() {}
}

/// Stub for ONNX-based embedding service (web platform)
class OnnxEmbeddingService {
  /// Whether the service is fully initialized
  bool get isInitialized => false;

  /// Whether the image encoder is ready
  bool get isImageEncoderReady => false;

  /// Whether the text encoder is ready
  bool get isTextEncoderReady => false;

  /// Initialize the runtime
  void initRuntime() {
    throw UnsupportedError('OnnxEmbeddingService not supported on web');
  }

  /// Initialize the service - throws on web
  Future<void> initialize({
    required String visionModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    throw UnsupportedError('OnnxEmbeddingService not supported on web');
  }

  /// Embed text - throws on web
  Float32List embedText(String text) {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed image - throws on web
  Float32List embedImage(Uint8List imageBytes) {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed preprocessed image - throws on web
  Float32List embedPreprocessedImage(Float32List preprocessedImage) {
    throw UnsupportedError('Not supported on web');
  }

  /// Compute cosine similarity
  double cosineSimilarity(Float32List a, Float32List b) {
    throw UnsupportedError('Not supported on web');
  }

  /// Dispose resources
  void dispose() {}
}

