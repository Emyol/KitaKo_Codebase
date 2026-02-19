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

  /// The model variant that produced these embeddings
  final String modelVariant;

  const StoredEmbeddingSnapshot({
    required this.embeddings,
    required this.imagePaths,
    required this.modelVariant,
  });
}

/// Persistence layer for image embeddings.
///
/// This is the **single source of truth** for all on-disk storage related to
/// the embedding / search pipeline.  No other service should perform file I/O
/// for these concerns — they export data to this layer and import it back.
///
/// ## Storage layout
///
/// All files live under `getApplicationDocumentsDirectory()/embeddings_cache/`:
///
/// | File               | Contents                                        |
/// |--------------------|-------------------------------------------------|
/// | `embeddings.bin`   | Binary blob of Float32List vectors (KEMB format) |
/// | `metadata.json`    | Image id→path map, model variant, timestamp      |
///
/// ## Why this is a storage layer
///
/// 1. **Single responsibility** — all file I/O for embeddings lives here.
/// 2. **Information hiding** — callers don't know about binary formats, paths,
///    or directory structure.
/// 3. **Clean interface** — [saveAll] / [loadAll] / [clear] are the only
///    entry points.
/// 4. **Swappable** — could be replaced with SQLite, cloud storage, etc.
///    without touching search or ANN logic.
class EmbeddingStorageService {
  static const String _cacheDirName = 'embeddings_cache';
  static const String _embeddingsFile = 'embeddings.bin';
  static const String _metadataFile = 'metadata.json';

  /// Binary format constants
  static const int _magic = 0x4B454D42; // "KEMB"
  static const int _version = 1;

  /// Get the cache directory, creating it if necessary.
  Future<Directory> get _cacheDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ========== Save ==========

  /// Persist all embedding data to disk in a single operation.
  ///
  /// [embeddings] — image ID → Float32List (768-dim)
  /// [imagePaths] — image ID → file path on device
  /// [modelVariant] — name of the model variant (for cache invalidation)
  Future<void> saveAll({
    required Map<String, Float32List> embeddings,
    required Map<String, String> imagePaths,
    required String modelVariant,
  }) async {
    if (embeddings.isEmpty) return;

    final dir = await _cacheDir;
    final stopwatch = Stopwatch()..start();

    await Future.wait([
      _saveEmbeddingsBinary(
        '${dir.path}/$_embeddingsFile',
        embeddings,
        modelVariant,
      ),
      _saveMetadataJson(
        '${dir.path}/$_metadataFile',
        imagePaths,
        modelVariant,
        embeddings.length,
      ),
    ]);

    stopwatch.stop();
    final sizeKb = await _fileSizeKb('${dir.path}/$_embeddingsFile');
    debugPrint('EmbeddingStorageService: Saved ${embeddings.length} embeddings '
        '(${sizeKb.toStringAsFixed(0)} KB) in ${stopwatch.elapsedMilliseconds}ms');
  }

  // ========== Load ==========

  /// Load all persisted embedding data if it exists and matches the model.
  ///
  /// Returns `null` if the cache is missing, corrupt, or was created with a
  /// different model variant.
  Future<StoredEmbeddingSnapshot?> loadAll(String modelVariant) async {
    final dir = await _cacheDir;
    final embPath = '${dir.path}/$_embeddingsFile';
    final metaPath = '${dir.path}/$_metadataFile';

    if (!await File(embPath).exists() || !await File(metaPath).exists()) {
      debugPrint('EmbeddingStorageService: No cache found');
      return null;
    }

    try {
      final stopwatch = Stopwatch()..start();

      // Read metadata first (cheap) to check model variant
      final metaJson =
          jsonDecode(await File(metaPath).readAsString()) as Map<String, dynamic>;
      final cachedVariant = metaJson['modelVariant'] as String?;

      if (cachedVariant != modelVariant) {
        debugPrint('EmbeddingStorageService: Cache model mismatch '
            '(cached: $cachedVariant, current: $modelVariant) — ignoring cache');
        return null;
      }

      final imagePaths = (metaJson['imagePaths'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));

      // Read binary embeddings
      final embeddings = await _loadEmbeddingsBinary(embPath, modelVariant);
      if (embeddings == null) return null;

      stopwatch.stop();
      debugPrint('EmbeddingStorageService: Loaded ${embeddings.length} cached embeddings '
          'in ${stopwatch.elapsedMilliseconds}ms');

      return StoredEmbeddingSnapshot(
        embeddings: embeddings,
        imagePaths: imagePaths,
        modelVariant: modelVariant,
      );
    } catch (e) {
      debugPrint('EmbeddingStorageService: Failed to load cache: $e');
      return null;
    }
  }

  // ========== Clear ==========

  /// Delete all persisted data.
  Future<void> clear() async {
    final dir = await _cacheDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      debugPrint('EmbeddingStorageService: All stored data cleared');
    }
  }

  // ========== Binary Embedding Format ==========

  /// Write embeddings as a compact binary blob.
  ///
  /// Format:
  /// ```
  /// [magic:4][version:4][dimension:4][count:4]
  /// [variantLen:2][variantBytes...]
  /// For each entry:
  ///   [idLen:2][idBytes...][embedding: dim×4 bytes]
  /// ```
  Future<void> _saveEmbeddingsBinary(
    String path,
    Map<String, Float32List> embeddings,
    String modelVariant,
  ) async {
    if (embeddings.isEmpty) return;

    final dimension = embeddings.values.first.length;
    final variantBytes = utf8.encode(modelVariant);

    // Calculate total size
    var totalSize = 16; // header
    totalSize += 2 + variantBytes.length; // variant string
    for (final entry in embeddings.entries) {
      final idBytes = utf8.encode(entry.key);
      totalSize += 2 + idBytes.length + dimension * 4;
    }

    final buffer = Uint8List(totalSize);
    final data = ByteData.sublistView(buffer);

    // Header
    data.setUint32(0, _magic, Endian.little);
    data.setUint32(4, _version, Endian.little);
    data.setUint32(8, dimension, Endian.little);
    data.setUint32(12, embeddings.length, Endian.little);

    var offset = 16;

    // Model variant string
    data.setUint16(offset, variantBytes.length, Endian.little);
    offset += 2;
    buffer.setRange(offset, offset + variantBytes.length, variantBytes);
    offset += variantBytes.length;

    // Entries
    for (final entry in embeddings.entries) {
      final idBytes = utf8.encode(entry.key);

      // ID
      data.setUint16(offset, idBytes.length, Endian.little);
      offset += 2;
      buffer.setRange(offset, offset + idBytes.length, idBytes);
      offset += idBytes.length;

      // Embedding (copy float32 bytes directly)
      final embBytes = entry.value.buffer.asUint8List(
        entry.value.offsetInBytes,
        entry.value.lengthInBytes,
      );
      buffer.setRange(offset, offset + embBytes.length, embBytes);
      offset += embBytes.length;
    }

    await File(path).writeAsBytes(buffer);
  }

  /// Read embeddings from binary blob.
  Future<Map<String, Float32List>?> _loadEmbeddingsBinary(
    String path,
    String expectedVariant,
  ) async {
    final bytes = await File(path).readAsBytes();
    final data = ByteData.sublistView(bytes);

    // Validate header
    if (bytes.length < 16) return null;

    final magic = data.getUint32(0, Endian.little);
    if (magic != _magic) {
      debugPrint('EmbeddingStorageService: Invalid magic number');
      return null;
    }

    final version = data.getUint32(4, Endian.little);
    if (version != _version) {
      debugPrint('EmbeddingStorageService: Unsupported version $version');
      return null;
    }

    final dimension = data.getUint32(8, Endian.little);
    final count = data.getUint32(12, Endian.little);

    var offset = 16;

    // Read variant string
    final variantLen = data.getUint16(offset, Endian.little);
    offset += 2;
    final variant = utf8.decode(bytes.sublist(offset, offset + variantLen));
    offset += variantLen;

    if (variant != expectedVariant) {
      debugPrint('EmbeddingStorageService: Binary variant mismatch');
      return null;
    }

    // Read entries
    final embeddings = <String, Float32List>{};
    for (var i = 0; i < count; i++) {
      // ID
      final idLen = data.getUint16(offset, Endian.little);
      offset += 2;
      final id = utf8.decode(bytes.sublist(offset, offset + idLen));
      offset += idLen;

      // Embedding
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
    String modelVariant,
    int embeddingCount,
  ) async {
    final meta = {
      'modelVariant': modelVariant,
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
