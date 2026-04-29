/// KitaKo Embedding Package
///
/// Provides SigLIP-based image and text embedding generation for the
/// KitaKo application.
library kitako_embedding;

export 'src/embedding_service.dart';
export 'src/image_preprocessor.dart';
export 'src/siglip_inference.dart';
export 'src/gemma_tokenizer.dart';

// ONNX-based inference (alternative to TFLite)
export 'src/onnx_embedding_service.dart';
export 'src/onnx_siglip_inference.dart';
export 'src/siglip_model_config.dart';

// Face recognition pipeline (optional — gracefully degrades if models missing)
export 'src/face/face.dart';
