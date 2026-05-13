import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'alpha_test_screen.dart';
import 'people_screen.dart';
import 'details_screen.dart';
import '../theme/theme_notifier.dart';
import '../../services/image_search_service.dart';
import '../../services/search_history_service.dart';
import '../../state/settings_controller.dart';
import '../../models/search_models.dart';

class HomeScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService searchService;
  final SettingsController settingsController;

  const HomeScreen({
    super.key,
    required this.themeNotifier,
    required this.searchService,
    required this.settingsController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ImageItem> _images = [];
  StreamSubscription<List<ImageItem>>? _imagesSubscription;
  StreamSubscription<SearchState>? _searchSubscription;
  SearchState _searchState = const SearchState();
  bool _isLoading = true;
  final SearchHistoryService _historyService = SearchHistoryService();

  @override
  void initState() {
    super.initState();
    _loadImages();
    _listenForImageUpdates();
    _listenForSearchState();
    _historyService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _imagesSubscription?.cancel();
    _searchSubscription?.cancel();
    super.dispose();
  }

  void _listenForImageUpdates() {
    _imagesSubscription = widget.searchService.imagesLoadedStream.listen((images) {
      debugPrint('HomeScreen: Received ${images.length} images from stream');
      if (mounted) {
        setState(() {
          _images = images;
          _isLoading = false;
        });
      }
    });
  }

  void _listenForSearchState() {
    _searchState = widget.searchService.currentState;
    _searchSubscription = widget.searchService.searchStateStream.listen((state) {
      if (mounted) setState(() => _searchState = state);
    });
  }

  Future<void> _loadImages() async {
    final images = widget.searchService.getAllImages();
    debugPrint('HomeScreen: Initial load found ${images.length} images');
    if (mounted) {
      setState(() {
        _images = images;
        _isLoading = images.isEmpty; // Only show loading if no images yet
      });
    }
  }

  void _openSearch() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SearchScreen(
              searchService: widget.searchService,
              historyService: _historyService,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    ).then((_) {
      // Refresh so the search bar shows the latest query
      if (mounted) setState(() {});
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          themeNotifier: widget.themeNotifier,
          searchService: widget.searchService,
          settingsController: widget.settingsController,
        ),
      ),
    );
  }

  void _openDetails(ImageItem image, int index, {List<ImageItem>? imageList}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          image: image,
          searchService: widget.searchService,
          imageList: imageList ?? _images,
          currentIndex: index,
          // popCount=1: pops DetailsScreen back to HomeScreen, which shows results
        ),
      ),
    );
  }

  Future<void> _findSimilar(ImageItem image) async {
    // Results appear directly on HomeScreen via the searchStateStream listener
    try {
      await widget.searchService.searchByImageId(image.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to find similar images: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildPlaceholder(ImageItem image, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            color: isDark ? Colors.white24 : Colors.black26,
            size: 40,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              image.name,
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the main content area: searching spinner, results grid, or gallery.
  Widget _buildContent(bool isDark) {
    final status = _searchState.status;

    // ── Searching ─────────────────────────────────────────────────────────────
    if (status == SearchStatus.searching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_searchState.queryImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _searchState.queryImage!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
            ),
            const SizedBox(height: 12),
            Text(
              'Finding similar images…',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // ── Results ───────────────────────────────────────────────────────────────
    if (status == SearchStatus.success) {
      final results = _searchState.result?.images ?? [];
      final scores = _searchState.result?.scores;

      return Column(
        children: [
          // Header: query thumbnail + count + close
          Container(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                if (_searchState.queryImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      _searchState.queryImage!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  '${results.length} similar image${results.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  tooltip: 'Back to gallery',
                  onPressed: widget.searchService.clearSearch,
                ),
              ],
            ),
          ),
          // Results grid
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      'No similar images found',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 14,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final image = results[index];
                        final score =
                            scores != null && index < scores.length
                                ? scores[index]
                                : null;
                        return Material(
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () =>
                                _openDetails(image, index, imageList: results),
                            borderRadius: BorderRadius.circular(8),
                            splashColor:
                                isDark ? Colors.white12 : Colors.black12,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(image.path),
                                    fit: BoxFit.cover,
                                    cacheWidth: 256,
                                    errorBuilder: (_, _, _) =>
                                        _buildPlaceholder(image, isDark),
                                  ),
                                  // Rank badge
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4A90E2),
                                        borderRadius: BorderRadius.circular(6),
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
                                  // Score badge
                                  if (score != null)
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.7,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${(score * 100).toStringAsFixed(1)}%',
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

    // ── Gallery (idle / noResults / error) ────────────────────────────────────
    if (_images.isEmpty) {
      return Center(
        child: _isLoading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading gallery...',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                ],
              )
            : Text(
                'No images found',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                ),
              ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: _images.length,
        itemBuilder: (context, index) {
          final image = _images[index];
          return Material(
            color: isDark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _openDetails(image, index),
              onLongPress: () => _findSimilar(image),
              borderRadius: BorderRadius.circular(8),
              splashColor: isDark ? Colors.white12 : Colors.black12,
              highlightColor: isDark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(image.path),
                  fit: BoxFit.cover,
                  cacheWidth: 256,
                  errorBuilder: (_, _, _) =>
                      _buildPlaceholder(image, isDark),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openAlphaTest() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            AlphaTestScreen(searchService: widget.searchService),
      ),
    );
  }

  void _openPeople() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PeopleScreen(searchService: widget.searchService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          // Face Recognition button
          IconButton(
            icon: const Icon(
              Icons.face_outlined,
              color: Colors.tealAccent,
              size: 28,
            ),
            tooltip: 'People',
            onPressed: _openPeople,
          ),
          // Alpha Testing button
          IconButton(
            icon: Icon(
              Icons.science_outlined,
              color: Colors.amber,
              size: 28,
            ),
            tooltip: 'Alpha Testing',
            onPressed: _openAlphaTest,
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: Theme.of(context).appBarTheme.titleTextStyle?.color,
              size: 28,
            ),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildContent(isDark)),
          // Search Bar at Bottom
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
              child: GestureDetector(
                onTap: _openSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFE0E0E0),
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
                        child: Text(
                          _historyService.queries.isNotEmpty
                              ? _historyService.queries.first
                              : 'Search...',
                          style: TextStyle(
                            color: _historyService.queries.isNotEmpty
                                ? (isDark ? Colors.white54 : Colors.black54)
                                : (isDark
                                    ? const Color(0xFF666666)
                                    : const Color(0xFF999999)),
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
