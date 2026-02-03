import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';
import '../services/image_search_service.dart';

/// Controller for managing search state and operations
///
/// This controller provides a higher-level API for search functionality
/// and can be used with state management solutions like Provider/Riverpod.
///
/// Example usage:
/// ```dart
/// final controller = SearchController(searchService);
/// await controller.initialize();
///
/// controller.search('sunset beach');
///
/// controller.stateStream.listen((state) {
///   print('Status: ${state.status}');
/// });
/// ```
class SearchController extends ChangeNotifier {
  final ImageSearchService _searchService;

  /// Create a new SearchController
  SearchController(this._searchService);

  // ========== State ==========

  SearchState _state = const SearchState();
  StreamSubscription<SearchState>? _subscription;

  /// Current search state
  SearchState get state => _state;

  /// Whether search is in progress
  bool get isSearching => _state.isSearching;

  /// Whether results are available
  bool get hasResults => _state.hasResults;

  /// Current query text
  String get query => _state.query;

  /// Normalized query text (after Taglish processing)
  String? get normalizedQuery => _state.normalizedQuery;

  /// Search results
  List<ImageItem> get results => _state.result?.images ?? [];

  /// Number of results
  int get resultCount => _state.result?.resultCount ?? 0;

  /// Error message if any
  String? get error => _state.error;

  // ========== Stream ==========

  final _stateController = StreamController<SearchState>.broadcast();

  /// Stream of search state changes
  Stream<SearchState> get stateStream => _stateController.stream;

  // ========== Lifecycle ==========

  /// Initialize the controller
  ///
  /// Must be called before using search functionality.
  Future<bool> initialize() async {
    try {
      // Subscribe to search service state changes
      _subscription = _searchService.searchStateStream.listen(_onStateChanged);

      // Initialize the underlying service
      final success = await _searchService.initialize();
      if (!success) {
        debugPrint('SearchController: Failed to initialize search service');
      }
      return success;
    } catch (e) {
      debugPrint('SearchController: Initialization error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stateController.close();
    super.dispose();
  }

  // ========== Search Operations ==========

  /// Perform a text search
  ///
  /// The query will be normalized using TaglishNormalizer before searching.
  ///
  /// Parameters:
  /// - [query]: The search query text
  /// - [topK]: Number of results to return (optional)
  /// - [threshold]: Minimum similarity threshold (optional)
  Future<void> search(String query, {int? topK, double? threshold}) async {
    if (query.trim().isEmpty) {
      clearSearch();
      return;
    }

    try {
      await _searchService.searchImages(
        query.trim(),
        topK: topK,
        threshold: threshold,
      );
    } catch (e) {
      debugPrint('SearchController: Search error: $e');
      _updateState(_state.copyWith(
        status: SearchStatus.error,
        error: e.toString(),
      ));
    }
  }

  /// Clear the current search
  void clearSearch() {
    _searchService.clearSearch();
    _updateState(const SearchState());
  }

  // ========== Image Operations ==========

  /// Get all loaded images (not filtered by search)
  List<ImageItem> getAllImages() {
    return _searchService.getAllImages();
  }

  /// Get a specific image by ID
  ImageItem? getImageById(String id) {
    return _searchService.getImageById(id);
  }

  /// Refresh images from device
  Future<void> refreshImages() async {
    try {
      await _searchService.refreshImages();
      notifyListeners();
    } catch (e) {
      debugPrint('SearchController: Refresh error: $e');
    }
  }

  // ========== Configuration ==========

  /// Set the number of results to return
  void setTopK(int value) {
    _searchService.topK = value;
  }

  /// Set the minimum similarity threshold
  void setSimilarityThreshold(double value) {
    _searchService.similarityThreshold = value;
  }

  // ========== Statistics ==========

  /// Get service statistics
  Map<String, dynamic> getStats() {
    return _searchService.getStats();
  }

  // ========== Private Methods ==========

  /// Handle state changes from the search service
  void _onStateChanged(SearchState newState) {
    _updateState(newState);
  }

  /// Update state and notify listeners
  void _updateState(SearchState newState) {
    _state = newState;
    _stateController.add(newState);
    notifyListeners();
  }
}
