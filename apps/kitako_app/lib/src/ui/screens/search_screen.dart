import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../services/image_search_service.dart';
import '../../models/search_models.dart';
import 'results_screen.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  final ImageSearchService searchService;

  const SearchScreen({super.key, required this.searchService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
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

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _imagesLoadedSubscription?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    if (_searchController.text.trim().isEmpty) return;
    widget.searchService.searchImages(_searchController.text.trim());
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
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
            ),
            const SizedBox(height: 16),
            Text(
              'Searching for "${_currentSearchState.query}"...',
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFF999999),
                fontSize: 16,
              ),
            ),
            // Show normalized query if different from original
            if (_currentSearchState.normalizedQuery != null &&
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
          ],
        ),
      );
    }

    if (_currentSearchState.status == SearchStatus.success) {
      final results = _currentSearchState.result?.images ?? [];
      final hasNormalization = _currentSearchState.normalizedQuery != null &&
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
                    Expanded(
                      child: Text(
                        _currentSearchState.query,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
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

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  /// Build an image thumbnail widget
  Widget _buildImageThumbnail(ImageItem image, bool isDark) {
    // Try to load thumbnail if available
    if (image.thumbnail != null) {
      return Image.memory(
        image.thumbnail!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(image, isDark),
      );
    }

    // Try to load from file path
    final file = File(image.path);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(image, isDark),
      );
    }

    // Fallback to placeholder
    return _buildPlaceholder(image, isDark);
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

  /// Pick an image from gallery for image-to-image search
  Future<void> _pickImageForSearch() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image == null) return;

      // Show a dialog indicating image search is in progress
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Searching by image...'),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      // Read image bytes and perform image-to-image search
      final bytes = await image.readAsBytes();
      await widget.searchService.searchByImage(bytes);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
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
