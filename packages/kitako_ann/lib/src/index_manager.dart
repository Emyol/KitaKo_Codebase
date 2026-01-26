import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

/// Metadata about an ANN index
class IndexMetadata {
  /// The embedding dimension
  final int dimension;

  /// The space type (0=IP, 1=L2, 2=Cosine)
  final int spaceType;

  /// Number of items in the index
  final int itemCount;

  /// HNSW M parameter
  final int M;

  /// HNSW efConstruction parameter
  final int efConstruction;

  /// Creation timestamp
  final DateTime? createdAt;

  /// Optional description
  final String? description;

  const IndexMetadata({
    required this.dimension,
    required this.spaceType,
    required this.itemCount,
    this.M = 16,
    this.efConstruction = 200,
    this.createdAt,
    this.description,
  });

  factory IndexMetadata.fromJson(Map<String, dynamic> json) {
    return IndexMetadata(
      dimension: json['dimension'] as int,
      spaceType: json['space_type'] as int? ?? 0,
      itemCount: json['item_count'] as int,
      M: json['M'] as int? ?? 16,
      efConstruction: json['ef_construction'] as int? ?? 200,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'dimension': dimension,
        'space_type': spaceType,
        'item_count': itemCount,
        'M': M,
        'ef_construction': efConstruction,
        'created_at': createdAt?.toIso8601String(),
        'description': description,
      };

  @override
  String toString() => 'IndexMetadata(dim: $dimension, items: $itemCount)';
}

/// Manages ANN index files for on-device retrieval.
///
/// Handles:
/// - Copying index from Flutter assets to device storage
/// - Index versioning and updates
/// - Metadata loading
///
/// Example:
/// ```dart
/// final manager = IndexManager(
///   assetPath: 'assets/index/ann_index.bin',
///   metadataAssetPath: 'assets/index/ann_index.meta.json',
/// );
///
/// await manager.ensureIndexAvailable();
/// final indexPath = await manager.getIndexPath();
/// ```
class IndexManager {
  /// Asset path to the index file (for Flutter asset bundle)
  final String assetPath;

  /// Asset path to the metadata file (optional)
  final String? metadataAssetPath;

  /// Local filename for the index (in app documents directory)
  final String localFilename;

  /// Whether to overwrite existing local index
  final bool forceOverwrite;

  IndexMetadata? _metadata;

  /// The loaded metadata (null if not yet loaded or no metadata file)
  IndexMetadata? get metadata => _metadata;

  String? _localIndexPath;

  IndexManager({
    required this.assetPath,
    this.metadataAssetPath,
    String? localFilename,
    this.forceOverwrite = false,
  }) : localFilename = localFilename ?? _extractFilename(assetPath);

  static String _extractFilename(String path) {
    return path.split('/').last;
  }

  /// Gets the path to the index file on the local file system.
  ///
  /// If the index is bundled as an asset, this will first copy it
  /// to the app's documents directory.
  Future<String> getIndexPath() async {
    if (_localIndexPath != null && !forceOverwrite) {
      return _localIndexPath!;
    }

    await ensureIndexAvailable();
    return _localIndexPath!;
  }

  /// Ensures the index is available on the local file system.
  ///
  /// Copies from assets if needed.
  Future<void> ensureIndexAvailable() async {
    final appDocDir = await path_provider.getApplicationDocumentsDirectory();
    final localPath = '${appDocDir.path}/$localFilename';
    final localFile = File(localPath);

    // Check if we need to copy the index
    bool needsCopy = !localFile.existsSync() || forceOverwrite;

    // Also check metadata version if available
    if (!needsCopy && metadataAssetPath != null) {
      try {
        final currentMetadata = await _loadMetadataFromFile(localPath);
        final assetMetadata = await _loadMetadataFromAsset();
        if (currentMetadata != null &&
            assetMetadata != null &&
            currentMetadata.itemCount != assetMetadata.itemCount) {
          debugPrint(
            'IndexManager: Index version mismatch, will update '
            '(${currentMetadata.itemCount} -> ${assetMetadata.itemCount})',
          );
          needsCopy = true;
        }
      } catch (e) {
        debugPrint('IndexManager: Could not check version: $e');
      }
    }

    if (needsCopy) {
      debugPrint('IndexManager: Copying index from assets to $localPath');
      await _copyAssetToFile(assetPath, localPath);
      debugPrint('IndexManager: Index copied successfully');
    } else {
      debugPrint('IndexManager: Index already exists at $localPath');
    }

    _localIndexPath = localPath;

    // Load metadata
    await _loadMetadata();
  }

  /// Copies an asset file to the local file system.
  Future<void> _copyAssetToFile(String assetPath, String targetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      final file = File(targetPath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('IndexManager: Failed to copy asset: $e');
      rethrow;
    }
  }

  /// Loads metadata from asset or local file.
  Future<void> _loadMetadata() async {
    // Try loading from asset first
    if (metadataAssetPath != null) {
      _metadata = await _loadMetadataFromAsset();
      if (_metadata != null) {
        debugPrint('IndexManager: Loaded metadata: $_metadata');
        return;
      }
    }

    // Try loading from local file
    if (_localIndexPath != null) {
      _metadata = await _loadMetadataFromFile(_localIndexPath!);
      if (_metadata != null) {
        debugPrint('IndexManager: Loaded metadata from local: $_metadata');
      }
    }
  }

  Future<IndexMetadata?> _loadMetadataFromAsset() async {
    if (metadataAssetPath == null) return null;

    try {
      final jsonStr = await rootBundle.loadString(metadataAssetPath!);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return IndexMetadata.fromJson(json);
    } catch (e) {
      debugPrint('IndexManager: Could not load metadata from asset: $e');
      return null;
    }
  }

  Future<IndexMetadata?> _loadMetadataFromFile(String indexPath) async {
    final metaPath = indexPath.replaceAll('.bin', '.meta.json');
    final file = File(metaPath);

    if (!file.existsSync()) return null;

    try {
      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return IndexMetadata.fromJson(json);
    } catch (e) {
      debugPrint('IndexManager: Could not load metadata from file: $e');
      return null;
    }
  }

  /// Checks if the index file exists locally.
  Future<bool> isIndexAvailable() async {
    final appDocDir = await path_provider.getApplicationDocumentsDirectory();
    final localPath = '${appDocDir.path}/$localFilename';
    return File(localPath).existsSync();
  }

  /// Gets the size of the index file in bytes.
  Future<int?> getIndexSize() async {
    if (_localIndexPath == null) return null;
    final file = File(_localIndexPath!);
    if (!file.existsSync()) return null;
    return file.lengthSync();
  }

  /// Deletes the local index file.
  Future<void> deleteLocalIndex() async {
    final appDocDir = await path_provider.getApplicationDocumentsDirectory();
    final localPath = '${appDocDir.path}/$localFilename';
    final file = File(localPath);

    if (file.existsSync()) {
      await file.delete();
      debugPrint('IndexManager: Deleted local index');
    }

    _localIndexPath = null;
    _metadata = null;
  }
}
