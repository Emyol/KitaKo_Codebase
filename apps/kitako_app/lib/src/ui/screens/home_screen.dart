import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'alpha_test_screen.dart';
import 'details_screen.dart';
import '../theme/theme_notifier.dart';
import '../../services/image_search_service.dart';
import '../../models/search_models.dart';

class HomeScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService searchService;

  const HomeScreen({
    super.key,
    required this.themeNotifier,
    required this.searchService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ImageItem> _images = [];
  StreamSubscription<List<ImageItem>>? _imagesSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _listenForImageUpdates();
  }

  @override
  void dispose() {
    _imagesSubscription?.cancel();
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
            SearchScreen(searchService: widget.searchService),
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
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            SettingsScreen(themeNotifier: widget.themeNotifier),
      ),
    );
  }

  void _openDetails(ImageItem image, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          image: image,
          searchService: widget.searchService,
          imageList: _images,
          currentIndex: index,
        ),
      ),
    );
  }

  Future<void> _findSimilar(ImageItem image) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 16),
            Text('Finding similar images...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    try {
      await widget.searchService.searchByImageId(image.id);
      if (!mounted) return;
      _openSearch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to find similar images: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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

  void _openAlphaTest() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            AlphaTestScreen(searchService: widget.searchService),
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
          // Gallery Grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _images.isEmpty
                  ? Center(
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
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                            highlightColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.1),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: image.thumbnail != null
                                  ? Image.memory(
                                      image.thumbnail!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _buildPlaceholder(image, isDark),
                                    )
                                  : _buildPlaceholder(image, isDark),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
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
                      Text(
                        'Search...',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF666666)
                              : const Color(0xFF999999),
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
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
