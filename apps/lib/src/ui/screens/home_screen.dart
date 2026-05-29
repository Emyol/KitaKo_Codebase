import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'details_screen.dart';
import 'results_screen.dart';
import '../theme/theme_notifier.dart';
import '../../services/image_search_service.dart';
import '../../services/search_history_service.dart';
import '../../state/settings_controller.dart';
import '../../models/search_models.dart';

import '../theme/palette.dart';
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
  StreamSubscription<IndexingProgress>? _indexingSubscription;
  DateTime? _lastBackPressed;
  IndexingProgress _indexingProgress =
      const IndexingProgress(phase: IndexingPhase.idle, message: '');
  bool _isLoading = true;
  bool _findingSimilar = false;
  final SearchHistoryService _historyService = SearchHistoryService();

  // -- Gallery column count (pinch-adjustable, persisted) ---------------------
  int _columnCount = 3;
  int _columnCountAtGestureStart = 3;
  // Raw pointer tracking — bypasses gesture arena so pinch works on scrollables
  final Map<int, Offset> _activePointers = {};
  double _pinchStartDist = 0;

  static const _kColKey = 'gallery_columns';
  static const _kColMin = 2;
  static const _kColMax = 6;

  Future<void> _loadColumnCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _columnCount = (prefs.getInt(_kColKey) ?? 3)
          .clamp(_kColMin, _kColMax));
    }
  }

  Future<void> _saveColumnCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kColKey, count);
  }

  @override
  void initState() {
    super.initState();
    _loadImages();
    _listenForImageUpdates();
    _listenForIndexingProgress();
    _loadColumnCount();
    _historyService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _imagesSubscription?.cancel();
    _indexingSubscription?.cancel();
    super.dispose();
  }

  void _listenForIndexingProgress() {
    _indexingProgress = widget.searchService.lastProgress;
    _indexingSubscription =
        widget.searchService.indexingProgressStream.listen((p) {
      if (mounted) setState(() => _indexingProgress = p);
    });
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
            SearchScreen(
              searchService: widget.searchService,
              historyService: _historyService,
              onSettingsTap: _openSettings,
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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => SettingsScreen(
              themeNotifier: widget.themeNotifier,
              searchService: widget.searchService,
              settingsController: widget.settingsController,
            ),
          ),
        )
        .then((_) => _loadColumnCount());
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
    if (_findingSimilar) return;
    setState(() => _findingSimilar = true);
    try {
      await widget.searchService.searchByImageId(image.id);
      if (!mounted) return;
      final state = widget.searchService.currentState;
      final result = state.result;
      if (result == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            searchResult: result,
            searchService: widget.searchService,
            queryImage: state.queryImage,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to find similar images: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _findingSimilar = false);
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
                color: P.textFaint(isDark),
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

  /// Builds the main content area: gallery (or skeleton on first load).
  ///
  /// Find-similar results are no longer rendered inline here — they push a
  /// fresh [ResultsScreen] route so text-search and image-similarity share
  /// one results surface.
  Widget _buildContent(bool isDark) {
    if (_findingSimilar) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
            const SizedBox(height: 12),
            Text(
              'Finding similar images…',
              style: TextStyle(
                color: P.textMore(isDark),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }


    if (_images.isEmpty) {
      if (_isLoading) {
        // Skeleton grid — shows immediately while first progressive batch loads.
        return _SkeletonGallery(columnCount: _columnCount, isDark: isDark);
      }
      return Center(
        child: Text(
          'No images found',
          style: TextStyle(
            color: P.textDim(isDark),
            fontSize: 16,
          ),
        ),
      );
    }

    // Date-grouped gallery.
    // Listener bypasses the gesture arena entirely, so pinch is always detected
    // even though CustomScrollView owns the drag recognizer for scrolling.
    // When 2 pointers are active, NeverScrollableScrollPhysics prevents the
    // scroll view from fighting the pinch.
    final groups = _groupByDate(_images);
    final isPinching = _activePointers.length >= 2;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _activePointers[e.pointer] = e.position;
        if (_activePointers.length == 2) {
          final pts = _activePointers.values.toList();
          _pinchStartDist = (pts[0] - pts[1]).distance;
          _columnCountAtGestureStart = _columnCount;
          setState(() {}); // rebuild to switch to NeverScrollableScrollPhysics
        }
      },
      onPointerMove: (e) {
        _activePointers[e.pointer] = e.position;
        if (_activePointers.length >= 2 && _pinchStartDist > 0) {
          final pts = _activePointers.values.toList();
          final dist = (pts[0] - pts[1]).distance;
          final scale = dist / _pinchStartDist;
          final newCount = (_columnCountAtGestureStart / scale)
              .round()
              .clamp(_kColMin, _kColMax);
          if (newCount != _columnCount) {
            setState(() => _columnCount = newCount);
          }
        }
      },
      onPointerUp: (e) {
        _activePointers.remove(e.pointer);
        if (_activePointers.length < 2) {
          _saveColumnCount(_columnCount);
          setState(() {}); // restore normal scroll physics
        }
      },
      onPointerCancel: (e) {
        _activePointers.remove(e.pointer);
        if (_activePointers.length < 2) {
          setState(() {});
        }
      },
      child: CustomScrollView(
        physics: isPinching ? const NeverScrollableScrollPhysics() : null,
        slivers: [
          for (final group in groups) ...[
            SliverToBoxAdapter(
                child: _buildSectionHead(group.$1, group.$2.length, isDark)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columnCount,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildGalleryTile(group.$2[index], isDark),
                  childCount: group.$2.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
      ),
    );
  }

  // Returns [(label, images)] groups sorted newest-first within each group.
  // Sections: Today → This week → This month → Month YYYY (per month) → Earlier
  List<(String, List<ImageItem>)> _groupByDate(List<ImageItem> images) {
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final thisWeekStart = todayStart.subtract(const Duration(days: 6));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    final today = <ImageItem>[];
    final thisWeek = <ImageItem>[];
    final thisMonth = <ImageItem>[];
    final byMonth = <(int, int), List<ImageItem>>{}; // (year, month) → images
    final nullDates = <ImageItem>[];

    for (final img in images) {
      final d = img.createdAt ?? img.modifiedAt;
      if (d == null) {
        nullDates.add(img);
      } else if (!d.isBefore(todayStart)) {
        today.add(img);
      } else if (!d.isBefore(thisWeekStart)) {
        thisWeek.add(img);
      } else if (!d.isBefore(thisMonthStart)) {
        thisMonth.add(img);
      } else {
        (byMonth[(d.year, d.month)] ??= []).add(img);
      }
    }

    // Sort newest-first within every group
    int newestFirst(ImageItem a, ImageItem b) {
      final da = a.createdAt ?? a.modifiedAt;
      final db = b.createdAt ?? b.modifiedAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    }

    today.sort(newestFirst);
    thisWeek.sort(newestFirst);
    thisMonth.sort(newestFirst);
    for (final list in byMonth.values) {
      list.sort(newestFirst);
    }

    final out = <(String, List<ImageItem>)>[];
    if (today.isNotEmpty) out.add(('Today', today));
    if (thisWeek.isNotEmpty) out.add(('This week', thisWeek));
    if (thisMonth.isNotEmpty) out.add(('This month', thisMonth));

    // Month groups sorted newest-first (year desc then month desc)
    final sortedMonths = byMonth.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : b.$2 - a.$2);
    for (final key in sortedMonths) {
      out.add(('${monthNames[key.$2 - 1]} ${key.$1}', byMonth[key]!));
    }

    if (nullDates.isNotEmpty) out.add(('Earlier', nullDates));

    // Fallback: all dates null → single Gallery group
    if (out.isEmpty) return [('Gallery', nullDates)];
    return out;
  }

  Widget _buildSectionHead(String label, int count, bool isDark) {
    final blue = P.accent(isDark);
    final textColor = P.text(isDark);
    final faint = P.textFaint(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Row(
        children: [
          Container(width: 3, height: 14,
              decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(label.toUpperCase(),
              style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(width: 8),
          Text('$count',
              style: TextStyle(color: faint, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildGalleryTile(ImageItem image, bool isDark) {
    // Find index for _openDetails navigation
    final index = _images.indexOf(image);
    return Material(
      color: P.surfaceAlt(isDark),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openDetails(image, index < 0 ? 0 : index),
        onLongPress: () => _findSimilar(image),
        borderRadius: BorderRadius.circular(14),
        splashColor: isDark ? Colors.white12 : Colors.black12,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(image.path),
            fit: BoxFit.cover,
            cacheWidth: 256,
            errorBuilder: (_, _, _) => _buildPlaceholder(image, isDark),
          ),
        ),
      ),
    );
  }


/// Compact banner shown above the search bar while background indexing runs.
  /// Hidden when indexing is idle, done, or errored.
  Widget _buildIndexingBanner(bool isDark) {
    final phase = _indexingProgress.phase;
    final isActive = phase == IndexingPhase.embedding ||
        phase == IndexingPhase.embeddingPartialFailure ||
        phase == IndexingPhase.loadingGallery ||
        phase == IndexingPhase.restoringCache;
    if (!isActive) return const SizedBox.shrink();

    final fraction = _indexingProgress.fraction;
    final isPartialFailure = phase == IndexingPhase.embeddingPartialFailure;
    final bannerColor = isPartialFailure
        ? (isDark ? const Color(0xFF3A2800) : const Color(0xFFFFF3E0))
        : (isDark ? const Color(0xFF1A2A3A) : const Color(0xFFE8F4FD));
    final textColor = isPartialFailure
        ? (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100))
        : (isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0));
    final barColor = isPartialFailure
        ? const Color(0xFFFFB74D)
        : const Color(0xFF3B82F6);

    return Container(
      color: bannerColor,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _indexingProgress.message.isEmpty
                      ? 'Indexing photos…'
                      : _indexingProgress.message,
                  style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isPartialFailure) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => widget.searchService
                      .continueAfterEmbeddingFailure(retry: false),
                  child: Text('Skip',
                      style: TextStyle(
                          fontSize: 11,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline)),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => widget.searchService
                      .continueAfterEmbeddingFailure(retry: true),
                  child: Text('Retry',
                      style: TextStyle(
                          fontSize: 11,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 2,
                backgroundColor: barColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final titleColor = P.title(isDark);
    final hairline = P.hairline(isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        final now = DateTime.now();
        if (_lastBackPressed != null &&
            now.difference(_lastBackPressed!) < const Duration(seconds: 2)) {
          // Second tap within 2 s — exit
          SystemNavigator.pop();
          return;
        }
        _lastBackPressed = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('KitaKo',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                )),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: P.accentSoft(isDark),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'BETA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: P.chipText(isDark),
                ),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: hairline,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: titleColor, size: 24),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey(
                    _images.isEmpty && _isLoading ? 'skeleton' : 'gallery'),
                child: _buildContent(isDark),
              ),
            ),
          ),
          _buildIndexingBanner(isDark),
          // Search Bar at Bottom — floating pill
          SafeArea(
            child: GestureDetector(
              onTap: _openSearch,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: P.surface(isDark),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: P.border(isDark),
                    ),
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.30),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: const Color(0xFF0F2A4A)
                                  .withValues(alpha: 0.10),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: const Color(0xFF0F2A4A)
                                  .withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      // Blue circle badge with search icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: P.accent(isDark),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.search,
                            color: P.onAccent(isDark), size: 18),
                      ),
                      const SizedBox(width: 10),
                      // Recent query or placeholder
                      Expanded(
                        child: _historyService.queries.isNotEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'RECENT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.6,
                                      color: P.accent(isDark),
                                    ),
                                  ),
                                  Text(
                                    _historyService.queries.first,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: P.text(isDark),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              )
                            : Text(
                                'Search photos in Taglish…',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                      ),
                      // Photo chip
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding:
                            const EdgeInsets.fromLTRB(8, 6, 10, 6),
                        decoration: BoxDecoration(
                          color: P.chipBg(isDark),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_outlined,
                              size: 14,
                              color: P.chipText(isDark),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Photo',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: P.chipText(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ), // Scaffold
    ); // PopScope
  }
}

// -- Skeleton gallery -----------------------------------------------------------
// Shown immediately on launch while the first progressive image batch loads.
// One AnimationController drives all tiles so there is no per-tile overhead.

class _SkeletonGallery extends StatefulWidget {
  final int columnCount;
  final bool isDark;

  const _SkeletonGallery({required this.columnCount, required this.isDark});

  @override
  State<_SkeletonGallery> createState() => _SkeletonGalleryState();
}

class _SkeletonGalleryState extends State<_SkeletonGallery>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    // Enough tiles to fill a typical screen height (5 rows)
    final tileCount = widget.columnCount * 5;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final baseColor = Color.lerp(
          isDark ? const Color(0xFF161B22) : const Color(0xFFE2EAF4),
          isDark ? const Color(0xFF222A36) : const Color(0xFFF0F4FA),
          _anim.value,
        )!;
        final labelColor = Color.lerp(
          isDark ? const Color(0xFF1F2733) : const Color(0xFFD8E2EF),
          isDark ? const Color(0xFF2A3244) : const Color(0xFFEAEFF7),
          _anim.value,
        )!;

        return CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            // Fake section head
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: labelColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 56,
                      height: 12,
                      decoration: BoxDecoration(
                        color: labelColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 10,
                      decoration: BoxDecoration(
                        color: labelColor.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Shimmer tile grid
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: widget.columnCount,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Container(
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  childCount: tileCount,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
