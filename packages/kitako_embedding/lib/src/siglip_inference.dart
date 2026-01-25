import 'dart:io';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// SigLIP inference service for generating image and text embeddings.
///
/// This class handles TFLite model loading and inference for the KitaKo
/// SigLIP-based embedding models.
class SiglipInference {
  Interpreter? _imageInterpreter;
  Interpreter? _textInterpreter;

  bool _isImageModelLoaded = false;
  bool _isTextModelLoaded = false;

  /// Image model input shape: [1, 224, 224, 3] float32
  static const int imageSize = 224;
  static const int imageChannels = 3;

  /// Text model input shape: [1, 64] int64
  static const int maxTextLength = 64;

  /// Output embedding dimension
  static const int embeddingDim = 768;

  /// Whether the image encoder model is loaded
  bool get isImageModelLoaded => _isImageModelLoaded;

  /// Whether the text encoder model is loaded
  bool get isTextModelLoaded => _isTextModelLoaded;

  /// Loads the image encoder model from the given path.
  ///
  /// [modelPath] should be the full path to the .tflite file.
  /// For assets, use a method to copy to a temp directory first.
  Future<void> loadImageModel(String modelPath) async {
    try {
      _imageInterpreter = await Interpreter.fromAsset(modelPath);
      _isImageModelLoaded = true;
    } catch (e) {
      _isImageModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the image encoder model from a file path (not asset).
  Future<void> loadImageModelFromFile(String filePath) async {
    try {
      _imageInterpreter = Interpreter.fromFile(File(filePath));
      _isImageModelLoaded = true;
    } catch (e) {
      _isImageModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the text encoder model from the given asset path.
  Future<void> loadTextModel(String modelPath) async {
    try {
      _textInterpreter = await Interpreter.fromAsset(modelPath);
      _isTextModelLoaded = true;
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the text encoder model from a file path (not asset).
  Future<void> loadTextModelFromFile(String filePath) async {
    try {
      _textInterpreter = Interpreter.fromFile(File(filePath));
      _isTextModelLoaded = true;
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Generates an embedding from a preprocessed image.
  ///
  /// [imageData] must be a Float32List of shape [1, 224, 224, 3]
  /// with values normalized to [-1, 1] (mean=0.5, std=0.5 applied).
  ///
  /// Returns a Float32List of length 768 (the embedding vector).
  Float32List embedImage(Float32List imageData) {
    if (!_isImageModelLoaded || _imageInterpreter == null) {
      throw StateError('Image model not loaded. Call loadImageModel first.');
    }

    // Validate input size: 1 * 224 * 224 * 3 = 150528
    const expectedSize = 1 * imageSize * imageSize * imageChannels;
    if (imageData.length != expectedSize) {
      throw ArgumentError(
        'Invalid image data size. Expected $expectedSize, got ${imageData.length}',
      );
    }

    // Reshape input to [1, 224, 224, 3]
    final input = imageData.reshape([1, imageSize, imageSize, imageChannels]);

    // Prepare output buffer [1, 768]
    final output = List.filled(1 * embeddingDim, 0.0).reshape([1, embeddingDim]);

    // Run inference
    _imageInterpreter!.run(input, output);

    // Extract and return the embedding
    return Float32List.fromList((output[0] as List).cast<double>().map((e) => e.toDouble()).toList());
  }

  /// Generates an embedding from tokenized text.
  ///
  /// [tokenIds] must be an Int64List (or List<int>) of shape [1, 64].
  /// Shorter sequences should be padded with 0 (pad token).
  ///
  /// Returns a Float32List of length 768 (the embedding vector).
  Float32List embedText(List<int> tokenIds) {
    if (!_isTextModelLoaded || _textInterpreter == null) {
      throw StateError('Text model not loaded. Call loadTextModel first.');
    }

    // Ensure we have exactly maxTextLength tokens
    List<int> paddedTokens;
    if (tokenIds.length >= maxTextLength) {
      paddedTokens = tokenIds.sublist(0, maxTextLength);
    } else {
      paddedTokens = List<int>.from(tokenIds)
        ..addAll(List.filled(maxTextLength - tokenIds.length, 0)); // pad with 0
    }

    // TFLite expects int64, reshape to [1, 64]
    // Note: Dart's tflite_flutter handles int64 as List<int> internally
    final input = [paddedTokens];

    // Prepare output buffer [1, 768]
    final output = List.filled(1 * embeddingDim, 0.0).reshape([1, embeddingDim]);

    // Run inference
    _textInterpreter!.run(input, output);

    // Extract and return the embedding
    return Float32List.fromList((output[0] as List).cast<double>().map((e) => e.toDouble()).toList());
  }

  /// Computes cosine similarity between two embeddings.
  ///
  /// Returns a value between -1 and 1, where 1 means identical.
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError('Embeddings must have the same length');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0.0;

    return dotProduct / (_sqrt(normA) * _sqrt(normB));
  }

  /// Releases resources held by the interpreters.
  void dispose() {
    _imageInterpreter?.close();
    _textInterpreter?.close();
    _imageInterpreter = null;
    _textInterpreter = null;
    _isImageModelLoaded = false;
    _isTextModelLoaded = false;
  }
}

/// Helper for sqrt (avoid importing dart:math just for this)
double _sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}

/// Extension to reshape lists for TFLite input/output
extension ListReshape<T> on List<T> {
  List reshape(List<int> shape) {
    if (shape.length == 1) {
      return this;
    } else if (shape.length == 2) {
      final rows = shape[0];
      final cols = shape[1];
      return List.generate(rows, (i) => sublist(i * cols, (i + 1) * cols));
    } else if (shape.length == 4) {
      final batch = shape[0];
      final height = shape[1];
      final width = shape[2];
      final channels = shape[3];
      final result = <List<List<List<T>>>>[];
      int idx = 0;
      for (int b = 0; b < batch; b++) {
        final batchData = <List<List<T>>>[];
        for (int h = 0; h < height; h++) {
          final rowData = <List<T>>[];
          for (int w = 0; w < width; w++) {
            final pixel = <T>[];
            for (int c = 0; c < channels; c++) {
              pixel.add(this[idx++]);
            }
            rowData.add(pixel);
          }
          batchData.add(rowData);
        }
        result.add(batchData);
      }
      return result;
    }
    throw UnsupportedError('Reshape only supports 1D, 2D, and 4D shapes');
  }
}
