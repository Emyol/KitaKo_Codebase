import 'dart:typed_data';

/// Stub implementation for web platform where native ML is not available.
/// This file is used via conditional imports when running on web.
/// All methods throw UnsupportedError - the EmbeddingService falls back to mock mode.

/// Stub for SigLIP model versions
enum SiglipModelVersion {
  siglip2,
}

/// Stub for SigLIP model configuration
class SiglipModelConfig {
  final SiglipModelVersion version;
  final int vocabularySize;
  final int imageSize;
  final int imageChannels;
  final int maxTextLength;
  final int embeddingDimension;
  final String visionOutputTensorName;
  final String textOutputTensorName;
  final bool hasProjectionLayer;
  final List<double> imageMean;
  final List<double> imageStd;

  const SiglipModelConfig({
    required this.version,
    required this.vocabularySize,
    required this.imageSize,
    required this.imageChannels,
    required this.maxTextLength,
    required this.embeddingDimension,
    required this.visionOutputTensorName,
    required this.textOutputTensorName,
    required this.hasProjectionLayer,
    required this.imageMean,
    required this.imageStd,
  });

  static SiglipModelConfig forVersion(SiglipModelVersion version) {
    throw UnsupportedError('Not supported on web');
  }
}

class KitakoEmbeddingService {
  bool get isInitialized => false;
  bool get isImageEncoderReady => false;
  bool get isTextEncoderReady => false;

  Future<void> initialize({
    required String imageModelPath,
    required String textModelPath,
    required String tokenizerPath,
  }) async {
    throw UnsupportedError('KitakoEmbeddingService is not supported on web platform.');
  }

  Float32List embedText(String text) {
    throw UnsupportedError('Not supported on web');
  }

  Float32List embedImage(Uint8List imageBytes) {
    throw UnsupportedError('Not supported on web');
  }

  Float32List embedPreprocessedImage(Float32List preprocessedImage) {
    throw UnsupportedError('Not supported on web');
  }

  double cosineSimilarity(Float32List a, Float32List b) {
    throw UnsupportedError('Not supported on web');
  }

  void dispose() {}
}

/// Stub for model variant enum (web platform)
enum ModelVariant {
  kitakoFp32,
  kitakoMixed,
  kitakoInt8,
  siglip2Baseline;

  String get displayName {
    switch (this) {
      case ModelVariant.kitakoFp32:
        return 'Kitako FP32 (FP32+FP32)';
      case ModelVariant.kitakoMixed:
        return 'Kitako Mixed (FP32+INT8)';
      case ModelVariant.kitakoInt8:
        return 'Kitako INT8';
      case ModelVariant.siglip2Baseline:
        return 'SigLIP-2 Baseline';
    }
  }

  String get visionEncoderId {
    switch (this) {
      case ModelVariant.kitakoFp32:
      case ModelVariant.kitakoMixed:
        return 'kitako_vision_fp32';
      case ModelVariant.kitakoInt8:
        return 'kitako_vision_int8';
      case ModelVariant.siglip2Baseline:
        return 'siglip2_vision';
    }
  }

  String get textEncoderId {
    switch (this) {
      case ModelVariant.kitakoFp32:
        return 'kitako_text_fp32';
      case ModelVariant.kitakoMixed:
      case ModelVariant.kitakoInt8:
        return 'kitako_text_int8';
      case ModelVariant.siglip2Baseline:
        return 'siglip2_text';
    }
  }
}

/// Stub for ONNX-based embedding service (web platform)
class OnnxEmbeddingService {
  bool get isInitialized => false;
  bool get isImageEncoderReady => false;
  bool get isTextEncoderReady => false;

  SiglipModelConfig get modelConfig => throw UnsupportedError('Not supported on web');
  SiglipModelVersion get modelVersion => SiglipModelVersion.siglip2;
  String get imageEp => 'cpu';
  String get textEp => 'cpu';

  void initRuntime({SiglipModelVersion modelVersion = SiglipModelVersion.siglip2}) {
    throw UnsupportedError('OnnxEmbeddingService not supported on web');
  }

  Future<void> initialize({
    required String visionModelPath,
    required String textModelPath,
    required String tokenizerPath,
    SiglipModelVersion modelVersion = SiglipModelVersion.siglip2,
  }) async {
    throw UnsupportedError('OnnxEmbeddingService not supported on web');
  }

  Future<Float32List> embedText(String text) async {
    throw UnsupportedError('Not supported on web');
  }

  Future<Float32List> embedImage(Uint8List imageBytes) async {
    throw UnsupportedError('Not supported on web');
  }

  Float32List embedPreprocessedImage(Float32List preprocessedImage) {
    throw UnsupportedError('Not supported on web');
  }

  double cosineSimilarity(Float32List a, Float32List b) {
    throw UnsupportedError('Not supported on web');
  }

  void dispose() {}
}
