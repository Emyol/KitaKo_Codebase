/// SigLIP model versions with their specific configurations
enum SiglipModelVersion {
  /// SigLIP-1 (base-patch16-224)
  /// - Vocabulary: ~32k tokens
  /// - Used by Xenova's original exports
  siglip1,

  /// SigLIP-2 (base-patch16-256)
  /// - Vocabulary: ~256k tokens (SentencePiece)
  /// - Improved multilingual support
  /// - Better semantic understanding
  siglip2,
}

/// Configuration for a specific SigLIP model version
class SiglipModelConfig {
  /// Model version identifier
  final SiglipModelVersion version;

  /// Expected vocabulary size for the tokenizer
  final int vocabularySize;

  /// Image input size (height and width)
  final int imageSize;

  /// Number of color channels
  final int imageChannels;

  /// Maximum text sequence length
  final int maxTextLength;

  /// Embedding output dimension
  final int embeddingDimension;

  /// Expected output tensor name for vision encoder
  /// Common names:
  /// - "pooler_output" for models with pooling head
  /// - "image_embeds" for models with projection layer
  /// - "last_hidden_state" for raw encoder output
  final String visionOutputTensorName;

  /// Expected output tensor name for text encoder
  /// Common names:
  /// - "pooler_output" for models with pooling head
  /// - "text_embeds" for models with projection layer
  /// - "last_hidden_state" for raw encoder output
  final String textOutputTensorName;

  /// Whether the model includes projection layers
  /// (maps encoder outputs to shared embedding space)
  final bool hasProjectionLayer;

  /// Image normalization mean values [R, G, B]
  final List<double> imageMean;

  /// Image normalization std values [R, G, B]
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

  /// Configuration for SigLIP-1 (base-patch16-224) - ALIGNED version
  /// Uses the correctly exported models with pooler_output (aligned embeddings)
  /// Output tensor name is 'image_features' / 'text_features'
  static const siglip1Config = SiglipModelConfig(
    version: SiglipModelVersion.siglip1,
    vocabularySize: 32000,
    imageSize: 224,
    imageChannels: 3,
    maxTextLength: 64,
    embeddingDimension: 768,
    visionOutputTensorName: 'image_features',  // New aligned model output
    textOutputTensorName: 'text_features',     // New aligned model output
    hasProjectionLayer: true,  // pooler_output IS aligned (no separate projection needed)
    imageMean: [0.5, 0.5, 0.5],
    imageStd: [0.5, 0.5, 0.5],
  );

  /// Configuration for SigLIP-2 (base-patch16-224)
  /// NOTE: The actual model expects 224x224 input (14x14=196 patches)
  /// despite the model name suggesting 256. This was determined by 
  /// runtime error analysis.
  static const siglip2Config = SiglipModelConfig(
    version: SiglipModelVersion.siglip2,
    vocabularySize: 256000,
    imageSize: 224, // Model expects 224x224 -> 14x14=196 patches
    imageChannels: 3,
    maxTextLength: 64,
    embeddingDimension: 768,
    visionOutputTensorName: 'pooler_output', // May need adjustment
    textOutputTensorName: 'pooler_output', // May need adjustment
    hasProjectionLayer: true, // SigLIP-2 should have projection
    imageMean: [0.5, 0.5, 0.5],
    imageStd: [0.5, 0.5, 0.5],
  );

  /// Get configuration for a specific model version
  static SiglipModelConfig forVersion(SiglipModelVersion version) {
    switch (version) {
      case SiglipModelVersion.siglip1:
        return siglip1Config;
      case SiglipModelVersion.siglip2:
        return siglip2Config;
    }
  }

  @override
  String toString() {
    return 'SiglipModelConfig('
        'version: ${version.name}, '
        'vocab: $vocabularySize, '
        'imageSize: ${imageSize}x$imageSize, '
        'embeddingDim: $embeddingDimension, '
        'projection: $hasProjectionLayer'
        ')';
  }
}
