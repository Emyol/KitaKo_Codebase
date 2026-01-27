import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;

/// IO-specific helper functions for ANN service
class AnnPlatformHelper {
  static bool get isSupported => true;

  /// Copy asset to local file system (required for native FFI)
  static Future<String> copyAssetToFile(String assetPath, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    // Check if file already exists
    if (await file.exists()) {
      return filePath;
    }

    // Copy from assets
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List());

    return filePath;
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
    final results = await _client.search(
      query,
      k: k,
      threshold: threshold,
    );
    return results.map((r) => AnnSearchResult(id: r.id, score: r.score)).toList();
  }

  void dispose() => _client.dispose();
}

/// Platform-agnostic search result
class AnnSearchResult {
  final int id;
  final double score;

  AnnSearchResult({required this.id, required this.score});
}
