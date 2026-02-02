import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service for downloading and managing ML models at runtime.
///
/// This service handles downloading large ONNX models that can't be bundled
/// with the APK due to size constraints.
class ModelDownloadService {
  /// Singleton instance
  static final ModelDownloadService _instance = ModelDownloadService._internal();
  factory ModelDownloadService() => _instance;
  ModelDownloadService._internal();

  /// Base URL for model hosting.
  /// 
  /// Using Xenova/siglip-base-patch16-224 models from HuggingFace.
  /// These models properly include the MultiheadAttentionPoolingHead and output
  /// pooler_output directly (2D tensor [1, 768]), not last_hidden_state.
  static const String defaultBaseUrl = 
      'https://huggingface.co/Xenova/siglip-base-patch16-224/resolve/main/onnx/';

  String _baseUrl = defaultBaseUrl;

  /// Model file definitions
  /// 
  /// SigLIP-1 (Quantized): Xenova/siglip-base-patch16-224 - includes pooling head
  /// - Smaller, faster downloads (~210MB total)
  /// - Quantized models for mobile efficiency
  /// - May have slight accuracy loss due to quantization
  /// 
  /// SigLIP-2 (FP32): google/siglip-base-patch16-256 - includes projection layers
  /// - Larger, better quality (~1.5GB total)
  /// - Full precision models
  /// - Proper vision/text alignment with projection layers
  /// - Recommended for best search accuracy
  /// 
  /// NOTE: Using older *_quantized.onnx models (not *_int8.onnx) for SigLIP-1 because:
  /// - int8 models use ConvInteger(10) which isn't supported by ONNX Runtime Mobile
  /// - The older quantized models use compatible dynamic quantization
  static const int modelVersion = 5; // Added SigLIP-1 aligned models

  static const Map<String, ModelInfo> models = {
    // SigLIP-1 ALIGNED (RECOMMENDED - correctly aligned embeddings)
    // These models output pooler_output which is in the shared embedding space
    'siglip1_vision_aligned': ModelInfo(
      filename: 'siglip_vision_aligned_full.onnx',
      expectedSizeBytes: 371640302, // ~354 MB
      description: 'SigLIP-1 Vision Encoder (FP32, 224x224, ALIGNED)',
      modelType: ModelType.siglip1Aligned,
      requiresManualSetup: true,
    ),
    'siglip1_text_aligned': ModelInfo(
      filename: 'siglip_text_aligned_full.onnx',
      expectedSizeBytes: 441187029, // ~421 MB
      description: 'SigLIP-1 Text Encoder (FP32, 32K vocab, ALIGNED)',
      modelType: ModelType.siglip1Aligned,
      requiresManualSetup: true,
    ),

    // SigLIP-1 Quantized (from Xenova HuggingFace - NOT recommended, misaligned)
    'vision_encoder': ModelInfo(
      filename: 'vision_model_quantized.onnx',
      expectedSizeBytes: 99499129, // ~99.5 MB
      description: 'SigLIP-1 Vision Encoder (quantized, 224x224) - LEGACY',
      modelType: ModelType.siglip1Quantized,
    ),
    'text_encoder': ModelInfo(
      filename: 'text_model_quantized.onnx',
      expectedSizeBytes: 111475220, // ~111 MB
      description: 'SigLIP-1 Text Encoder (quantized, 32K vocab) - LEGACY',
      modelType: ModelType.siglip1Quantized,
    ),

    // SigLIP-2 FP32 (higher quality, manually hosted or local)
    'siglip2_vision': ModelInfo(
      filename: 'siglip2_vision_model_fp32.onnx',
      expectedSizeBytes: 371807752, // ~371 MB
      description: 'SigLIP-2 Vision Encoder (FP32, 256x256, with projection)',
      modelType: ModelType.siglip2Fp32,
      requiresManualSetup: true, // Too large for auto-download from HF
    ),
    'siglip2_text': ModelInfo(
      filename: 'siglip2_text_model_fp32.onnx',
      expectedSizeBytes: 1129469657, // ~1.1 GB
      description: 'SigLIP-2 Text Encoder (FP32, 256K vocab, with projection)',
      modelType: ModelType.siglip2Fp32,
      requiresManualSetup: true, // Too large for auto-download from HF
    ),
  };

  /// Download progress callbacks
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};

  /// Set custom base URL for model downloads
  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url : '$url/';
  }

  /// Get the local cache directory for models
  Future<Directory> get _modelCacheDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/onnx_models');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Get the local path for a model
  Future<String> getModelPath(String modelKey) async {
    final info = models[modelKey];
    if (info == null) {
      throw ArgumentError('Unknown model: $modelKey');
    }
    final cacheDir = await _modelCacheDir;
    return '${cacheDir.path}/${info.filename}';
  }

  /// Check if a model is already downloaded and valid
  Future<bool> isModelAvailable(String modelKey) async {
    final path = await getModelPath(modelKey);
    final file = File(path);
    
    if (!await file.exists()) {
      return false;
    }
    
    // Verify file size (basic integrity check)
    final info = models[modelKey]!;
    final actualSize = await file.length();
    
    // Allow some tolerance (±5%)
    final minSize = (info.expectedSizeBytes * 0.95).toInt();
    final maxSize = (info.expectedSizeBytes * 1.05).toInt();
    
    return actualSize >= minSize && actualSize <= maxSize;
  }

  /// Copy models from /data/local/tmp/ if they exist (for manual deployment)
  Future<void> copyModelsFromTmp() async {
    for (final entry in models.entries) {
      final modelKey = entry.key;
      final info = entry.value;

      // Skip if already have valid model
      if (await isModelAvailable(modelKey)) {
        debugPrint('ModelDownloadService: $modelKey already available');
        continue;
      }

      // Check if model exists in /data/local/tmp/
      final tmpFile = File('/data/local/tmp/${info.filename}');
      if (!await tmpFile.exists()) {
        continue;
      }

      // Verify size
      final tmpSize = await tmpFile.length();
      final minSize = (info.expectedSizeBytes * 0.95).toInt();
      final maxSize = (info.expectedSizeBytes * 1.05).toInt();

      if (tmpSize < minSize || tmpSize > maxSize) {
        debugPrint('ModelDownloadService: $modelKey in tmp has wrong size: $tmpSize (expected ~${info.expectedSizeBytes})');
        continue;
      }

      // Copy to app directory
      try {
        final destPath = await getModelPath(modelKey);
        final destFile = File(destPath);

        debugPrint('ModelDownloadService: Copying $modelKey from tmp to $destPath');
        await tmpFile.copy(destPath);

        // Verify copied file
        if (await isModelAvailable(modelKey)) {
          debugPrint('ModelDownloadService: $modelKey copied successfully from tmp');
        } else {
          debugPrint('ModelDownloadService: $modelKey copy failed verification');
          await destFile.delete();
        }
      } catch (e) {
        debugPrint('ModelDownloadService: Failed to copy $modelKey from tmp: $e');
      }
    }
  }

  /// Get download progress notifier for a model
  ValueNotifier<double> getProgressNotifier(String modelKey) {
    return _progressNotifiers.putIfAbsent(
      modelKey,
      () => ValueNotifier(0.0),
    );
  }

  /// Download a model with progress tracking
  Future<String> downloadModel(
    String modelKey, {
    void Function(double progress)? onProgress,
  }) async {
    final info = models[modelKey];
    if (info == null) {
      throw ArgumentError('Unknown model: $modelKey');
    }

    final path = await getModelPath(modelKey);
    final file = File(path);

    // Check if already downloaded
    if (await isModelAvailable(modelKey)) {
      debugPrint('ModelDownloadService: $modelKey already cached at $path');
      return path;
    }

    final url = '$_baseUrl${info.filename}';
    debugPrint('ModelDownloadService: Downloading $modelKey from $url');

    final progressNotifier = getProgressNotifier(modelKey);
    progressNotifier.value = 0.0;

    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      final contentLength = response.contentLength ?? info.expectedSizeBytes;
      var downloadedBytes = 0;

      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        final progress = downloadedBytes / contentLength;
        progressNotifier.value = progress.clamp(0.0, 1.0);
        onProgress?.call(progress);
      }

      await sink.close();

      // Verify download
      final actualSize = await file.length();
      if (actualSize < info.expectedSizeBytes * 0.9) {
        await file.delete();
        throw Exception('Downloaded file is incomplete');
      }

      progressNotifier.value = 1.0;
      debugPrint('ModelDownloadService: $modelKey downloaded successfully');
      
      return path;
    } catch (e) {
      // Clean up partial download
      if (await file.exists()) {
        await file.delete();
      }
      progressNotifier.value = 0.0;
      rethrow;
    }
  }

  /// Download all required models
  Future<Map<String, String>> downloadAllModels({
    void Function(String modelKey, double progress)? onProgress,
  }) async {
    final paths = <String, String>{};
    
    for (final key in models.keys) {
      final path = await downloadModel(
        key,
        onProgress: (progress) => onProgress?.call(key, progress),
      );
      paths[key] = path;
    }
    
    return paths;
  }

  /// Get total download size in bytes
  int get totalDownloadSize {
    return models.values.fold(0, (sum, info) => sum + info.expectedSizeBytes);
  }

  /// Get human-readable total download size
  String get totalDownloadSizeFormatted {
    final bytes = totalDownloadSize;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Delete all cached models
  Future<void> clearCache() async {
    final cacheDir = await _modelCacheDir;
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
    debugPrint('ModelDownloadService: Cache cleared');
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    final cacheDir = await _modelCacheDir;
    if (!await cacheDir.exists()) return 0;
    
    var totalSize = 0;
    await for (final entity in cacheDir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// Get the model cache directory path (for manual file placement / ADB push)
  Future<String> getModelCacheDirectoryPath() async {
    final cacheDir = await _modelCacheDir;
    return cacheDir.path;
  }

  /// Print instructions for manually placing models (for development)
  Future<void> printModelSetupInstructions() async {
    final cacheDir = await _modelCacheDir;
    debugPrint('=== ONNX Model Setup Instructions ===');
    debugPrint('Model cache directory: ${cacheDir.path}');
    debugPrint('');
    debugPrint('--- SigLIP-1 (Quantized, ~210MB) ---');
    debugPrint('Auto-downloadable from HuggingFace. Use the app UI to download.');
    debugPrint('');
    debugPrint('--- SigLIP-2 (FP32, ~1.5GB) - RECOMMENDED ---');
    debugPrint('For better accuracy, manually place SigLIP-2 models:');
    debugPrint('');
    debugPrint('Method 1: ADB Push (from your PC):');
    debugPrint('  cd <path_to_workspace>/assets/models/');
    debugPrint('  adb push siglip2_vision_model_fp32.onnx /data/local/tmp/');
    debugPrint('  adb push siglip2_text_model_fp32.onnx /data/local/tmp/');
    debugPrint('  Then restart the app - it will copy from /data/local/tmp/');
    debugPrint('');
    debugPrint('Method 2: Direct Copy:');
    for (final entry in models.entries) {
      if (entry.value.modelType == ModelType.siglip2Fp32) {
        final info = entry.value;
        debugPrint('  adb push ${info.filename} ${cacheDir.path}/${info.filename}');
      }
    }
    debugPrint('');
    debugPrint('Model files location in workspace:');
    debugPrint('  <workspace>/assets/models/siglip2_vision_model_fp32.onnx');
    debugPrint('  <workspace>/assets/models/siglip2_text_model_fp32.onnx');
    debugPrint('=====================================');
  }

  /// Check if SigLIP-2 models are available
  Future<bool> isSiglip2Available() async {
    final vision = await isModelAvailable('siglip2_vision');
    final text = await isModelAvailable('siglip2_text');
    return vision && text;
  }

  /// Check if SigLIP-1 models are available
  Future<bool> isSiglip1Available() async {
    final vision = await isModelAvailable('vision_encoder');
    final text = await isModelAvailable('text_encoder');
    return vision && text;
  }
}

/// Model type for categorization
enum ModelType {
  siglip1Quantized,  // Quantized SigLIP-1 (~210MB total) - LEGACY, misaligned
  siglip1Aligned,    // Full precision SigLIP-1 with aligned embeddings (~775MB total) - RECOMMENDED
  siglip2Fp32,       // Full precision SigLIP-2 (~1.5GB total)
}

/// Information about a downloadable model
class ModelInfo {
  final String filename;
  final int expectedSizeBytes;
  final String description;
  final ModelType modelType;
  final bool requiresManualSetup;

  const ModelInfo({
    required this.filename,
    required this.expectedSizeBytes,
    required this.description,
    required this.modelType,
    this.requiresManualSetup = false,
  });

  String get sizeFormatted {
    final bytes = expectedSizeBytes;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
