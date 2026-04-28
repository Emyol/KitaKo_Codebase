import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;

/// IO-specific helper functions for ANN service
class AnnPlatformHelper {
  static bool get isSupported => true;

  /// Copy asset to local file system (required for native FFI)
  /// Returns null if the asset is empty or doesn't exist
  static Future<String?> copyAssetToFile(String assetPath, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    // Check if file already exists and is non-empty
    if (await file.exists()) {
      final size = await file.length();
      if (size > 0) {
        return filePath;
      }
      // Delete empty file to allow re-copy
      await file.delete();
    }

    // Copy from assets
    try {
      final data = await rootBundle.load(assetPath);
      // Skip if the asset is empty
      if (data.lengthInBytes == 0) {
        return null;
      }
      await file.writeAsBytes(data.buffer.asUint8List());
      return filePath;
    } catch (e) {
      // Asset doesn't exist or can't be loaded
      return null;
    }
  }

  /// Create the native ANN client
  static Future<AnnClientWrapper> createClient({
    required String indexPath,
  }) async {
    final client = ann.AnnSearchService();
    await client.initialize(
      indexPath: indexPath,
      config: ann.AnnClientConfig.siglip768,
    );
    return AnnClientWrapper._(client);
  }
}

/// Wrapper around the native ANN client
class AnnClientWrapper {
  final ann.AnnSearchService _client;

  AnnClientWrapper._(this._client);

  int get indexSize => _client.indexSize;

  Future<List<AnnSearchResult>> search(
    List<double> query, {
    required int k,
    required double threshold,
  }) async {
    // Convert List<double> to Float32List
    final float32Query = Float32List.fromList(query);
    
    final results = await _client.search(
      float32Query,
      k: k,
      threshold: threshold,
    );
    // Use similarity (derived from distance) as score
    return results.map((r) => AnnSearchResult(id: r.id, score: r.similarity)).toList();
  }

  void dispose() => _client.dispose();
}

/// Platform-agnostic search result
class AnnSearchResult {
  final int id;
  final double score;

  AnnSearchResult({required this.id, required this.score});
}
