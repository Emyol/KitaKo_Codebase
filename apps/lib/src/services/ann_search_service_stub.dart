/// Stub implementation for web platform where native ANN is not available.
/// This file is used via conditional imports when running on web.

class AnnPlatformHelper {
  static bool get isSupported => false;

  static Future<String> copyAssetToFile(String assetPath, String fileName) async {
    throw UnsupportedError('Native ANN not supported on web');
  }

  static Future<AnnClientWrapper> createClient({
    required String indexPath,
  }) async {
    throw UnsupportedError(
      'Native ANN search is not supported on web platform. '
      'HNSW requires native FFI binaries which are not available in browsers.',
    );
  }
}

/// Wrapper stub for web
class AnnClientWrapper {
  int get indexSize => 0;

  Future<List<AnnSearchResult>> search(
    List<double> query, {
    required int k,
    required double threshold,
  }) async {
    throw UnsupportedError('Not supported on web');
  }

  void dispose() {}
}

/// Platform-agnostic search result
class AnnSearchResult {
  final int id;
  final double score;

  AnnSearchResult({required this.id, required this.score});
}
