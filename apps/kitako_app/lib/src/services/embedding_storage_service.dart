import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Everything needed to restore the app's embedding + search state from disk.
class StoredEmbeddingSnapshot {
  /// Image ID → 768-dim embedding vector
  final Map<String, Float32List> embeddings;

  /// Image ID → file path (for matching against current device images)
  final Map<String, String> imagePaths;

  /// The vision encoder ID that produced these embeddings
  final String visionEncoderId;

  const StoredEmbeddingSnapshot({
    required this.embeddings,
    required this.imagePaths,
    required this.visionEncoderId,
  });
}

/// Persistence layer for image embeddings.
///
/// Storage is keyed by **vision encoder ID** (e.g. `kitako_vision_fp32`), not
/// by full model variant. Variants that share the same vision tower (such as
/// `kitakoFp32` and `kitakoMixed`) can therefore reuse the same image
/// embeddings, so switching between them costs only a text-encoder reload.
///
/// Layout under `getApplicationDocumentsDirectory()/embeddings_cache/`:
///
/// ```
/// embeddings_cache/
///   <visionEncoderId>/
///     embeddings.bin
///     metadata.json
///     ivfpq_index.bin
/// ```
class EmbeddingStorageService {
  static const String _cacheDirName = 'embeddings_cache';
  static const String _embeddingsFile = 'embeddings.bin';
  static const String _metadataFile = 'metadata.json';
  static const String _ivfpqFile = 'ivfpq_index.bin';

  /// Binary format constants
  static const int _magic = 0x4B454D42; // "KEMB"
  static const int _version = 2;

  /// Get the root cache directory, creating it if necessary.
  Future<Directory> _rootDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Get the per-vision-encoder cache directory.
  Future<Directory> _encoderDir(String visionEncoderId) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/$visionEncoderId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Path to the IVF-PQ index file for a given vision encoder.
  Future<String> ivfpqIndexPath(String visionEncoderId) async {
    final dir = await _encoderDir(visionEncoderId);
    return '${dir.path}/$_ivfpqFile';
  }

  // ========== Save ==========

  /// Persist all embedding data to disk in a single operation.
  Future<void> saveAll({
    required Map<String, Float32List> embeddings,
    required Map<String, String> imagePaths,
    required String visionEncoderId,
  }) async {
    if (embeddings.isEmpty) return;

    final dir = await _encoderDir(visionEncoderId);
    final stopwatch = Stopwatch()..start();

    await Future.wait([
      _saveEmbeddingsBinary(
        '${dir.path}/$_embeddingsFile',
        embeddings,
        visionEncoderId,
      ),
      _saveMetadataJson(
        '${dir.path}/$_metadataFile',
        imagePaths,
        visionEncoderId,
        embeddings.length,
      ),
    ]);

    stopwatch.stop();
    final sizeKb = await _fileSizeKb('${dir.path}/$_embeddingsFile');
    debugPrint('EmbeddingStorageService: Saved ${embeddings.length} embeddings '
        'for "$visionEncoderId" (${sizeKb.toStringAsFixed(0)} KB) in '
        '${stopwatch.elapsedMilliseconds}ms');
  }

  // ========== Load ==========

  /// Load all persisted embedding data for a vision encoder, if any.
  ///
  /// Returns `null` if the cache is missing or corrupt.
  Future<StoredEmbeddingSnapshot?> loadAll(String visionEncoderId) async {
    final dir = await _encoderDir(visionEncoderId);
    final embPath = '${dir.path}/$_embeddingsFile';
    final metaPath = '${dir.path}/$_metadataFile';

    if (!await File(embPath).exists() || !await File(metaPath).exists()) {
      debugPrint('EmbeddingStorageService: No cache for "$visionEncoderId"');
      return null;
    }

    try {
      final stopwatch = Stopwatch()..start();

      final metaJson =
          jsonDecode(await File(metaPath).readAsString()) as Map<String, dynamic>;
      final cachedEncoder = metaJson['visionEncoderId'] as String? ??
          metaJson['modelVariant'] as String?;

      if (cachedEncoder != visionEncoderId) {
        debugPrint('EmbeddingStorageService: Metadata encoder mismatch '
            '(cached: $cachedEncoder, expected: $visionEncoderId) — ignoring');
        return null;
      }

      final imagePaths = (metaJson['imagePaths'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));

      final embeddings = await _loadEmbeddingsBinary(embPath, visionEncoderId);
      if (embeddings == null) return null;

      stopwatch.stop();
      debugPrint('EmbeddingStorageService: Loaded ${embeddings.length} cached '
          'embeddings for "$visionEncoderId" in '
          '${stopwatch.elapsedMilliseconds}ms');

      return StoredEmbeddingSnapshot(
        embeddings: embeddings,
        imagePaths: imagePaths,
        visionEncoderId: visionEncoderId,
      );
    } catch (e) {
      debugPrint('EmbeddingStorageService: Failed to load cache for '
          '"$visionEncoderId": $e');
      return null;
    }
  }

  // ========== Clear ==========

  /// Delete persisted data.
  ///
  /// If [visionEncoderId] is provided, only that encoder's cache is removed.
  /// Otherwise the entire cache root is wiped.
  Future<void> clear({String? visionEncoderId}) async {
    if (visionEncoderId != null) {
      final dir = await _encoderDir(visionEncoderId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint(
            'EmbeddingStorageService: Cleared cache for "$visionEncoderId"');
      }
      return;
    }

    final root = await _rootDir();
    if (await root.exists()) {
      await root.delete(recursive: true);
      debugPrint('EmbeddingStorageService: All stored data cleared');
    }
  }

  // ========== Binary Embedding Format ==========

  /// Write embeddings as a compact binary blob.
  ///
  /// Format:
  /// ```
  /// [magic:4][version:4][dimension:4][count:4]
  /// [encoderIdLen:2][encoderIdBytes...]
  /// For each entry:
  ///   [idLen:2][idBytes...][embedding: dim×4 bytes]
  /// ```
  Future<void> _saveEmbeddingsBinary(
    String path,
    Map<String, Float32List> embeddings,
    String visionEncoderId,
  ) async {
    if (embeddings.isEmpty) return;

    final dimension = embeddings.values.first.length;
    final encoderBytes = utf8.encode(visionEncoderId);

    var totalSize = 16; // header
    totalSize += 2 + encoderBytes.length;
    for (final entry in embeddings.entries) {
      final idBytes = utf8.encode(entry.key);
      totalSize += 2 + idBytes.length + dimension * 4;
    }

    final buffer = Uint8List(totalSize);
    final data = ByteData.sublistView(buffer);

    data.setUint32(0, _magic, Endian.little);
    data.setUint32(4, _version, Endian.little);
    data.setUint32(8, dimension, Endian.little);
    data.setUint32(12, embeddings.length, Endian.little);

    var offset = 16;

    data.setUint16(offset, encoderBytes.length, Endian.little);
    offset += 2;
    buffer.setRange(offset, offset + encoderBytes.length, encoderBytes);
    offset += encoderBytes.length;

    for (final entry in embeddings.entries) {
      final idBytes = utf8.encode(entry.key);

      data.setUint16(offset, idBytes.length, Endian.little);
      offset += 2;
      buffer.setRange(offset, offset + idBytes.length, idBytes);
      offset += idBytes.length;

      final embBytes = entry.value.buffer.asUint8List(
        entry.value.offsetInBytes,
        entry.value.lengthInBytes,
      );
      buffer.setRange(offset, offset + embBytes.length, embBytes);
      offset += embBytes.length;
    }

    await File(path).writeAsBytes(buffer);
  }

  Future<Map<String, Float32List>?> _loadEmbeddingsBinary(
    String path,
    String expectedEncoder,
  ) async {
    final bytes = await File(path).readAsBytes();
    final data = ByteData.sublistView(bytes);

    if (bytes.length < 16) return null;

    final magic = data.getUint32(0, Endian.little);
    if (magic != _magic) {
      debugPrint('EmbeddingStorageService: Invalid magic number');
      return null;
    }

    final version = data.getUint32(4, Endian.little);
    // Accept v1 blobs (old variant-keyed cache) as long as the encoder string
    // matches, so existing caches keep working after the rename.
    if (version != _version && version != 1) {
      debugPrint('EmbeddingStorageService: Unsupported version $version');
      return null;
    }

    final dimension = data.getUint32(8, Endian.little);
    final count = data.getUint32(12, Endian.little);

    var offset = 16;

    final encoderLen = data.getUint16(offset, Endian.little);
    offset += 2;
    final encoder = utf8.decode(bytes.sublist(offset, offset + encoderLen));
    offset += encoderLen;

    if (encoder != expectedEncoder) {
      debugPrint('EmbeddingStorageService: Binary encoder mismatch '
          '(have "$encoder", want "$expectedEncoder")');
      return null;
    }

    final embeddings = <String, Float32List>{};
    for (var i = 0; i < count; i++) {
      final idLen = data.getUint16(offset, Endian.little);
      offset += 2;
      final id = utf8.decode(bytes.sublist(offset, offset + idLen));
      offset += idLen;

      final embBytes = bytes.sublist(offset, offset + dimension * 4);
      final embedding = Float32List.view(Uint8List.fromList(embBytes).buffer);
      embeddings[id] = embedding;
      offset += dimension * 4;
    }

    return embeddings;
  }

  // ========== JSON helpers ==========

  Future<void> _saveMetadataJson(
    String path,
    Map<String, String> imagePaths,
    String visionEncoderId,
    int embeddingCount,
  ) async {
    final meta = {
      'visionEncoderId': visionEncoderId,
      'embeddingCount': embeddingCount,
      'savedAt': DateTime.now().toIso8601String(),
      'imagePaths': imagePaths,
    };
    await File(path).writeAsString(jsonEncode(meta));
  }

  // ========== Utilities ==========

  Future<double> _fileSizeKb(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return (await file.length()) / 1024;
    }
    return 0;
  }
}
