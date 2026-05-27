import 'dart:typed_data';

import 'image_preprocessor.dart';
import 'siglip_inference.dart';
import 'gemma_tokenizer.dart';
import 'siglip_model_config.dart';

/// ONNX-based embedding service for KitaKo SigLIP models.
///
/// Wraps [SiglipInference] and [GemmaTokenizer] to provide a high-level API
/// for generating image and text embeddings from file-path-based ONNX models.
class OnnxEmbeddingService {
  final SiglipInference _inference = SiglipInference();
  final GemmaTokenizer _tokenizer = GemmaTokenizer();

  bool _isInitialized = false;
  late SiglipModelConfig _modelConfig;

  /// Whether the service is fully initialized.
  bool get isInitialized => _isInitialized;

  /// Whether the image encoder is ready.
  bool get isImageEncoderReady => _inference.isImageModelLoaded;

  /// Whether the text encoder is ready.
  bool get isTextEncoderReady =>
      _inference.isTextModelLoaded && _tokenizer.isLoaded;

  /// Active model configuration.
  SiglipModelConfig get modelConfig => _modelConfig;

  /// Active model version.
  SiglipModelVersion get modelVersion =>
      _isInitialized ? _modelConfig.version : SiglipModelVersion.siglip2;

  /// Active execution provider for each encoder ('nnapi', 'coreml', 'xnnpack', 'cpu').
  String get imageEp => _inference.imageEp;
  String get textEp => _inference.textEp;

  /// Initializes the service with the given model file paths.
  ///
  /// [visionModelPath] and [textModelPath] must be file system paths to `.onnx`
  /// files. [tokenizerPath] may be a Flutter asset path ('assets/...') or a
  /// file system path.
  Future<void> initialize({
    required String visionModelPath,
    required String textModelPath,
    required String tokenizerPath,
    SiglipModelVersion modelVersion = SiglipModelVersion.siglip2,
  }) async {
    _modelConfig = SiglipModelConfig.forVersion(modelVersion);
    await _inference.loadImageModelFromFile(visionModelPath);
    await _inference.loadTextModelFromFile(textModelPath);
    await _tokenizer.loadFromAsset(tokenizerPath);
    _isInitialized = true;
  }

  /// Returns the byte-fallback ratio for the given text (0.0 = all known
  /// tokens, 1.0 = all byte-fallback). See [GemmaTokenizer.byteFallbackRatio].
  double byteFallbackRatio(String text) => _tokenizer.byteFallbackRatio(text);

  /// Generates a normalized embedding for raw image bytes.
  Future<Float32List> embedImage(Uint8List imageBytes) async {
    if (!isImageEncoderReady) {
      throw StateError('Image encoder not ready. Call initialize() first.');
    }
    final preprocessed =
        await ImagePreprocessor.preprocessImageAsync(imageBytes);
    final embedding = await _inference.embedImage(preprocessed);
    return _l2Normalize(embedding);
  }

  /// Generates a normalized embedding from pre-decoded RGBA bytes.
  ///
  /// Prefer this over [embedImage] when the caller already holds decoded
  /// pixels (e.g. from [dart:ui.instantiateImageCodec]), since it skips
  /// the full-resolution JPEG decode step.
  Future<Float32List> embedImageFromRgba(
      Uint8List rgba, int width, int height) async {
    if (!isImageEncoderReady) {
      throw StateError('Image encoder not ready. Call initialize() first.');
    }
    final preprocessed =
        await ImagePreprocessor.preprocessRgbaAsync(rgba, width, height);
    final embedding = await _inference.embedImage(preprocessed);
    return _l2Normalize(embedding);
  }

  /// Generates a normalized embedding for a text query.
  Future<Float32List> embedText(String text) async {
    if (!isTextEncoderReady) {
      throw StateError('Text encoder not ready. Call initialize() first.');
    }
    final tokens = _tokenizer.encode(text);
    final embedding = await _inference.embedText(tokens);
    return _l2Normalize(embedding);
  }

  /// Computes cosine similarity between two normalized embeddings.
  double cosineSimilarity(Float32List a, Float32List b) {
    return SiglipInference.cosineSimilarity(a, b);
  }

  /// Releases all resources.
  void dispose() {
    _inference.dispose();
    _isInitialized = false;
  }

  Float32List _l2Normalize(Float32List v) {
    double norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    if (norm == 0) return v;
    norm = _sqrt(norm);
    final out = Float32List(v.length);
    for (int i = 0; i < v.length; i++) {
      out[i] = v[i] / norm;
    }
    return out;
  }
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double g = x / 2;
  for (int i = 0; i < 20; i++) {
    g = (g + x / g) / 2;
  }
  return g;
}
