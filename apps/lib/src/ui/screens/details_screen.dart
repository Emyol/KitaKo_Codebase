import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';

/// Displays full-screen details for a single [ImageItem].
///
/// Optionally accepts [imageList] and [currentIndex] to support
/// swipe-based navigation between results.
class DetailsScreen extends StatefulWidget {
  final ImageItem image;
  final ImageSearchService searchService;
  final List<ImageItem>? imageList;
  final int? currentIndex;

  /// How many routes to pop after Find Similar completes.
  ///
  /// Use 1 (default) when DetailsScreen is pushed directly from SearchScreen.
  /// Use 2 when pushed from ResultsScreen so we pop both DetailsScreen and
  /// ResultsScreen, landing back on SearchScreen where results update.
  final int popCount;

  const DetailsScreen({
    super.key,
    required this.image,
    required this.searchService,
    this.imageList,
    this.currentIndex,
    this.popCount = 1,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late PageController _pageController;
  late int _currentIndex;
  late List<ImageItem> _images;
  bool _findingSimilar = false;

  @override
  void initState() {
    super.initState();
    _images = widget.imageList ?? [widget.image];
    _currentIndex = widget.currentIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ImageItem get _current => _images[_currentIndex];

  void _goToPrev() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < _images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : null,
        iconTheme: IconThemeData(color: fgColor),
        title: Text(
          _current.name,
          style: TextStyle(color: fgColor, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_findingSimilar)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.image_search, color: fgColor),
              tooltip: 'Find similar',
              onPressed: () => _findSimilar(_current),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: _images.length,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemBuilder: (context, i) => _ImagePage(image: _images[i]),
                ),
                // Prev button
                if (_images.length > 1)
                  Positioned(
                    left: 4,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavButton(
                        icon: Icons.chevron_left,
                        enabled: _currentIndex > 0,
                        onTap: _goToPrev,
                      ),
                    ),
                  ),
                // Next button
                if (_images.length > 1)
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavButton(
                        icon: Icons.chevron_right,
                        enabled: _currentIndex < _images.length - 1,
                        onTap: _goToNext,
                      ),
                    ),
                  ),
                // Page indicator
                if (_images.length > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${_images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // SafeArea keeps the panel above the home bar / navigation bar.
          SafeArea(
            top: false,
            child: _MetadataPanel(
              image: _current,
              isDark: isDark,
              findingSimilar: _findingSimilar,
              onFindSimilar: () => _findSimilar(_current),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _findSimilar(ImageItem image) async {
    if (_findingSimilar) return;
    setState(() => _findingSimilar = true);
    try {
      // Primary path: look up image by ID in the loader cache.
      // Fallback: read file bytes directly from disk (works for any ImageItem
      // that has a valid path, even if it wasn't registered in the test cache).
      try {
        await widget.searchService.searchByImageId(image.id);
      } catch (_) {
        final bytes = await File(image.path).readAsBytes();
        await widget.searchService.searchByImage(bytes.toList());
      }
      if (mounted) {
        // Pop enough levels to reach SearchScreen, which listens to the stream
        // and will display the new results automatically.
        int popsLeft = widget.popCount;
        while (popsLeft > 0 && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          popsLeft--;
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not find similar images: $e')),
      );
    } finally {
      if (mounted) setState(() => _findingSimilar = false);
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _ImagePage extends StatelessWidget {
  final ImageItem image;
  const _ImagePage({required this.image});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: Image.file(
          File(image.path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}

class _MetadataPanel extends StatelessWidget {
  final ImageItem image;
  final bool isDark;
  final bool findingSimilar;
  final VoidCallback onFindSimilar;

  const _MetadataPanel({
    required this.image,
    required this.isDark,
    required this.findingSimilar,
    required this.onFindSimilar,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final mainColor = isDark ? Colors.white : Colors.black87;

    return Container(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── File info ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.name,
                  style: TextStyle(
                    color: mainColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                // Timestamp row
                if (image.modifiedAt != null || image.createdAt != null) ...[
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: dimColor),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(image.modifiedAt ?? image.createdAt!),
                        style: TextStyle(fontSize: 12, color: dimColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  image.path,
                  style: TextStyle(color: subColor, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (image.sizeBytes != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    _formatSize(image.sizeBytes!),
                    style: TextStyle(fontSize: 11, color: dimColor),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ── Find Similar button ──
          OutlinedButton.icon(
            onPressed: findingSimilar ? null : onFindSimilar,
            icon: findingSimilar
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_search, size: 18),
            label: Text(findingSimilar ? 'Searching…' : 'Find Similar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white70 : Colors.black87,
              side: BorderSide(
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m $ampm';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
