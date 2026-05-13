import 'dart:typed_data';

/// Represents an image with its metadata and path
class ImageItem {
  /// Unique identifier for the image
  final String id;

  /// File path to the image on device
  final String path;

  /// Optional thumbnail data for quick display
  final Uint8List? thumbnail;

  /// Image creation timestamp
  final DateTime? createdAt;

  /// Image modification timestamp
  final DateTime? modifiedAt;

  /// Image file size in bytes
  final int? sizeBytes;

  /// Image width in pixels
  final int? width;

  /// Image height in pixels
  final int? height;

  const ImageItem({
    required this.id,
    required this.path,
    this.thumbnail,
    this.createdAt,
    this.modifiedAt,
    this.sizeBytes,
    this.width,
    this.height,
  });

  /// Creates a copy of this ImageItem with updated fields
  ImageItem copyWith({
    String? id,
    String? path,
    Uint8List? thumbnail,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? sizeBytes,
    int? width,
    int? height,
  }) {
    return ImageItem(
      id: id ?? this.id,
      path: path ?? this.path,
      thumbnail: thumbnail ?? this.thumbnail,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ImageItem && other.id == id && other.path == path;
  }

  @override
  int get hashCode => id.hashCode ^ path.hashCode;

  /// Get the filename from the path
  String get name {
    final segments = path.split('/');
    return segments.isEmpty ? 'Unknown' : segments.last;
  }

  @override
  String toString() => 'ImageItem(id: $id, path: $path)';
}

/// A search result paired with its similarity score.
class SearchResultWithScore {
  final ImageItem image;
  final double similarity;

  const SearchResultWithScore({required this.image, required this.similarity});
}

/// Result of a search operation
class SearchResult {
  /// List of images matching the search query
  final List<ImageItem> images;

  /// Similarity scores parallel to [images] (index-aligned).
  /// Null when scores are not available (e.g. mock backend).
  final List<double>? scores;

  /// Query used for search
  final String query;

  /// Time taken to generate the query embedding (ONNX inference) in milliseconds
  final int? embeddingTimeMs;

  /// Time taken to search the ANN index in milliseconds
  final int? searchTimeMs;

  /// Total number of images scanned
  final int? totalScanned;

  const SearchResult({
    required this.images,
    required this.query,
    this.scores,
    this.embeddingTimeMs,
    this.searchTimeMs,
    this.totalScanned,
  });

  /// Whether the search returned any results
  bool get hasResults => images.isNotEmpty;

  /// Number of results found
  int get resultCount => images.length;

  /// Get the similarity score for a result at [index], or null if unavailable.
  double? scoreAt(int index) {
    if (scores == null || index < 0 || index >= scores!.length) return null;
    return scores![index];
  }

  @override
  String toString() =>
      'SearchResult(query: $query, results: $resultCount, timeMs: $searchTimeMs)';
}

/// Confidence level of a search result, used to decide whether to show suggestions.
enum QueryConfidence {
  /// Top result score is strong — no suggestions needed.
  strong,

  /// Top result score is low but non-zero — show soft suggestions alongside results.
  weak,

  /// Zero results or all scores below floor — show suggestions prominently.
  failed,
}

/// Status of a search operation
enum SearchStatus {
  /// No search has been performed yet
  idle,

  /// Search is currently in progress
  searching,

  /// Search completed successfully with results
  success,

  /// Search completed but no results found
  noResults,

  /// Search failed with an error
  error,
}

/// State of the search functionality
class SearchState {
  /// Current status of the search
  final SearchStatus status;

  /// Current search query (original input)
  final String query;

  /// Normalized query after Taglish processing
  final String? normalizedQuery;

  /// Search results if available
  final SearchResult? result;

  /// Error message if search failed
  final String? error;

  /// Query image thumbnail for image-to-image search
  final Uint8List? queryImage;

  /// Alternative query suggestions generated when confidence is weak or failed.
  /// Null when no suggestions were generated (e.g. strong result or image search).
  final List<String>? suggestions;

  /// Confidence level of the last search result.
  final QueryConfidence? queryConfidence;

  const SearchState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.normalizedQuery,
    this.result,
    this.error,
    this.queryImage,
    this.suggestions,
    this.queryConfidence,
  });

  /// Whether this is an image-to-image search
  bool get isImageSearch => queryImage != null;

  /// Creates a copy with updated fields
  SearchState copyWith({
    SearchStatus? status,
    String? query,
    String? normalizedQuery,
    SearchResult? result,
    String? error,
    Uint8List? queryImage,
    List<String>? suggestions,
    QueryConfidence? queryConfidence,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      normalizedQuery: normalizedQuery ?? this.normalizedQuery,
      result: result ?? this.result,
      error: error ?? this.error,
      queryImage: queryImage ?? this.queryImage,
      suggestions: suggestions ?? this.suggestions,
      queryConfidence: queryConfidence ?? this.queryConfidence,
    );
  }

  /// Whether search is currently in progress
  bool get isSearching => status == SearchStatus.searching;

  /// Whether search has completed
  bool get hasCompleted =>
      status == SearchStatus.success ||
      status == SearchStatus.noResults ||
      status == SearchStatus.error;

  /// Whether results are available
  bool get hasResults => result?.hasResults ?? false;

  @override
  String toString() => 'SearchState(status: $status, query: $query, isImageSearch: $isImageSearch)';
}
