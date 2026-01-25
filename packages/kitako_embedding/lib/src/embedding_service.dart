import 'dart:typed_data';

import 'image_preprocessor.dart';
import 'siglip_inference.dart';
import 'siglip_tokenizer.dart';

/// High-level embedding service for KitaKo.
///
/// Provides a unified interface for generating image and text embeddings
/// using the SigLIP model.
class KitakoEmbeddingService {
  final SiglipInference _inference = SiglipInference();
  final SiglipTokenizer _tokenizer = SiglipTokenizer();

  bool _isInitialized = false;

  /// Whether the service is fully initialized (models + tokenizer loaded)
  bool get isInitialized => _isInitialized;

  /// Whether the image encoder is ready
  bool get isImageEncoderReady => _inference.isImageModelLoaded;

  /// Whether the text encoder is ready
  bool get isTextEncoderReady =>
      _inference.isTextModelLoaded && _tokenizer.isLoaded;

  /// Initializes the embedding service with model and tokenizer files.
  ///
  /// [imageModelPath] - Path to the image encoder TFLite model (int8)
  /// [textModelPath] - Path to the text encoder TFLite model (dynamic)
  /// [tokenizerPath] - Path to the tokenizer.json file
  ///
  /// Pass asset paths for Flutter assets, or file paths for file system.
  Future<void> initialize({
    required String imageModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    // Load models (asset paths)
    await _inference.loadImageModel(imageModelPath);
    await _inference.loadTextModel(textModelPath);

    // Load tokenizer
    await _tokenizer.loadFromFile(tokenizerPath);

    _isInitialized = true;
  }

  /// Initializes from file paths (not Flutter assets).
  Future<void> initializeFromFiles({
    required String imageModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    await _inference.loadImageModelFromFile(imageModelPath);
    await _inference.loadTextModelFromFile(textModelPath);
    await _tokenizer.loadFromFile(tokenizerPath);

    _isInitialized = true;
  }

  /// Generates an embedding for an image.
  ///
  /// [imageBytes] - Raw image bytes (JPEG, PNG, etc.)
  ///
  /// Returns a normalized 768-dimensional embedding vector.
  Float32List embedImage(Uint8List imageBytes) {
    _ensureImageReady();

    // Preprocess the image
    final preprocessed = ImagePreprocessor.preprocessImage(imageBytes);

    // Run inference
    final embedding = _inference.embedImage(preprocessed);

    // L2 normalize the embedding
    return _l2Normalize(embedding);
  }

  /// Generates an embedding for preprocessed image data.
  ///
  /// [preprocessedImage] - Already preprocessed Float32List [1, 224, 224, 3]
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
  ///
  /// Returns a score between -1 and 1.
  double computeSimilarity(Uint8List imageBytes, String text) {
    final imageEmbedding = embedImage(imageBytes);
    final textEmbedding = embedText(text);
    return SiglipInference.cosineSimilarity(imageEmbedding, textEmbedding);
  }

  /// Computes similarity between two embeddings.
  double cosineSimilarity(Float32List a, Float32List b) {
    return SiglipInference.cosineSimilarity(a, b);
  }

  /// Finds the best matching text for an image from a list of candidates.
  ///
  /// Returns the index of the best match and its similarity score.
  (int index, double score) findBestTextMatch(
    Uint8List imageBytes,
    List<String> candidates,
  ) {
    final imageEmbedding = embedImage(imageBytes);

    int bestIndex = -1;
    double bestScore = double.negativeInfinity;

    for (int i = 0; i < candidates.length; i++) {
      final textEmbedding = embedText(candidates[i]);
      final score =
          SiglipInference.cosineSimilarity(imageEmbedding, textEmbedding);

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
    if (!_inference.isImageModelLoaded) {
      throw StateError('Image encoder not loaded. Call initialize() first.');
    }
  }

  void _ensureTextReady() {
    if (!_inference.isTextModelLoaded || !_tokenizer.isLoaded) {
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
