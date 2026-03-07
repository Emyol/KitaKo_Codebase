import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kitako_core/kitako_core.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// ONNX-based face embedding generator using ArcFace (MobileFaceNet backbone).
///
/// Generates 512-dimensional L2-normalized face embeddings from aligned
/// 112×112 face crops. These embeddings can be compared using cosine
/// similarity to determine if two faces belong to the same person.
///
/// ## Model Details
/// - **Model**: ArcFace w600k_mbf (MobileFaceNet backbone)
/// - **Input**: Aligned face [1, 3, 112, 112] NCHW Float32
/// - **Output**: 512-dim Float32 embedding, L2-normalized
/// - **Size**: ~12 MB
/// - **Accuracy**: 99.6% on LFW benchmark
///
/// ## Graceful Degradation
/// If the model is not available or fails to load, [isReady] returns false
/// and all embedding methods throw [FaceEmbeddingException] or return null.
/// The rest of the KitaKo system continues to function normally.
class OnnxFaceEmbedder {
  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _isReady = false;

  /// Face input size (must be aligned to this before embedding)
  static const int inputSize = kFaceInputSize;

  /// Output embedding dimension
  static const int embeddingDim = kFaceEmbeddingDim;

  /// Whether the embedder model is loaded and ready
  bool get isReady => _isReady;

  /// Initialize the ONNX Runtime environment for face embedding.
  void initialize() {
    try {
      OrtEnv.instance.init();
      _sessionOptions = OrtSessionOptions();
      debugPrint('OnnxFaceEmbedder: Initialized');
    } catch (e) {
      debugPrint('OnnxFaceEmbedder: Init (may already be initialized): $e');
      _sessionOptions ??= OrtSessionOptions();
    }
  }

  /// Load the ArcFace embedding model from a file path or asset.
  ///
  /// Returns true if successful, false otherwise. Does NOT throw.
  Future<bool> loadModel(String modelPath) async {
    try {
      if (_sessionOptions == null) initialize();

      if (modelPath.startsWith('assets/')) {
        final data = await rootBundle.load(modelPath);
        final bytes = data.buffer.asUint8List();
        _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      } else {
        final file = File(modelPath);
        if (!await file.exists()) {
          debugPrint('OnnxFaceEmbedder: Model file not found: $modelPath');
          return false;
        }
        _session = OrtSession.fromFile(file, _sessionOptions!);
      }

      _isReady = true;
      debugPrint('OnnxFaceEmbedder: Model loaded from $modelPath');

      if (_session != null) {
        debugPrint('OnnxFaceEmbedder: Input names: ${_session!.inputNames}');
        debugPrint('OnnxFaceEmbedder: Output names: ${_session!.outputNames}');
      }

      return true;
    } catch (e) {
      _isReady = false;
      debugPrint('OnnxFaceEmbedder: Failed to load model: $e');
      return false;
    }
  }

  /// Generate a face embedding from an aligned face tensor.
  ///
  /// Parameters:
  /// - [alignedFace]: NCHW Float32 [1, 3, 112, 112] preprocessed face
  ///   (normalized to [-1, 1] using (pixel/255 - 0.5) / 0.5)
  ///
  /// Returns a 512-dim L2-normalized Float32List,
  /// or null if embedding fails.
  Float32List? embedFace(Float32List alignedFace) {
    if (!_isReady || _session == null) {
      debugPrint('OnnxFaceEmbedder: Not ready');
      return null;
    }

    final shape = [1, 3, inputSize, inputSize];
    final inputTensor =
        OrtValueTensor.createTensorWithDataList(alignedFace, shape);
    final runOptions = OrtRunOptions();

    // Try common input names
    final inputName = _session!.inputNames.isNotEmpty
        ? _session!.inputNames.first
        : 'input';
    final inputs = {inputName: inputTensor};

    try {
      final outputs = _session!.run(runOptions, inputs);

      // Extract the embedding from the first non-null output
      Float32List? embedding;
      for (final output in outputs) {
        if (output == null) continue;
        final value = output.value;

        if (value is List && value.isNotEmpty) {
          if (value.first is List) {
            // Shape [1, 512] — nested list of num
            final inner = value.first as List;
            embedding = Float32List.fromList(
                inner.map((e) => (e as num).toDouble()).toList());
            break;
          } else if (value.first is num) {
            // Shape [512] — flat list of num
            embedding = Float32List.fromList(
                value.map((e) => (e as num).toDouble()).toList());
            break;
          }
        }
      }

      if (embedding == null) {
        debugPrint('OnnxFaceEmbedder: Could not extract embedding from output');
        return null;
      }

      final normalized = _l2Normalize(embedding);

      // Release resources
      inputTensor.release();
      runOptions.release();
      for (final output in outputs) {
        output?.release();
      }

      return normalized;
    } catch (e) {
      debugPrint('OnnxFaceEmbedder: Embedding failed: $e');
      inputTensor.release();
      runOptions.release();
      return null;
    }
  }

  /// L2-normalize a vector to unit length.
  Float32List _l2Normalize(Float32List vector) {
    double sumOfSquares = 0.0;
    for (final v in vector) {
      sumOfSquares += v * v;
    }
    final norm = math.sqrt(sumOfSquares);

    if (norm == 0) return vector;

    final normalized = Float32List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      normalized[i] = vector[i] / norm;
    }
    return normalized;
  }

  /// Release all resources.
  void dispose() {
    _session?.release();
    _sessionOptions?.release();
    _session = null;
    _sessionOptions = null;
    _isReady = false;
    debugPrint('OnnxFaceEmbedder: Disposed');
  }
}
