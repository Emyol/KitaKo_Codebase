import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../theme/theme_notifier.dart';
import '../../services/image_search_service.dart';
import '../../services/image_loader_service.dart';
import '../../models/search_models.dart';

class HomeScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService searchService;
  final ImageLoaderService? imageLoaderService;

  const HomeScreen({
    super.key,
    required this.themeNotifier,
    required this.searchService,
    this.imageLoaderService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ImageItem> _images = [];
  final Map<String, Uint8List> _thumbnailCache = {};
  bool _loadingThumbnails = false;
  ImageLoaderService? _imageLoader;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final images = widget.searchService.getAllImages();
    if (mounted) {
      setState(() {
        _images = images;
      });
      // Load thumbnails for display
      _loadThumbnails();
    }
  }

  Future<void> _loadThumbnails() async {
    if (_loadingThumbnails || _images.isEmpty) return;
    _loadingThumbnails = true;

    // Get the image loader service
    _imageLoader = widget.imageLoaderService ?? ImageLoaderService();
    if (widget.imageLoaderService == null) {
      await _imageLoader!.initialize();
      // Load images if not already loaded
      await _imageLoader!.loadDeviceImages();
    }

    // Load thumbnails in batches for visible images
    final batchSize = 10;
    for (var i = 0; i < _images.length; i += batchSize) {
      if (!mounted) break;

      final batch = _images.skip(i).take(batchSize).toList();
      final thumbnails = await _imageLoader!.loadThumbnailBatch(batch, batchSize: 5);

      if (mounted) {
        setState(() {
          _thumbnailCache.addAll(thumbnails);
        });
      }
    }

    _loadingThumbnails = false;
  }

  Widget _buildPlaceholder(bool isDark, String name) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            color: isDark
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
            size: 40,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              name,
              style: TextStyle(
                color: isDark
                    ? Colors.white.withOpacity(0.5)
                    : Colors.black.withOpacity(0.5),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
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
                      child: Text(
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
                        final thumbnail = _thumbnailCache[image.id];

                        return Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFE0E0E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: thumbnail != null
                              ? Image.memory(
                                  thumbnail,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildPlaceholder(isDark, image.name),
                                )
                              : _buildPlaceholder(isDark, image.name),
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
