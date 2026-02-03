import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// SigLIP inference service for generating image and text embeddings.
///
/// This class handles ONNX model loading and inference for the KitaKo
/// SigLIP-based embedding models.
class SiglipInference {
  OrtSession? _imageSession;
  OrtSession? _textSession;

  bool _isImageModelLoaded = false;
  bool _isTextModelLoaded = false;

  /// Image model input shape: [1, 3, 224, 224] float32 (NCHW format)
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

  /// Loads the image encoder model from the given asset path.
  ///
  /// [modelPath] should be the asset path to the .onnx file.
  Future<void> loadImageModel(String modelPath) async {
    try {
      // Load model from assets
      final modelData = await rootBundle.load(modelPath);
      final modelBytes = modelData.buffer.asUint8List();

      final sessionOptions = OrtSessionOptions();
      // Enable multi-threading for faster inference
      sessionOptions.setIntraOpNumThreads(4);
      sessionOptions.setInterOpNumThreads(2);
      _imageSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isImageModelLoaded = true;
    } catch (e) {
      _isImageModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the image encoder model from a file path (not asset).
  Future<void> loadImageModelFromFile(String filePath) async {
    try {
      // Read file as bytes to avoid path encoding issues on Windows
      final file = File(filePath);
      final modelBytes = await file.readAsBytes();
      
      final sessionOptions = OrtSessionOptions();
      // Enable multi-threading for faster inference
      sessionOptions.setIntraOpNumThreads(4);
      sessionOptions.setInterOpNumThreads(2);
      _imageSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isImageModelLoaded = true;
    } catch (e) {
      _isImageModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the text encoder model from the given asset path.
  Future<void> loadTextModel(String modelPath) async {
    try {
      // Load model from assets
      final modelData = await rootBundle.load(modelPath);
      final modelBytes = modelData.buffer.asUint8List();

      final sessionOptions = OrtSessionOptions();
      // Enable multi-threading for faster inference
      sessionOptions.setIntraOpNumThreads(4);
      sessionOptions.setInterOpNumThreads(2);
      _textSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isTextModelLoaded = true;
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the text encoder model from a file path (not asset).
  Future<void> loadTextModelFromFile(String filePath) async {
    try {
      // Read file as bytes to avoid path encoding issues on Windows
      final file = File(filePath);
      final modelBytes = await file.readAsBytes();
      
      final sessionOptions = OrtSessionOptions();
      // Enable multi-threading for faster inference
      sessionOptions.setIntraOpNumThreads(4);
      sessionOptions.setInterOpNumThreads(2);
      _textSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isTextModelLoaded = true;
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Generates an embedding from a preprocessed image.
  ///
  /// [imageData] must be a Float32List of shape [1, 3, 224, 224] (NCHW format)
  /// with values normalized to [-1, 1] (mean=0.5, std=0.5 applied).
  ///
  /// Returns a Float32List of length 768 (the embedding vector).
  Future<Float32List> embedImage(Float32List imageData) async {
    if (!_isImageModelLoaded || _imageSession == null) {
      throw StateError('Image model not loaded. Call loadImageModel first.');
    }

    // Validate input size: 1 * 3 * 224 * 224 = 150528
    const expectedSize = 1 * imageChannels * imageSize * imageSize;
    if (imageData.length != expectedSize) {
      throw ArgumentError(
        'Invalid image data size. Expected $expectedSize, got ${imageData.length}',
      );
    }

    // Create input tensor with shape [1, 3, 224, 224] (NCHW format)
    // IMPORTANT: Use Float32List directly to ensure tensor(float) type, not tensor(double)
    final inputOrt = OrtValueTensor.createTensorWithDataList(
      imageData,
      [1, imageChannels, imageSize, imageSize],
    );

    // Get input name from the model
    final inputNames = _imageSession!.inputNames;
    final runOptions = OrtRunOptions();

    try {
      // Run inference
      final outputs = await _imageSession!.runAsync(
        runOptions,
        {inputNames.first: inputOrt},
      );

      // Extract output tensor
      if (outputs == null || outputs.isEmpty) {
        throw StateError('Model produced no output');
      }

      final outputTensor = outputs.first;
      if (outputTensor == null) {
        throw StateError('Output tensor is null');
      }

      // Get the embedding data - output shape is [1, 768]
      final outputValue = outputTensor.value;
      Float32List embedding;

      if (outputValue is List) {
        // Handle nested list output [1, 768] -> [[...]]
        if (outputValue.isNotEmpty && outputValue.first is List) {
          final innerList = outputValue.first as List;
          embedding = Float32List.fromList(
            innerList.map((e) => (e as num).toDouble()).toList(),
          );
        } else {
          // Handle flat list
          embedding = Float32List.fromList(
            outputValue.map((e) => (e as num).toDouble()).toList(),
          );
        }
      } else if (outputValue is Float32List) {
        embedding = outputValue;
      } else {
        throw StateError('Unexpected output type: ${outputValue.runtimeType}');
      }

      // Clean up
      inputOrt.release();
      runOptions.release();
      for (final output in outputs) {
        output?.release();
      }

      return embedding;
    } catch (e) {
      inputOrt.release();
      runOptions.release();
      rethrow;
    }
  }

  /// Generates an embedding from tokenized text.
  ///
  /// [tokenIds] must be a List<int> of shape [1, 32].
  /// Shorter sequences should be padded with 0 (pad token).
  ///
  /// Returns a Float32List of length 768 (the embedding vector).
  Future<Float32List> embedText(List<int> tokenIds) async {
    if (!_isTextModelLoaded || _textSession == null) {
      throw StateError('Text model not loaded. Call loadTextModel first.');
    }

    // Ensure we have exactly maxTextLength tokens
    List<int> paddedTokens;
    List<int> attentionMask;

    if (tokenIds.length >= maxTextLength) {
      paddedTokens = tokenIds.sublist(0, maxTextLength);
      attentionMask = List.filled(maxTextLength, 1); // All tokens are real
    } else {
      paddedTokens = List<int>.from(tokenIds)
        ..addAll(List.filled(maxTextLength - tokenIds.length, 0)); // pad with 0

      // Attention mask: 1 for real tokens, 0 for padding
      attentionMask = List.filled(tokenIds.length, 1)
        ..addAll(List.filled(maxTextLength - tokenIds.length, 0));
    }

    // Create input tensors with shape [1, 32]
    final inputIdsOrt = OrtValueTensor.createTensorWithDataList(
      paddedTokens,
      [1, maxTextLength],
    );

    final attentionMaskOrt = OrtValueTensor.createTensorWithDataList(
      attentionMask,
      [1, maxTextLength],
    );

    // Get input names from the model
    final inputNames = _textSession!.inputNames;
    final runOptions = OrtRunOptions();

    try {
      // Run inference with both input_ids and attention_mask
      final outputs = await _textSession!.runAsync(
        runOptions,
        {
          inputNames[0]: inputIdsOrt,  // Usually 'input_ids'
          inputNames[1]: attentionMaskOrt,  // Usually 'attention_mask'
        },
      );

      // Extract output tensor
      if (outputs == null || outputs.isEmpty) {
        throw StateError('Model produced no output');
      }

      final outputTensor = outputs.first;
      if (outputTensor == null) {
        throw StateError('Output tensor is null');
      }

      // Get the embedding data - output shape is [1, 768]
      final outputValue = outputTensor.value;
      Float32List embedding;

      if (outputValue is List) {
        // Handle nested list output [1, 768] -> [[...]]
        if (outputValue.isNotEmpty && outputValue.first is List) {
          final innerList = outputValue.first as List;
          embedding = Float32List.fromList(
            innerList.map((e) => (e as num).toDouble()).toList(),
          );
        } else {
          // Handle flat list
          embedding = Float32List.fromList(
            outputValue.map((e) => (e as num).toDouble()).toList(),
          );
        }
      } else if (outputValue is Float32List) {
        embedding = outputValue;
      } else {
        throw StateError('Unexpected output type: ${outputValue.runtimeType}');
      }

      // Clean up
      inputIdsOrt.release();
      attentionMaskOrt.release();
      runOptions.release();
      for (final output in outputs) {
        output?.release();
      }

      return embedding;
    } catch (e) {
      inputIdsOrt.release();
      attentionMaskOrt.release();
      runOptions.release();
      rethrow;
    }
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

  /// Releases resources held by the ONNX sessions.
  void dispose() {
    _imageSession?.release();
    _textSession?.release();
    _imageSession = null;
    _textSession = null;
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
