import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves ONNX model file paths for the KitaKo app.
///
/// Model key → filename mapping:
///   kitako_vision_fp32 → kitako_image_encoder_fp32.onnx
///   kitako_vision_int8 → kitako_image_encoder_int8.onnx
///   kitako_text_fp32   → kitako_text_encoder_fp32.onnx  (ADB-pushed, dev only)
///   kitako_text_int8   → kitako_text_encoder_int8.onnx
///   siglip2_vision     → siglip2_image_encoder.onnx
///   siglip2_text       → siglip2_text_encoder.onnx
///
/// Search order:
///   1. App documents directory (populated via [copyModelsFromTmp]).
///   2. /data/local/tmp/ (ADB-pushed, Android only).
///   3. <cwd>/models/ (desktop development).
class ModelDownloadService {
  static const Map<String, String> _keyToFilename = {
    'kitako_vision_fp32': 'kitako_image_encoder_fp32.onnx',
    'kitako_vision_int8': 'kitako_image_encoder_int8.onnx',
    'kitako_text_fp32': 'kitako_text_encoder_fp32.onnx',
    'kitako_text_int8': 'kitako_text_encoder_int8.onnx',
    'siglip2_vision': 'siglip2_image_encoder.onnx',
    'siglip2_text': 'siglip2_text_encoder.onnx',
  };

  static const String _tokenizerFilename = 'tokenizer.json';
  static const String _tokenizerAssetPath =
      'assets/models/tokenizer/tokenizer.json';

  Directory? _docDir;

  Future<Directory> _getDocDir() async {
    _docDir ??= await getApplicationDocumentsDirectory();
    return _docDir!;
  }

  /// Returns `true` if the model file for [key] exists.
  Future<bool> isModelAvailable(String key) async {
    return (await _resolvePath(key)) != null;
  }

  /// Returns the resolved file-system path for [key].
  ///
  /// Throws [StateError] if not found.
  Future<String> getModelPath(String key) async {
    final path = await _resolvePath(key);
    if (path == null) {
      throw StateError(
        'Model "$key" not found. '
        'Push via ADB or place in models/.',
      );
    }
    return path;
  }

  /// Returns a file-system path to the tokenizer.json.
  ///
  /// Search order:
  ///   1. App documents directory.
  ///   2. /data/local/tmp/ (ADB-pushed, Android only).
  ///   3. Falls back to the bundled asset path so GemmaTokenizer can load it
  ///      via rootBundle (requires the file to be in pubspec assets).
  Future<String> getTokenizerPath() async {
    // 1. App documents directory.
    final docDir = await _getDocDir();
    final docFile = File('${docDir.path}/$_tokenizerFilename');
    if (await docFile.exists()) return docFile.path;

    // 2. ADB tmp (Android only).
    if (Platform.isAndroid) {
      final tmp = File('/data/local/tmp/$_tokenizerFilename');
      if (await tmp.exists()) return tmp.path;
    }

    // 3. Asset fallback.
    return _tokenizerAssetPath;
  }

  /// Copies model files from `/data/local/tmp/` into the app documents
  /// directory (Android only).
  Future<void> copyModelsFromTmp() async {
    if (!Platform.isAndroid) return;
    final docDir = await _getDocDir();
    const tmp = '/data/local/tmp';
    // Copy ONNX models.
    for (final filename in _keyToFilename.values) {
      final src = File('$tmp/$filename');
      if (!await src.exists()) continue;
      final dest = File('${docDir.path}/$filename');
      if (!await dest.exists()) {
        await src.copy(dest.path);
        debugPrint('ModelDownloadService: copied $filename from $tmp');
      }
    }
    // Copy tokenizer.
    final tokSrc = File('$tmp/$_tokenizerFilename');
    if (await tokSrc.exists()) {
      final tokDest = File('${docDir.path}/$_tokenizerFilename');
      if (!await tokDest.exists()) {
        await tokSrc.copy(tokDest.path);
        debugPrint('ModelDownloadService: copied $_tokenizerFilename from $tmp');
      }
    }
  }

  /// Native bridge to copy model files out of the install-time asset pack.
  /// Implemented in MainActivity (`com.kitako.app`); Android only.
  static const MethodChannel _modelsChannel =
      MethodChannel('kitako_app/models');

  /// Extracts the ONNX models from the install-time asset pack into the app
  /// documents directory.
  ///
  /// The models ship in the `:models_pack` Play Asset Delivery pack (delivery
  /// type install-time), not as Flutter assets — bundling ~660 MB in the base
  /// module would exceed Play's ~200 MB cap. install-time packs are fused into
  /// the Android AssetManager, so the native side streams each file out via
  /// `assets.open(...)` directly to a destination path (the big files never
  /// cross the method channel).
  ///
  /// Call this once at startup before loading any models. It is safe to call
  /// on every launch — files that already exist in the documents directory are
  /// skipped, so extraction only happens on the first install.
  ///
  /// [onProgress] is called after each file is handled with the file name and
  /// the index (1-based) out of the total count, so callers can show progress.
  Future<void> extractBundledModels({
    void Function(String filename, int done, int total)? onProgress,
  }) async {
    // Asset packs are an Android delivery mechanism. On other platforms the
    // models are resolved directly from the workspace `models/` dir instead
    // (see [_resolvePath]), so there is nothing to extract.
    if (!Platform.isAndroid) return;

    final docDir = await _getDocDir();

    // asset-pack asset path → destination filename
    const packAssets = <String, String>{
      'models/kitako_image_encoder_fp32.onnx': 'kitako_image_encoder_fp32.onnx',
      'models/kitako_text_encoder_int8.onnx': 'kitako_text_encoder_int8.onnx',
    };

    int done = 0;
    final total = packAssets.length;

    for (final entry in packAssets.entries) {
      final dest = File('${docDir.path}/${entry.value}');
      if (await dest.exists()) {
        done++;
        onProgress?.call(entry.value, done, total);
        debugPrint(
            'ModelDownloadService: ${entry.value} already extracted, skipping');
        continue;
      }

      debugPrint('ModelDownloadService: extracting ${entry.value} from asset pack…');
      try {
        await _modelsChannel.invokeMethod<bool>('copyAsset', {
          'assetPath': entry.key,
          'destPath': dest.path,
        });
        done++;
        onProgress?.call(entry.value, done, total);
        final size = await dest.length();
        debugPrint(
            'ModelDownloadService: extracted ${entry.value} '
            '(${(size / 1024 / 1024).toStringAsFixed(0)} MB)');
      } catch (e) {
        debugPrint(
            'ModelDownloadService: failed to extract ${entry.value}: $e');
        rethrow;
      }
    }
  }

  /// Prints model availability and setup hints to the debug console.
  Future<void> printModelSetupInstructions() async {
    debugPrint('═══ KitaKo Model Setup ═══');
    for (final entry in _keyToFilename.entries) {
      final ok = await isModelAvailable(entry.key);
      debugPrint('  ${ok ? "✓" : "✗"} ${entry.key} → ${entry.value}');
    }
    if (Platform.isAndroid) {
      debugPrint('Push models via ADB:');
      for (final fn in _keyToFilename.values) {
        debugPrint('  adb push models/$fn /data/local/tmp/');
      }
    } else {
      debugPrint(
        'Place models in: ${Directory.current.path}/models/',
      );
    }
    debugPrint('══════════════════════════');
  }

  Future<String?> _resolvePath(String key) async {
    final filename = _keyToFilename[key];
    if (filename == null) return null;

    // 1. App documents directory.
    final docDir = await _getDocDir();
    final docFile = File('${docDir.path}/$filename');
    if (await docFile.exists()) return docFile.path;

    // 2. ADB tmp (Android only).
    if (Platform.isAndroid) {
      final tmp = File('/data/local/tmp/$filename');
      if (await tmp.exists()) return tmp.path;
    }

    // 3. Workspace-relative desktop path.
    final desktop = File('${Directory.current.path}/models/$filename');
    if (await desktop.exists()) return desktop.path;

    return null;
  }
}
