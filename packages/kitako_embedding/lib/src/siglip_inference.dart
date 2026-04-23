import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

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

      final sessionOptions = _buildSessionOptions();
      _imageSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isImageModelLoaded = true;
    } catch (e) {
      _isImageModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the image encoder model from a file path (not asset).
  ///
  /// Uses [OrtSession.fromFile] so the native runtime mmaps the model directly
  /// — avoids OOM on multi-GB FP32 weights that can't fit in the Dart heap.
  Future<void> loadImageModelFromFile(String filePath) async {
    try {
      final sessionOptions = _buildSessionOptions();
      _imageSession = OrtSession.fromFile(File(filePath), sessionOptions);
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

      final sessionOptions = _buildSessionOptions();
      _textSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isTextModelLoaded = true;
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the text encoder model from a file path (not asset).
  ///
  /// Uses [OrtSession.fromFile] so the native runtime mmaps the model directly
  /// — avoids OOM on multi-GB FP32 weights that can't fit in the Dart heap.
  Future<void> loadTextModelFromFile(String filePath) async {
    try {
      final sessionOptions = _buildSessionOptions();
      _textSession = OrtSession.fromFile(File(filePath), sessionOptions);
      _isTextModelLoaded = true;
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Builds session options with threading and platform GPU acceleration.
  ///
  /// Priority: NNAPI (Android) / CoreML (iOS/macOS) → CPU fallback.
  /// Each model load call creates its own options instance.
  OrtSessionOptions _buildSessionOptions() {
    final opts = OrtSessionOptions();
    // Native C++ thread pool for intra/inter operator parallelism.
    opts.setIntraOpNumThreads(4);
    opts.setInterOpNumThreads(2);

    // Platform-specific hardware acceleration (graceful fallback to CPU).
    if (Platform.isAndroid) {
      try {
        opts.appendNnapiProvider(NnapiFlags.useNone);
      } catch (_) {
        // NNAPI not available on this device — CPU will be used.
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      try {
        opts.appendCoreMLProvider(CoreMLFlags.useNone);
      } catch (_) {
        // CoreML not available — CPU will be used.
      }
    }

    return opts;
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
      // Run inference — runOnceAsync creates a fresh isolate per call so
      // multiple images can be embedded in parallel without hitting the
      // "isolate already processing" error.  The OrtSession is thread-safe
      // at the native C++ level and handles concurrent FFI calls correctly.
      final outputs = await _imageSession!.runOnceAsync(
        runOptions,
        {inputNames.first: inputOrt},
      );

      // Extract output tensor
      if (outputs.isEmpty) {
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

    // Ensure we have exactly maxTextLength tokens.
    //
    // GemmaTokenizer.encode() returns HF-style right-padded tokens
    // ([t0, ..., EOS, PAD, PAD, ...]) of length maxTextLength. If a caller
    // hands us raw, unpadded tokens we right-pad here too: keep the FIRST
    // maxTextLength so any trailing EOS is preserved relative to the content.
    List<int> paddedTokens;

    if (tokenIds.length >= maxTextLength) {
      paddedTokens = tokenIds.sublist(0, maxTextLength);
    } else {
      final padCount = maxTextLength - tokenIds.length;
      paddedTokens = [
        ...tokenIds,                         // real tokens first
        ...List<int>.filled(padCount, 0),    // PAD on the right
      ];
    }

    // Match external query pipeline policy: keep all mask positions visible.
    final attentionMask = List<int>.filled(maxTextLength, 1);

    // Create input tensors with shape [1, maxTextLength]
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
      // Build inputs — only include attention_mask if the model declares it.
      final inputMap = <String, OrtValueTensor>{inputNames[0]: inputIdsOrt};
      if (inputNames.length > 1) {
        inputMap[inputNames[1]] = attentionMaskOrt;
      }

      final outputs = await _textSession!.runOnceAsync(runOptions, inputMap);

      // Extract output tensor
      if (outputs.isEmpty) {
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
