import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';

class DetailsScreen extends StatefulWidget {
  final ImageItem image;
  final ImageSearchService searchService;
  final List<ImageItem>? imageList;
  final int? currentIndex;

  /// How many routes to pop after Find Similar completes.
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

  Future<void> _findSimilar(ImageItem image) async {
    if (_findingSimilar) return;
    setState(() => _findingSimilar = true);
    try {
      try {
        await widget.searchService.searchByImageId(image.id);
      } catch (_) {
        final bytes = await File(image.path).readAsBytes();
        await widget.searchService.searchByImage(bytes.toList());
      }
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dark: black canvas, light top overlay, dark metadata panel
    // Light: light canvas, solid white top bar, light metadata panel
    final canvasBg    = isDark ? Colors.black : const Color(0xFFF4F7FB);
    final topBarBg    = isDark
        ? const Color(0x59000000)   // rgba(0,0,0,0.35)
        : Colors.white;
    final iconColor   = isDark ? Colors.white : const Color(0xFF0F172A);
    final metaBg      = isDark ? const Color(0xFF0E1116) : Colors.white;
    final metaBorder  = isDark
        ? const Color(0x0FFFFFFF)   // rgba(255,255,255,0.06)
        : const Color(0x0F000000);
    final blue        = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);

    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < _images.length - 1;
    final multiImage = _images.length > 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: canvasBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Top bar (back + filename + find-similar) ───────────────
              Container(
                color: topBarBg,
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back,
                          color: iconColor, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                    ),
                    Expanded(
                      child: Text(
                        _current.name,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Image area ─────────────────────────────────────────────
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: _images.length,
                      onPageChanged: (i) => setState(() => _currentIndex = i),
                      itemBuilder: (_, i) => _ImagePage(image: _images[i]),
                    ),

                    // Left button → newer/latest (lower index, slides in from left)
                    if (multiImage)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _NavButton(
                            icon: Icons.chevron_left,
                            enabled: hasPrev,
                            onTap: _goToPrev,
                          ),
                        ),
                      ),

                    // Right button → older/earliest (higher index, slides in from right)
                    if (multiImage)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _NavButton(
                            icon: Icons.chevron_right,
                            enabled: hasNext,
                            onTap: _goToNext,
                          ),
                        ),
                      ),

                    // Counter pill
                    if (multiImage)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0x990F172A),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_currentIndex + 1}  ·  ${_images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Metadata panel ─────────────────────────────────────────
              SafeArea(
                top: false,
                child: _MetadataPanel(
                  image: _current,
                  isDark: isDark,
                  metaBg: metaBg,
                  metaBorder: metaBorder,
                  blue: blue,
                  findingSimilar: _findingSimilar,
                  onFindSimilar: () => _findSimilar(_current),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            // rgba(15,23,42,0.55) — works on any image bg
            color: Color(0x8C0F172A),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
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
      minScale: 0.8,
      maxScale: 8.0,
      child: Center(
        child: Image.file(
          File(image.path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image,
                color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}

class _MetadataPanel extends StatelessWidget {
  final ImageItem image;
  final bool isDark;
  final Color metaBg;
  final Color metaBorder;
  final Color blue;
  final bool findingSimilar;
  final VoidCallback onFindSimilar;

  const _MetadataPanel({
    required this.image,
    required this.isDark,
    required this.metaBg,
    required this.metaBorder,
    required this.blue,
    required this.findingSimilar,
    required this.onFindSimilar,
  });

  @override
  Widget build(BuildContext context) {
    // Dark: white text at varying opacities (design spec)
    // Light: dark text at standard opacities
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final dateColor  = isDark
        ? const Color(0x9EFFFFFF)   // rgba(255,255,255,0.62)
        : const Color(0xFF64748B);
    final dateIcon   = isDark
        ? const Color(0x80FFFFFF)   // rgba(255,255,255,0.50)
        : const Color(0xFF94A3B8);
    final pathColor  = isDark
        ? const Color(0x6BFFFFFF)   // rgba(255,255,255,0.42)
        : const Color(0xFF94A3B8);

    return Container(
      decoration: BoxDecoration(
        color: metaBg,
        border: Border(top: BorderSide(color: metaBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.name,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (image.modifiedAt != null || image.createdAt != null) ...[
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: dateIcon),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(
                            image.modifiedAt ?? image.createdAt!),
                        style: TextStyle(
                            fontSize: 12, color: dateColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  [
                    image.path,
                    if (image.sizeBytes != null)
                      _formatSize(image.sizeBytes!),
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 11, color: pathColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Find Similar pill button
          FilledButton.icon(
            onPressed: findingSimilar ? null : onFindSimilar,
            icon: findingSimilar
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.image_search, size: 16),
            label: Text(findingSimilar ? 'Searching…' : 'Find Similar'),
            style: FilledButton.styleFrom(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
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
    final h = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
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
