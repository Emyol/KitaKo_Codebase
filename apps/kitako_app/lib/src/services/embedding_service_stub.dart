import 'dart:typed_data';

/// Stub implementation for web platform where ONNX Runtime is not available.
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
      'ONNX Runtime requires native binaries which are not available in browsers.',
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
  Future<Float32List> embedText(String text) async {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed image - throws on web
  Future<Float32List> embedImage(Uint8List imageBytes) async {
    throw UnsupportedError('Not supported on web');
  }

  /// Embed preprocessed image - throws on web
  Future<Float32List> embedPreprocessedImage(Float32List preprocessedImage) async {
    throw UnsupportedError('Not supported on web');
  }

  /// Compute cosine similarity
  double cosineSimilarity(Float32List a, Float32List b) {
    throw UnsupportedError('Not supported on web');
  }

  /// Dispose resources
  void dispose() {}
}

