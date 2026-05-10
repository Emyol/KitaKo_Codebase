import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

/// Serializes async work onto a single queue. Each `run` call resolves
/// in submission order, regardless of how long earlier calls take. Used
/// here to prevent two `OrtSession.runOnceAsync` calls from being in
/// flight against the same session at the same time — even when ORT
/// claims to be thread-safe at the native level, EP backends (NNAPI in
/// particular) and the Dart ↔ FFI bridge bookkeeping have produced
/// hard crashes on concurrent calls in practice.
class _InferenceQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await fn());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }
}

/// SigLIP inference service for generating image and text embeddings.
///
/// This class handles ONNX model loading and inference for the KitaKo
/// SigLIP-based embedding models.
class SiglipInference {
  OrtSession? _imageSession;
  OrtSession? _textSession;

  bool _isImageModelLoaded = false;
  bool _isTextModelLoaded = false;

  /// Which execution provider is active for each encoder.
  /// One of: 'nnapi', 'coreml', 'xnnpack', 'cpu'.
  String _imageEp = 'cpu';
  String _textEp = 'cpu';

  String get imageEp => _imageEp;
  String get textEp => _textEp;

  /// One queue per session — image and text inference can still run in
  /// parallel relative to each other, but calls targeting the same
  /// session are serialized.
  final _InferenceQueue _imageQueue = _InferenceQueue();
  final _InferenceQueue _textQueue = _InferenceQueue();

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
      final modelData = await rootBundle.load(modelPath);
      final modelBytes = modelData.buffer.asUint8List();

      final (sessionOptions, ep) = _buildSessionOptions();
      _imageSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isImageModelLoaded = true;
      _imageEp = ep;
      await _warmupImageSession();
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
      final (sessionOptions, ep) = _buildSessionOptions();
      _imageSession = OrtSession.fromFile(File(filePath), sessionOptions);
      _isImageModelLoaded = true;
      _imageEp = ep;
      await _warmupImageSession();
    } catch (e) {
      _isImageModelLoaded = false;
      rethrow;
    }
  }

  /// Loads the text encoder model from the given asset path.
  Future<void> loadTextModel(String modelPath) async {
    try {
      final modelData = await rootBundle.load(modelPath);
      final modelBytes = modelData.buffer.asUint8List();

      final (sessionOptions, ep) = _buildSessionOptions();
      _textSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
      _isTextModelLoaded = true;
      _textEp = ep;
      await _warmupTextSession();
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
      final (sessionOptions, ep) = _buildSessionOptions();
      _textSession = OrtSession.fromFile(File(filePath), sessionOptions);
      _isTextModelLoaded = true;
      _textEp = ep;
      await _warmupTextSession();
    } catch (e) {
      _isTextModelLoaded = false;
      rethrow;
    }
  }

  /// Builds session options and returns the active EP name.
  ///
  /// Priority: NNAPI (Android) / CoreML (iOS/macOS) → XNNPACK → plain CPU.
  /// When a hardware accelerator is active the Dart-side thread counts are
  /// reduced to 1+1 so we don't contend with the EP's own thread pool.
  (OrtSessionOptions, String) _buildSessionOptions() {
    final opts = OrtSessionOptions();

    // All-optimizations: constant folding, operator fusion, etc.
    opts.setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

    // Default thread counts for CPU path (overridden below if EP active).
    opts.setIntraOpNumThreads(4);
    opts.setInterOpNumThreads(2);

    String ep = 'cpu';
    bool acceleratorActive = false;

    if (Platform.isAndroid) {
      // Try FP16 first — enables GPU/DSP acceleration on most Android SoCs.
      // Fall back to useNone (CPU NNAPI) if the device doesn't support it.
      try {
        acceleratorActive = opts.appendNnapiProvider(NnapiFlags.useFp16);
        if (acceleratorActive) ep = 'nnapi-fp16';
      } catch (_) {}
      if (!acceleratorActive) {
        try {
          acceleratorActive = opts.appendNnapiProvider(NnapiFlags.useNone);
          if (acceleratorActive) ep = 'nnapi';
        } catch (_) {}
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      try {
        acceleratorActive = opts.appendCoreMLProvider(CoreMLFlags.useNone);
        if (acceleratorActive) ep = 'coreml';
      } catch (_) {}
    }

    if (acceleratorActive) {
      // Hardware EP manages its own threads — minimise Dart-side overhead.
      opts.setIntraOpNumThreads(1);
      opts.setInterOpNumThreads(1);
    } else {
      // No hardware EP — try XNNPACK as optimised CPU backend.
      // appendXnnpackProvider reads intraOpNumThreads, so set it first.
      try {
        final ok = opts.appendXnnpackProvider();
        if (ok) ep = 'xnnpack';
      } catch (_) {}
    }

    return (opts, ep);
  }

  /// Runs a single zero-input forward pass to trigger EP/JIT compilation.
  Future<void> _warmupImageSession() async {
    try {
      final zeros = Float32List(1 * imageChannels * imageSize * imageSize);
      await embedImage(zeros);
    } catch (_) {
      // Warmup failure is non-fatal — inference will still work, just slower
      // on the first real call.
    }
  }

  Future<void> _warmupTextSession() async {
    try {
      final zeros = List<int>.filled(maxTextLength, 0);
      await embedText(zeros);
    } catch (_) {}
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
      // Run inference. `runOnceAsync` creates a fresh isolate per call,
      // and the inference queue serializes submissions so we never have
      // two FFI run calls in flight against the same session — that
      // combination has crashed the app on some devices despite ORT's
      // claim of native thread-safety.
      final outputs = await _imageQueue.run(
        () => _imageSession!.runOnceAsync(
          runOptions,
          {inputNames.first: inputOrt},
        ),
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

      final outputs =
          await _textQueue.run(() => _textSession!.runOnceAsync(runOptions, inputMap));

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
