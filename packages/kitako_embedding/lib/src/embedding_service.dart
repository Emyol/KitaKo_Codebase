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
  /// [imageModelPath] - Path to the image encoder ONNX model (int8)
  /// [textModelPath] - Path to the text encoder ONNX model (int8)
  /// [tokenizerPath] - Path to the tokenizer.json file
  ///
  /// Pass asset paths for Flutter assets (e.g., 'assets/model/...').
  Future<void> initialize({
    required String imageModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    // Load models from assets
    await _inference.loadImageModel(imageModelPath);
    await _inference.loadTextModel(textModelPath);

    // Load tokenizer from asset
    await _tokenizer.loadFromAsset(tokenizerPath);

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
  Future<Float32List> embedImage(Uint8List imageBytes) async {
    _ensureImageReady();

    // Preprocess the image in background isolate (much faster for large images)
    final preprocessed = await ImagePreprocessor.preprocessImageAsync(imageBytes);

    // Run inference
    final embedding = await _inference.embedImage(preprocessed);

    // L2 normalize the embedding
    return _l2Normalize(embedding);
  }

  /// Generates an embedding for preprocessed image data.
  ///
  /// [preprocessedImage] - Already preprocessed Float32List [1, 224, 224, 3]
  Future<Float32List> embedPreprocessedImage(Float32List preprocessedImage) async {
    _ensureImageReady();
    final embedding = await _inference.embedImage(preprocessedImage);
    return _l2Normalize(embedding);
  }

  /// Generates an embedding for text.
  ///
  /// [text] - Input text to embed
  ///
  /// Returns a normalized 768-dimensional embedding vector.
  Future<Float32List> embedText(String text) async {
    _ensureTextReady();

    // Format text with prompt template for better CLIP/SigLIP performance
    // SigLIP works best with descriptive prompts
    final promptText = _formatPrompt(text);

    // Tokenize the text
    final tokens = _tokenizer.encode(promptText);

    // Run inference
    final embedding = await _inference.embedText(tokens);

    // L2 normalize the embedding
    return _l2Normalize(embedding);
  }

  /// Format text with a prompt template for better cross-modal matching
  String _formatPrompt(String text) {
    // If already looks like a sentence/description, use as-is
    if (text.contains(' ') && text.length > 20) {
      print('SigLIP prompt (as-is): "$text"');
      return text;
    }
    // For short queries, wrap in a descriptive prompt
    final prompt = 'a photo of $text';
    print('SigLIP prompt (formatted): "$prompt"');
    return prompt;
  }

  /// Generates embeddings for multiple texts (batch).
  Future<List<Float32List>> embedTexts(List<String> texts) async {
    final results = <Float32List>[];
    for (final text in texts) {
      results.add(await embedText(text));
    }
    return results;
  }

  /// Computes similarity between an image and text.
  ///
  /// Returns a score between -1 and 1.
  Future<double> computeSimilarity(Uint8List imageBytes, String text) async {
    final imageEmbedding = await embedImage(imageBytes);
    final textEmbedding = await embedText(text);
    return SiglipInference.cosineSimilarity(imageEmbedding, textEmbedding);
  }

  /// Computes similarity between two embeddings.
  double cosineSimilarity(Float32List a, Float32List b) {
    return SiglipInference.cosineSimilarity(a, b);
  }

  /// Finds the best matching text for an image from a list of candidates.
  ///
  /// Returns the index of the best match and its similarity score.
  Future<(int index, double score)> findBestTextMatch(
    Uint8List imageBytes,
    List<String> candidates,
  ) async {
    final imageEmbedding = await embedImage(imageBytes);

    int bestIndex = -1;
    double bestScore = double.negativeInfinity;

    for (int i = 0; i < candidates.length; i++) {
      final textEmbedding = await embedText(candidates[i]);
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
