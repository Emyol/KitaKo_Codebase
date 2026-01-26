/// KitaKo Core Constants
///
/// Defines shared constants used across the KitaKo packages.

/// Default embedding dimension for SigLIP models
const int kDefaultEmbeddingDim = 768;

/// Default image size for SigLIP models
const int kDefaultImageSize = 224;

/// Default max text length for tokenization
const int kDefaultMaxTextLength = 64;

/// Default number of search results to return
const int kDefaultTopK = 10;

/// Default efSearch parameter for HNSW queries
const int kDefaultEfSearch = 100;

/// Default HNSW M parameter for index building
const int kDefaultHnswM = 16;

/// Default HNSW efConstruction parameter
const int kDefaultHnswEfConstruction = 200;

/// Model filenames
class ModelFiles {
  static const String imageEncoder = 'kitako_image_encoder_int8.tflite';
  static const String textEncoder = 'kitako_text_encoder_dynamic.tflite';
  static const String tokenizer = 'tokenizer.json';
  static const String annIndex = 'ann_index.bin';
  static const String annIndexMeta = 'ann_index.meta.json';
}

/// Asset paths
class AssetPaths {
  static const String modelDir = 'assets/model';
  static const String indexDir = 'assets/index';
  static const String tokenizerDir = 'assets/tokenizer';
  
  static const String imageEncoder = '$modelDir/image_encoder/${ModelFiles.imageEncoder}';
  static const String textEncoder = '$modelDir/text_encoder/${ModelFiles.textEncoder}';
  static const String tokenizer = '$tokenizerDir/${ModelFiles.tokenizer}';
  static const String annIndex = '$indexDir/${ModelFiles.annIndex}';
  static const String annIndexMeta = '$indexDir/${ModelFiles.annIndexMeta}';
}
