import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/image_search_service.dart';
import '../../services/search_history_service.dart';
import '../../models/search_models.dart';
import 'results_screen.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  final ImageSearchService searchService;
  final SearchHistoryService historyService;

  const SearchScreen({
    super.key,
    required this.searchService,
    required this.historyService,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  SearchHistoryService get _historyService => widget.historyService;
  StreamSubscription<SearchState>? _searchSubscription;
  StreamSubscription<List<ImageItem>>? _imagesLoadedSubscription;
  late SearchState _currentSearchState;
  List<ImageItem> _indexedImages = [];
  bool _isLoadingGallery = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current state from service
    _currentSearchState = widget.searchService.currentState;

    // Rebuild when text changes (for history filtering & clear button visibility)
    _searchController.addListener(_onSearchTextChanged);

    // Auto-focus the search field when screen opens
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    // Listen to search state changes
    _searchSubscription = widget.searchService.searchStateStream.listen((
      state,
    ) {
      if (mounted) {
        setState(() {
          _currentSearchState = state;
        });
      }
    });

    // Listen for when images are loaded/indexed
    _imagesLoadedSubscription = widget.searchService.imagesLoadedStream.listen((
      images,
    ) {
      if (mounted) {
        setState(() {
          _indexedImages = images;
        });
      }
    });

    // Load initial indexed images if already available
    _indexedImages = widget.searchService.getAllImages();
  }

  void _onSearchTextChanged() => setState(() {});

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _imagesLoadedSubscription?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    _historyService.addQuery(query);
    widget.searchService.searchImages(query);
  }

  /// Fill the search field with a history entry and immediately run the search.
  void _runHistoryQuery(String query) {
    _searchController.text = query;
    _performSearch();
  }

  /// Tappable suggestion chips shown when a query produces weak or no results.
  Widget _buildSuggestionChips(List<String> suggestions, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map(
                  (s) => ActionChip(
                    avatar: const Icon(Icons.search, size: 16),
                    label: Text(s),
                    onPressed: () => _runHistoryQuery(s),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Search'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: Theme.of(context).appBarTheme.titleTextStyle?.color,
              size: 28,
            ),
            onPressed: () {
              // Settings action
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Results or Empty State
          Expanded(child: _buildSearchContent()),
          // Search Bar with Keyboard
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4A90E2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            color: isDark
                                ? const Color(0xFF666666)
                                : const Color(0xFF999999),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search...',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF666666)
                                      : const Color(0xFF999999),
                                  fontSize: 16,
                                ),
                              ),
                              onSubmitted: (_) => _performSearch(),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: isDark
                                    ? const Color(0xFF666666)
                                    : const Color(0xFF999999),
                                size: 20,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                widget.searchService.clearSearch();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Image picker button for image-to-image search
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4A90E2).withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.image_search,
                        color: const Color(0xFF4A90E2),
                      ),
                      onPressed: _pickImageForSearch,
                      tooltip: 'Search by image',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90E2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _performSearch,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    if (_currentSearchState.status == SearchStatus.searching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_currentSearchState.isImageSearch &&
                _currentSearchState.queryImage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _currentSearchState.queryImage!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
            ),
            const SizedBox(height: 16),
            Text(
              _currentSearchState.isImageSearch
                  ? 'Finding similar images...'
                  : 'Searching for "${_currentSearchState.query}"...',
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFF999999),
                fontSize: 16,
              ),
            ),
            // Show normalized query if different from original
            if (!_currentSearchState.isImageSearch &&
                _currentSearchState.normalizedQuery != null &&
                _currentSearchState.normalizedQuery != _currentSearchState.query)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Normalized: "${_currentSearchState.normalizedQuery}"',
                  style: TextStyle(
                    color: const Color(0xFF4A90E2).withOpacity(0.8),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (_currentSearchState.status == SearchStatus.noResults) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1E3A5F), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.search_off,
                    size: 50,
                    color: Color(0xFF4A90E2),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4A90E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No result has been found',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching for something else',
              style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 14),
            ),
            if (_currentSearchState.suggestions?.isNotEmpty == true) ...[
              const SizedBox(height: 24),
              _buildSuggestionChips(
                _currentSearchState.suggestions!,
                'Try instead:',
              ),
            ],
          ],
        ),
      );
    }

    if (_currentSearchState.status == SearchStatus.success) {
      final results = _currentSearchState.result?.images ?? [];
      final hasNormalization = !_currentSearchState.isImageSearch &&
          _currentSearchState.normalizedQuery != null &&
          _currentSearchState.normalizedQuery != _currentSearchState.query;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Show query image thumbnail for image search
                    if (_currentSearchState.isImageSearch &&
                        _currentSearchState.queryImage != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _currentSearchState.queryImage!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        _currentSearchState.isImageSearch
                            ? 'Similar Images'
                            : _currentSearchState.query,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_currentSearchState.isImageSearch)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          widget.searchService.clearSearch();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    else
                      Icon(
                        Icons.tune,
                        color: isDark
                            ? const Color(0xFF666666)
                            : const Color(0xFF999999),
                        size: 24,
                      ),
                  ],
                ),
                // Show normalized query chip if different from original
                if (hasNormalization)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF4A90E2).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.translate,
                            size: 14,
                            color: const Color(0xFF4A90E2),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Normalized: "${_currentSearchState.normalizedQuery}"',
                            style: TextStyle(
                              color: const Color(0xFF4A90E2),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Weak-result suggestions (shown when results exist but confidence is low)
          if (_currentSearchState.queryConfidence == QueryConfidence.weak &&
              _currentSearchState.suggestions?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: _buildSuggestionChips(
                _currentSearchState.suggestions!,
                'Try instead:',
              ),
            ),
          // View All Results button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${results.length} result${results.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: textColor.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _navigateToResults(),
                  icon: const Icon(Icons.grid_view, size: 18),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4A90E2),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final image = results[index];
                  return GestureDetector(
                    onTap: () => _navigateToDetails(image, results, index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildImageThumbnail(image, isDark),
                            // Rank badge
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4A90E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '#${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            // Similarity score badge
                            if (_currentSearchState.result?.scoreAt(index) != null)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${(_currentSearchState.result!.scoreAt(index)! * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    // Idle: show recent searches if any match the current input
    final inputText = _searchController.text.trim().toLowerCase();
    final historyMatches = inputText.isEmpty
        ? _historyService.queries
        : _historyService.queries
            .where((q) => q.toLowerCase().contains(inputText))
            .toList();

    if (historyMatches.isNotEmpty) {
      return _buildHistoryList(isDark, textColor, historyMatches, showClearAll: inputText.isEmpty);
    }

    // Default state - show gallery of indexed images
    if (_indexedImages.isEmpty) {
      // No images indexed yet - show logo
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF1E3A5F), width: 3),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer circles
                  Positioned(
                    top: 30,
                    left: 30,
                    child: _buildCircle(20, const Color(0xFF4A90E2)),
                  ),
                  Positioned(
                    top: 30,
                    right: 30,
                    child: _buildCircle(20, const Color(0xFF5BA3F5)),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 30,
                    child: _buildCircle(20, const Color(0xFF5BA3F5)),
                  ),
                  Positioned(
                    bottom: 30,
                    right: 30,
                    child: _buildCircle(20, const Color(0xFF4A90E2)),
                  ),
                  // Center circle
                  _buildCircle(35, const Color(0xFF4A90E2)),
                  // Inner design
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF5BA3F5), width: 2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoadingGallery)
              Column(
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loading gallery...',
                    style: TextStyle(
                      color: textColor.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    // Show gallery of all indexed images
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Indexed Images',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_indexedImages.length} images',
                style: TextStyle(
                  color: textColor.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _indexedImages.length,
              itemBuilder: (context, index) {
                final image = _indexedImages[index];
                return GestureDetector(
                  onTap: () => _navigateToDetails(image, _indexedImages, index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildImageThumbnail(image, isDark),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList(
    bool isDark,
    Color textColor,
    List<String> queries, {
    required bool showClearAll,
  }) {
    final hintColor = isDark ? Colors.white38 : Colors.black38;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              if (showClearAll)
                TextButton(
                  onPressed: () async {
                    await _historyService.clearAll();
                    setState(() {});
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4A90E2),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear all', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
        // History items
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: queries.length,
            itemBuilder: (context, index) {
              final query = queries[index];
              return ListTile(
                dense: true,
                leading: Icon(Icons.history, color: hintColor, size: 20),
                title: Text(
                  query,
                  style: TextStyle(color: textColor, fontSize: 15),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close, color: hintColor, size: 18),
                  splashRadius: 18,
                  onPressed: () async {
                    await _historyService.removeQuery(query);
                    setState(() {});
                  },
                ),
                onTap: () => _runHistoryQuery(query),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  /// Build an image thumbnail widget
  Widget _buildImageThumbnail(ImageItem image, bool isDark) {
    return Image.file(
      File(image.path),
      fit: BoxFit.cover,
      cacheWidth: 256,
      errorBuilder: (_, _, _) => _buildPlaceholder(image, isDark),
    );
  }

  /// Build placeholder for images that can't be loaded
  Widget _buildPlaceholder(ImageItem image, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              color: isDark
                  ? Colors.white.withOpacity(0.3)
                  : Colors.black.withOpacity(0.3),
              size: 32,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                image.name,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withOpacity(0.5)
                      : Colors.black.withOpacity(0.5),
                  fontSize: 9,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to the full results screen
  void _navigateToResults() {
    final result = _currentSearchState.result;
    if (result == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          searchResult: result,
          searchService: widget.searchService,
        ),
      ),
    );
  }

  /// Navigate to image details screen
  void _navigateToDetails(ImageItem image, List<ImageItem> allResults, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          image: image,
          searchService: widget.searchService,
          imageList: allResults,
          currentIndex: index,
        ),
      ),
    );
  }

  /// Show bottom sheet to choose image source, then perform image search
  void _pickImageForSearch() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Search by Image',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _showInAppImagePicker();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _performImageSearch(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Open in-app picker that shows only the 751 test dataset images
  Future<void> _showInAppImagePicker() async {
    final images = widget.searchService.getAllImages();
    if (images.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No test images available'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final selected = await Navigator.of(context).push<ImageItem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TestImagePickerScreen(images: images),
      ),
    );

    if (selected == null || !mounted) return;

    try {
      final bytes = await widget.searchService.imageLoader.loadImageBytes(selected.id);
      if (bytes == null || bytes.isEmpty) return;
      await widget.searchService.searchByImage(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load image: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  /// Pick image from the given source and perform image-to-image search
  Future<void> _performImageSearch(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image == null) return;

      // Read image bytes and perform image-to-image search
      final bytes = await image.readAsBytes();
      await widget.searchService.searchByImage(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image search failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }
}

/// Full-screen image picker that shows only the test dataset images.
///
/// Returns the selected [ImageItem] via [Navigator.pop].
class _TestImagePickerScreen extends StatelessWidget {
  final List<ImageItem> images;

  const _TestImagePickerScreen({required this.images});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${images.length} Images'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          final image = images[index];
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(image),
            child: _buildThumb(image, isDark),
          );
        },
      ),
    );
  }

  Widget _buildThumb(ImageItem image, bool isDark) {
    return Image.file(
      File(image.path),
      fit: BoxFit.cover,
      cacheWidth: 256,
      errorBuilder: (_, _, _) => Container(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
        child: Icon(
          Icons.image_outlined,
          color: isDark ? Colors.white30 : Colors.black26,
        ),
      ),
    );
  }
}
