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

/// Result of a search operation
class SearchResult {
  /// List of images matching the search query
  final List<ImageItem> images;

  /// Query used for search
  final String query;

  /// Time taken to perform search in milliseconds
  final int? searchTimeMs;

  /// Total number of images scanned
  final int? totalScanned;

  const SearchResult({
    required this.images,
    required this.query,
    this.searchTimeMs,
    this.totalScanned,
  });

  /// Whether the search returned any results
  bool get hasResults => images.isNotEmpty;

  /// Number of results found
  int get resultCount => images.length;

  @override
  String toString() =>
      'SearchResult(query: $query, results: $resultCount, timeMs: $searchTimeMs)';
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

  const SearchState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.normalizedQuery,
    this.result,
    this.error,
  });

  /// Creates a copy with updated fields
  SearchState copyWith({
    SearchStatus? status,
    String? query,
    String? normalizedQuery,
    SearchResult? result,
    String? error,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      normalizedQuery: normalizedQuery ?? this.normalizedQuery,
      result: result ?? this.result,
      error: error ?? this.error,
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
  String toString() => 'SearchState(status: $status, query: $query)';
}

/// Search result with similarity score (for alpha testing)
/// 
/// Used by ANNSearchService.searchSimilarWithScores() to return
/// results with their actual similarity scores for evaluation.
class SearchResultWithScore {
  /// The image result
  final ImageItem image;
  
  /// Cosine similarity score (0.0 to 1.0 for normalized embeddings)
  final double similarity;

  const SearchResultWithScore({
    required this.image,
    required this.similarity,
  });

  @override
  String toString() => 'SearchResultWithScore(${image.name}, similarity: ${similarity.toStringAsFixed(4)})';
}
