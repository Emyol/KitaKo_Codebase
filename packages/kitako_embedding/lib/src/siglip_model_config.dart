// SigLIP model configurations and variant definitions for KitaKo.

/// SigLIP model version identifier.
enum SiglipModelVersion {
  siglip2,
}

/// Configuration parameters for a SigLIP model variant.
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

  /// Returns the default config for the given model version.
  static SiglipModelConfig forVersion(SiglipModelVersion version) {
    switch (version) {
      case SiglipModelVersion.siglip2:
        return const SiglipModelConfig(
          version: SiglipModelVersion.siglip2,
          vocabularySize: 256000,
          imageSize: 224,
          imageChannels: 3,
          maxTextLength: 64,
          embeddingDimension: 768,
          visionOutputTensorName: 'image_embeds',
          textOutputTensorName: 'text_embeds',
          hasProjectionLayer: true,
          imageMean: [0.5, 0.5, 0.5],
          imageStd: [0.5, 0.5, 0.5],
        );
    }
  }

  @override
  String toString() =>
      'SiglipModelConfig(version: $version, imageSize: $imageSize, '
      'embeddingDim: $embeddingDimension, maxTextLength: $maxTextLength)';
}

/// Available model variants for KitaKo embedding.
enum ModelVariant {
  /// Kitako custom model: FP32 vision encoder + FP32 text encoder.
  kitakoFp32,

  /// Kitako custom model: FP32 vision encoder + INT8 text encoder.
  kitakoMixed,

  /// Kitako custom model: all INT8 quantized.
  kitakoInt8,

  /// SigLIP-2 baseline (Google's original weights).
  siglip2Baseline;

  /// Human-readable name for the variant.
  String get displayName {
    switch (this) {
      case ModelVariant.kitakoFp32:
        return 'Kitako FP32 (fp32 img + fp32 txt)';
      case ModelVariant.kitakoMixed:
        return 'Kitako Mixed (fp32 img + int8 txt)';
      case ModelVariant.kitakoInt8:
        return 'Kitako INT8 (int8 img + int8 txt)';
      case ModelVariant.siglip2Baseline:
        return 'SigLIP-2 Baseline';
    }
  }

  /// Stable identifier for the vision encoder used by this variant.
  ///
  /// Embedding caches are keyed by this ID so variants that share the same
  /// vision tower (e.g. [kitakoFp32] and [kitakoMixed]) can share image
  /// embeddings without re-embedding on model switch.
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

  /// Stable identifier for the text encoder used by this variant.
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
