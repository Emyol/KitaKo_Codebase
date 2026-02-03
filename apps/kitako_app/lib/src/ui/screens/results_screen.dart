import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';
import 'details_screen.dart';

/// Screen displaying search results in a grid layout
///
/// Shows images matching the search query with similarity scores
/// and allows navigation to detailed image view.
class ResultsScreen extends StatelessWidget {
  /// The search result to display
  final SearchResult searchResult;

  /// Reference to the search service for additional operations
  final ImageSearchService searchService;

  const ResultsScreen({
    super.key,
    required this.searchResult,
    required this.searchService,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Results'),
        actions: [
          // View mode toggle (grid/list)
          IconButton(
            icon: Icon(
              Icons.grid_view,
              color: Theme.of(context).appBarTheme.titleTextStyle?.color,
            ),
            onPressed: () {
              // TODO: Toggle between grid and list view
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Query info header
          _buildQueryHeader(context, isDark, textColor),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '${searchResult.resultCount} result${searchResult.resultCount == 1 ? '' : 's'} found',
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ),

          // Results grid
          Expanded(
            child: searchResult.hasResults
                ? _buildResultsGrid(context, isDark)
                : _buildNoResultsView(context, isDark, textColor),
          ),
        ],
      ),
    );
  }

  /// Build the query information header
  Widget _buildQueryHeader(BuildContext context, bool isDark, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.search,
                color: const Color(0xFF4A90E2),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"${searchResult.query}"',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (searchResult.searchTimeMs != null) ...[
            const SizedBox(height: 4),
            Text(
              'Search completed in ${searchResult.searchTimeMs}ms',
              style: TextStyle(
                color: textColor.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build the grid of search results
  Widget _buildResultsGrid(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: searchResult.images.length,
        itemBuilder: (context, index) {
          final image = searchResult.images[index];
          return _buildResultCard(context, image, index, isDark);
        },
      ),
    );
  }

  /// Build a single result card with image and metadata
  Widget _buildResultCard(
    BuildContext context,
    ImageItem image,
    int index,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: () => _navigateToDetails(context, image),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImageWidget(image, isDark),
                    // Ranking badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A90E2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Similarity score badge (mock for now)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 12,
                              color: _getSimilarityColor(index),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getMockSimilarityScore(index),
                              style: TextStyle(
                                color: _getSimilarityColor(index),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Image info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image.name,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatFileSize(image.sizeBytes),
                    style: TextStyle(
                      color: (isDark ? Colors.white : Colors.black87)
                          .withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the image widget - tries to load from file, falls back to placeholder
  Widget _buildImageWidget(ImageItem image, bool isDark) {
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

  /// Build a placeholder widget for images that can't be loaded
  Widget _buildPlaceholder(ImageItem image, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              color: isDark
                  ? Colors.white.withOpacity(0.3)
                  : Colors.black.withOpacity(0.3),
              size: 48,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                image.name,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withOpacity(0.4)
                      : Colors.black.withOpacity(0.4),
                  fontSize: 10,
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

  /// Build view when no results are found
  Widget _buildNoResultsView(BuildContext context, bool isDark, Color textColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF1E3A5F), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.search_off,
              size: 48,
              color: Color(0xFF4A90E2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No results found',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search query',
            style: TextStyle(
              color: textColor.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.search),
            label: const Text('New Search'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to the details screen for a specific image
  void _navigateToDetails(BuildContext context, ImageItem image) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          image: image,
          searchService: searchService,
        ),
      ),
    );
  }

  /// Format file size in human-readable format
  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown size';

    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get mock similarity score for demo purposes
  /// In production, this should come from the ANN search results
  String _getMockSimilarityScore(int index) {
    // Simulate decreasing similarity scores
    final score = 0.95 - (index * 0.05);
    return '${(score.clamp(0.5, 0.99) * 100).toInt()}%';
  }

  /// Get color based on similarity score
  Color _getSimilarityColor(int index) {
    if (index < 3) return Colors.greenAccent;
    if (index < 6) return Colors.yellowAccent;
    return Colors.orangeAccent;
  }
}
