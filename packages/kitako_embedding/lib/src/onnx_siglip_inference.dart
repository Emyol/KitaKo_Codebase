import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'siglip_model_config.dart';

/// ONNX-based SigLIP inference service.
///
/// This service uses ONNX Runtime to run the SigLIP vision and text encoders,
/// as an alternative to TFLite which has op version compatibility issues.
///
/// Supports multiple SigLIP model versions (SigLIP-1, SigLIP-2) with
/// configurable parameters.
class OnnxSiglipInference {
  OrtSession? _visionSession;
  OrtSession? _textSession;
  OrtSessionOptions? _sessionOptions;

  bool _isVisionReady = false;
  bool _isTextReady = false;

  /// Current model configuration
  SiglipModelConfig _config = SiglipModelConfig.siglip1Config;

  /// Image input shape: [1, 3, size, size] (NCHW format)
  int get imageSize => _config.imageSize;
  int get imageChannels => _config.imageChannels;

  /// Text input shape: [1, maxLength]
  int get maxTextLength => _config.maxTextLength;

  /// Output embedding dimension
  int get embeddingDim => _config.embeddingDimension;

  bool get isVisionReady => _isVisionReady;
  bool get isTextReady => _isTextReady;
  bool get isReady => _isVisionReady || _isTextReady;

  /// Get current model configuration
  SiglipModelConfig get config => _config;

  /// Get current model version
  SiglipModelVersion get modelVersion => _config.version;

  /// Initialize the ONNX Runtime environment with optional model configuration.
  ///
  /// [modelVersion] - Which SigLIP model version to use (defaults to SigLIP-1)
  void initialize({SiglipModelVersion modelVersion = SiglipModelVersion.siglip1}) {
    _config = SiglipModelConfig.forVersion(modelVersion);
    debugPrint('OnnxSiglipInference: Configured for ${_config.version.name}');
    debugPrint('OnnxSiglipInference: Config: $_config');

    OrtEnv.instance.init();
    _sessionOptions = OrtSessionOptions()..setIntraOpNumThreads(4);

    if (Platform.isAndroid) {
      // NNAPI dispatches supported ops to GPU/DSP/NPU; CPU handles the rest.
      try {
        _sessionOptions!.appendNnapiProvider(NnapiFlags.useNone);
        debugPrint('OnnxSiglipInference: NNAPI execution provider enabled');
      } catch (e) {
        debugPrint('OnnxSiglipInference: NNAPI unavailable: $e');
      }

      // XNNPACK accelerates ARM SIMD ops — coexists safely with NNAPI.
      try {
        _sessionOptions!.appendXnnpackProvider();
        debugPrint('OnnxSiglipInference: XNNPACK execution provider enabled');
      } catch (e) {
        debugPrint('OnnxSiglipInference: XNNPACK unavailable: $e');
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      try {
        _sessionOptions!.appendCoreMLProvider(CoreMLFlags.useNone);
        debugPrint('OnnxSiglipInference: CoreML execution provider enabled');
      } catch (e) {
        debugPrint('OnnxSiglipInference: CoreML unavailable: $e');
      }
    }
  }

  /// Load the vision encoder model.
  ///
  /// [modelPath] can be an asset path or a file path.
  Future<void> loadVisionModel(String modelPath) async {
    try {
      if (modelPath.startsWith('assets/')) {
        // Load from Flutter assets (must use buffer)
        final bytes = await _loadModelBytes(modelPath);
        _visionSession = OrtSession.fromBuffer(bytes, _sessionOptions!);
      } else {
        // Load from file system - use fromFile to avoid OOM on large models
        final file = File(modelPath);
        _visionSession = OrtSession.fromFile(file, _sessionOptions!);
      }
      _isVisionReady = true;
      debugPrint('OnnxSiglipInference: Vision encoder loaded');
      
      // Log output names to help debug output tensor selection
      if (_visionSession != null) {
        final outputNames = _visionSession!.outputNames;
        debugPrint('OnnxSiglipInference: Vision model output names: $outputNames');
      }
    } catch (e) {
      _isVisionReady = false;
      debugPrint('OnnxSiglipInference: Failed to load vision encoder: $e');
      rethrow;
    }
  }

  /// Load the text encoder model.
  Future<void> loadTextModel(String modelPath) async {
    try {
      if (modelPath.startsWith('assets/')) {
        // Load from Flutter assets (must use buffer)
        final bytes = await _loadModelBytes(modelPath);
        _textSession = OrtSession.fromBuffer(bytes, _sessionOptions!);
      } else {
        // Load from file system - use fromFile to avoid OOM on large models
        final file = File(modelPath);
        _textSession = OrtSession.fromFile(file, _sessionOptions!);
      }
      _isTextReady = true;
      debugPrint('OnnxSiglipInference: Text encoder loaded');
      
      // Log output names to help debug output tensor selection
      if (_textSession != null) {
        final outputNames = _textSession!.outputNames;
        debugPrint('OnnxSiglipInference: Text model output names: $outputNames');
      }
    } catch (e) {
      _isTextReady = false;
      debugPrint('OnnxSiglipInference: Failed to load text encoder: $e');
      rethrow;
    }
  }

  /// Load model bytes from asset or file path.
  Future<Uint8List> _loadModelBytes(String path) async {
    if (path.startsWith('assets/')) {
      // Load from Flutter assets
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } else {
      // Load from file system
      final file = File(path);
      return file.readAsBytes();
    }
  }

  /// Generate embedding for a preprocessed image.
  ///
  /// [imageData] should be a Float32List with shape [1, 3, 224, 224] in NCHW format,
  /// with values normalized to [-1, 1] or [0, 1] depending on model.
  Float32List embedImage(Float32List imageData) {
    if (!_isVisionReady || _visionSession == null) {
      throw StateError('Vision encoder not loaded');
    }

    final shape = [1, imageChannels, imageSize, imageSize];
    final inputTensor = OrtValueTensor.createTensorWithDataList(imageData, shape);

    final runOptions = OrtRunOptions();
    final inputs = {'pixel_values': inputTensor};

    try {
      final outputs = _visionSession!.run(runOptions, inputs);
      final outputNames = _visionSession!.outputNames;
      
      debugPrint('OnnxSiglipInference: Vision run complete, ${outputs.length} outputs');
      
      // Try to find the configured output tensor by name first
      OrtValue? embeddingOutput;
      int targetOutputIdx = -1;
      
      // Look for configured output tensor name
      final targetName = _config.visionOutputTensorName;
      for (int i = 0; i < outputNames.length; i++) {
        debugPrint('OnnxSiglipInference: Output[$i] name: ${outputNames[i]}');
        if (outputNames[i].contains(targetName) || outputNames[i] == targetName) {
          targetOutputIdx = i;
          break;
        }
      }
      
      if (targetOutputIdx >= 0 && targetOutputIdx < outputs.length) {
        embeddingOutput = outputs[targetOutputIdx];
        debugPrint('OnnxSiglipInference: Using $targetName at index $targetOutputIdx');
      } else {
        // Fall back to first non-null output (likely last_hidden_state)
        for (final output in outputs) {
          if (output != null) {
            embeddingOutput = output;
            break;
          }
        }
        debugPrint('OnnxSiglipInference: No $targetName found, using first output');
      }

      if (embeddingOutput == null) {
        throw StateError('Could not find embedding output');
      }

      // Get the value - handles multiple output formats:
      // - List<List<double>> for [1, 768] 2D shape (Xenova models with pooler_output)
      // - List<List<List<double>>> for [1, N, 768] 3D shape (raw last_hidden_state - needs pooling)
      // - List<double> for [768] 1D shape
      final outputValue = embeddingOutput.value;
      List<double> embeddingList;
      
      if (outputValue is List<List<List<double>>>) {
        // 3D output: [batch, patches/sequence, embedding_dim]
        // This is last_hidden_state - the model doesn't include the pooling head
        // WARNING: This means the model was exported without the MultiheadAttentionPoolingHead!
        // Mean pooling is a fallback but NOT equivalent to the proper SigLIP pooling.
        debugPrint('OnnxSiglipInference: WARNING - Vision model outputs 3D tensor (last_hidden_state)');
        debugPrint('OnnxSiglipInference: Shape: [${outputValue.length}, ${outputValue[0].length}, ${outputValue[0][0].length}]');
        debugPrint('OnnxSiglipInference: Using mean pooling fallback (not ideal for SigLIP!)');
        
        final numPatches = outputValue[0].length; // 196 patches for 224x224 image
        final embeddingDim = outputValue[0][0].length; // 768
        final meanEmbedding = List<double>.filled(embeddingDim, 0.0);
        
        // Mean pool over all patches (fallback - not the same as SigLIP's attention pooling)
        for (var patchIdx = 0; patchIdx < numPatches; patchIdx++) {
          for (var dim = 0; dim < embeddingDim; dim++) {
            meanEmbedding[dim] += outputValue[0][patchIdx][dim];
          }
        }
        
        for (var dim = 0; dim < embeddingDim; dim++) {
          meanEmbedding[dim] /= numPatches;
        }
        
        embeddingList = meanEmbedding;
      } else if (outputValue is List<List<double>>) {
        // 2D output: [batch, embedding_dim] = pooler_output (correct!)
        // This is what Xenova models output - properly pooled embeddings
        debugPrint('OnnxSiglipInference: Vision 2D pooler_output shape: [${outputValue.length}, ${outputValue[0].length}]');
        embeddingList = outputValue[0];
      } else if (outputValue is List<double>) {
        // 1D output: [embedding_dim]
        debugPrint('OnnxSiglipInference: Vision 1D output, length: ${outputValue.length}');
        embeddingList = outputValue;
      } else {
        throw StateError('Unexpected output format: ${outputValue.runtimeType}');
      }
      
      debugPrint('OnnxSiglipInference: Vision embedding length: ${embeddingList.length}');

      final embedding = Float32List.fromList(embeddingList.map((e) => e.toDouble()).toList());
      
      // L2 normalize the embedding - CRITICAL for SigLIP!
      final normalized = _l2Normalize(embedding);

      // Clean up
      inputTensor.release();
      runOptions.release();
      for (final output in outputs) {
        output?.release();
      }

      return normalized;
    } catch (e) {
      inputTensor.release();
      runOptions.release();
      rethrow;
    }
  }

  /// Generate embedding for tokenized text.
  ///
  /// [tokenIds] should be a list of 64 token IDs (padded).
  Float32List embedText(List<int> tokenIds) {
    if (!_isTextReady || _textSession == null) {
      throw StateError('Text encoder not loaded');
    }

    // Ensure we have exactly maxTextLength tokens
    final paddedTokens = List<int>.filled(maxTextLength, 0);
    for (var i = 0; i < tokenIds.length && i < maxTextLength; i++) {
      paddedTokens[i] = tokenIds[i];
    }
    
    // Find the last non-padding token position (for EOS token extraction)
    // SigLIP uses the EOS token (last actual token) for text representation
    int lastTokenPos = 0;
    for (var i = 0; i < maxTextLength; i++) {
      if (paddedTokens[i] != 0) {
        lastTokenPos = i;
      }
    }
    debugPrint('OnnxSiglipInference: Last non-padding token at position $lastTokenPos');

    final shape = [1, maxTextLength];
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(paddedTokens.map((e) => e.toInt()).toList()),
      shape,
    );

    final runOptions = OrtRunOptions();
    final inputs = {'input_ids': inputTensor};

    try {
      final outputs = _textSession!.run(runOptions, inputs);
      final outputNames = _textSession!.outputNames;
      
      debugPrint('OnnxSiglipInference: Text run complete, ${outputs.length} outputs');
      
      // Try to find the configured output tensor by name first
      OrtValue? embeddingOutput;
      int targetOutputIdx = -1;
      
      // Look for configured output tensor name
      final targetName = _config.textOutputTensorName;
      for (int i = 0; i < outputNames.length; i++) {
        debugPrint('OnnxSiglipInference: Text Output[$i] name: ${outputNames[i]}');
        if (outputNames[i].contains(targetName) || outputNames[i] == targetName) {
          targetOutputIdx = i;
          break;
        }
      }
      
      if (targetOutputIdx >= 0 && targetOutputIdx < outputs.length) {
        embeddingOutput = outputs[targetOutputIdx];
        debugPrint('OnnxSiglipInference: Using text $targetName at index $targetOutputIdx');
      } else {
        // Fall back to first non-null output (likely last_hidden_state)
        for (final output in outputs) {
          if (output != null) {
            embeddingOutput = output;
            break;
          }
        }
        debugPrint('OnnxSiglipInference: No text $targetName found, using first output');
      }

      if (embeddingOutput == null) {
        throw StateError('Could not find embedding output');
      }

      // Get the value - handle various output formats
      final outputValue = embeddingOutput.value;
      debugPrint('OnnxSiglipInference: Text output type: ${outputValue.runtimeType}');
      List<double> embeddingList;
      
      if (outputValue is List<List<List<double>>>) {
        // 3D tensor: [1, seq_len, embedding_dim] = last_hidden_state
        // WARNING: This means the model doesn't include the pooling head!
        // Mean pooling is a fallback but NOT equivalent to proper SigLIP text pooling.
        debugPrint('OnnxSiglipInference: WARNING - Text model outputs 3D tensor (last_hidden_state)');
        debugPrint('OnnxSiglipInference: Shape: [${outputValue.length}, ${outputValue[0].length}, ${outputValue[0][0].length}]');
        debugPrint('OnnxSiglipInference: Using mean pooling fallback (not ideal for SigLIP!)');
        
        // Mean pool over all non-padding tokens
        final embeddingDim = outputValue[0][0].length;
        final meanEmbedding = List<double>.filled(embeddingDim, 0.0);
        final numTokens = lastTokenPos + 1; // Include position 0 to lastTokenPos
        
        for (var tokenPos = 0; tokenPos <= lastTokenPos; tokenPos++) {
          for (var dim = 0; dim < embeddingDim; dim++) {
            meanEmbedding[dim] += outputValue[0][tokenPos][dim];
          }
        }
        
        for (var dim = 0; dim < embeddingDim; dim++) {
          meanEmbedding[dim] /= numTokens;
        }
        
        embeddingList = meanEmbedding;
      } else if (outputValue is List<List<double>>) {
        // 2D tensor: [1, embedding_dim] = pooler_output (correct!)
        // This is what Xenova models output - properly pooled embeddings
        debugPrint('OnnxSiglipInference: Text 2D pooler_output shape: [${outputValue.length}, ${outputValue[0].length}]');
        embeddingList = outputValue[0];
      } else if (outputValue is List<double>) {
        // 1D tensor: [embedding_dim]
        debugPrint('OnnxSiglipInference: Text 1D output, length: ${outputValue.length}');
        embeddingList = outputValue;
      } else {
        throw StateError('Unexpected output format: ${outputValue.runtimeType}');
      }

      debugPrint('OnnxSiglipInference: Text embedding length: ${embeddingList.length}');
      final embedding = Float32List.fromList(embeddingList.map((e) => e.toDouble()).toList());
      
      // L2 normalize the embedding - CRITICAL for SigLIP!
      final normalized = _l2Normalize(embedding);

      // Clean up
      inputTensor.release();
      runOptions.release();
      for (final output in outputs) {
        output?.release();
      }

      return normalized;
    } catch (e) {
      inputTensor.release();
      runOptions.release();
      rethrow;
    }
  }

  /// L2 normalize a vector to unit length.
  /// This is critical for cosine similarity to work correctly with SigLIP embeddings.
  Float32List _l2Normalize(Float32List vector) {
    double sumOfSquares = 0.0;
    for (final v in vector) {
      sumOfSquares += v * v;
    }
    final norm = math.sqrt(sumOfSquares);
    
    if (norm == 0) {
      debugPrint('OnnxSiglipInference: WARNING - zero norm vector!');
      return vector;
    }
    
    final normalized = Float32List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      normalized[i] = vector[i] / norm;
    }
    
    debugPrint('OnnxSiglipInference: Normalized embedding (norm was ${norm.toStringAsFixed(4)})');
    return normalized;
  }

  /// Dispose resources.
  void dispose() {
    _visionSession?.release();
    _textSession?.release();
    _sessionOptions?.release();
    OrtEnv.instance.release();

    _visionSession = null;
    _textSession = null;
    _sessionOptions = null;
    _isVisionReady = false;
    _isTextReady = false;
  }
}

/// Helper to download ONNX models at runtime.
class OnnxModelDownloader {
  /// Base URL for model downloads (configure this for your hosting).
  static const String baseUrl = 'https://your-cdn.com/models/';

  /// Download a model file if not already cached.
  static Future<String> ensureModel(String modelName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelPath = '${appDir.path}/onnx_models/$modelName';
    final modelFile = File(modelPath);

    if (await modelFile.exists()) {
      debugPrint('OnnxModelDownloader: Using cached model: $modelName');
      return modelPath;
    }

    // Create directory
    await modelFile.parent.create(recursive: true);

    debugPrint('OnnxModelDownloader: Downloading $modelName...');

    // TODO: Implement actual download logic
    // For now, this is a placeholder - you would use http package
    // to download from baseUrl + modelName

    throw UnimplementedError(
      'Model download not implemented. '
      'Copy models manually to: ${appDir.path}/onnx_models/',
    );
  }

  /// Get the expected cache path for a model.
  static Future<String> getModelCachePath(String modelName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/onnx_models/$modelName';
  }
}
