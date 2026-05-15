import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/image_search_service.dart';
import '../../services/search_history_service.dart';
import '../../models/search_models.dart';
import 'results_screen.dart';

class SearchScreen extends StatefulWidget {
  final ImageSearchService searchService;
  final SearchHistoryService historyService;
  final VoidCallback? onSettingsTap;

  const SearchScreen({
    super.key,
    required this.searchService,
    required this.historyService,
    this.onSettingsTap,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  SearchHistoryService get _historyService => widget.historyService;
  StreamSubscription<SearchState>? _searchSubscription;
  late SearchState _currentSearchState;
  bool _hasNavigated = false;


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
    _searchSubscription = widget.searchService.searchStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _currentSearchState = state);
      // Auto-navigate to ResultsScreen on any search success
      if (state.status == SearchStatus.success &&
          state.result != null &&
          !_hasNavigated) {
        _hasNavigated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToResults().then((_) {
              if (mounted) setState(() => _hasNavigated = false);
            });
          }
        });
      }
      if (state.status == SearchStatus.searching) {
        _hasNavigated = false;
      }
    });

  }

  void _onSearchTextChanged() => setState(() {});

  @override
  void dispose() {
    _searchSubscription?.cancel();
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
            onPressed: widget.onSettingsTap,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Results or Empty State
          Expanded(child: _buildSearchContent()),
          // Active search bar — pill with blue ring + Photo chip + external send button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Row(
                children: [
                  // Pill
                  Expanded(
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B22) : Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)).withValues(alpha: 0.35),
                            blurRadius: 0, spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search, size: 20,
                              color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search photos in Taglish…',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
                                  fontSize: 15,
                                ),
                              ),
                              onSubmitted: (_) => _performSearch(),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                widget.searchService.clearSearch();
                              },
                              child: Container(
                                width: 26, height: 26,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1A2030) : const Color(0xFFEEF3FA),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close, size: 14,
                                    color: isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B)),
                              ),
                            ),
                          // Photo chip inside pill
                          Container(
                            margin: const EdgeInsets.only(right: 8, left: 6),
                            padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x243B82F6) : const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _pickImageForSearch,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.image_outlined, size: 14,
                                          color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8)),
                                      const SizedBox(width: 4),
                                      Text('Photo',
                                          style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w600,
                                            color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                                          )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Send button — outside pill, solid circle
                  GestureDetector(
                    onTap: _performSearch,
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 22),
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
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
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
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.8),
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
            // 140×140 illustrated state
            SizedBox(
              width: 140, height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dashed outer ring
                  Container(
                    width: 124, height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Inner card
                  Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161B22) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)).withValues(alpha: 0.18),
                          blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(Icons.search, size: 44,
                          color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)),
                    ),
                  ),
                  // Blue circle with X at bottom-right
                  Positioned(
                    bottom: 14, right: 14,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('No results found',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
            const SizedBox(height: 6),
            Text('Try one of these instead',
                style: TextStyle(color: isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B), fontSize: 14)),
            const SizedBox(height: 20),
            // Suggestion chips
            if (_currentSearchState.suggestions?.isNotEmpty == true)
              Wrap(
                spacing: 8, runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _currentSearchState.suggestions!.map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B22) : Colors.white,
                    border: Border.all(color: isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search, size: 13, color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Text(s, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                )).toList(),
              )
            else
              Wrap(
                spacing: 8, runSpacing: 8,
                alignment: WrapAlignment.center,
                children: ['red sunset', 'beach photos', 'kasama ang pamilya', 'pagkain'].map((s) =>
                  GestureDetector(
                    onTap: () {
                      _searchController.text = s;
                      _performSearch();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B22) : Colors.white,
                        border: Border.all(color: isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 13, color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB)),
                          const SizedBox(width: 6),
                          Text(s, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ).toList(),
              ),
          ],
        ),
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

    // Idle with no history — show suggested prompts
    return _buildIdlePrompt(isDark, textColor);
  }

  Widget _buildIdlePrompt(bool isDark, Color textColor) {
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final surface = isDark ? const Color(0xFF161B22) : Colors.white;
    final border = isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0);
    final textMore = isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B);

    const suggested = [
      'sunset sa beach',
      'kumakain sa mesa',
      'pamilya sa bahay',
      'tao sa parke',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabelRow('Suggested', isDark),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggested.map((s) => GestureDetector(
              onTap: () => _runHistoryQuery(s),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 13, color: blue),
                    const SizedBox(width: 6),
                    Text(s,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Type a query or pick an image to search',
              style: TextStyle(color: textMore, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(
    bool isDark,
    Color textColor,
    List<String> queries, {
    required bool showClearAll,
  }) {
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final blueSoft = isDark ? const Color(0x2E3B82F6) : const Color(0xFFDBEAFE);
    final surface = isDark ? const Color(0xFF161B22) : Colors.white;
    final border = isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0);
    final hairline = isDark ? const Color(0x1F60A5FA) : const Color(0x192563EB);
    final textFaint = isDark ? const Color(0x61FFFFFF) : const Color(0xFF94A3B8);
    final chipBg = isDark ? const Color(0x243B82F6) : const Color(0xFFDBEAFE);
    final chipText = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);

    // Suggested queries (preset examples shown above history)
    const suggested = ['sunset sa beach', 'kumakain sa mesa', 'pamilya sa bahay'];

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suggested chips
          _buildSectionLabel('Suggested', isDark),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggested.map((s) => GestureDetector(
              onTap: () => _runHistoryQuery(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: surface,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 13, color: blue),
                    const SizedBox(width: 6),
                    Text(s, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )).toList(),
          ),

          // Recent section header
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
            child: Row(
              children: [
                _sectionLabelRow('Recent', isDark),
                const Spacer(),
                if (showClearAll)
                  GestureDetector(
                    onTap: () async {
                      await _historyService.clearAll();
                      setState(() {});
                    },
                    child: Text('Clear all',
                        style: TextStyle(fontSize: 13, color: blue, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
          ),

          // History card
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                for (int i = 0; i < queries.length; i++) ...[
                  if (i > 0)
                    Container(height: 1, color: hairline, margin: const EdgeInsets.symmetric(horizontal: 14)),
                  _buildHistoryItem(queries[i], i, blue, blueSoft, chipBg, chipText, textColor, textFaint, isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    String query,
    int index,
    Color blue,
    Color blueSoft,
    Color chipBg,
    Color chipText,
    Color textColor,
    Color textFaint,
    bool isDark,
  ) {
    return InkWell(
      onTap: () => _runHistoryQuery(query),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Blue circle with history icon
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: blueSoft, shape: BoxShape.circle),
              child: Icon(Icons.history, size: 14, color: blue),
            ),
            const SizedBox(width: 12),
            // Query text
            Expanded(
              child: Text(query,
                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            // Arrow icon
            Icon(Icons.north_east, size: 16, color: textFaint),
            // Delete button
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () async {
                await _historyService.removeQuery(query);
                setState(() {});
              },
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222A36) : const Color(0xFFE2EAF4),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, size: 14, color: textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: _sectionLabelRow(label, isDark),
    );
  }

  Widget _sectionLabelRow(String label, bool isDark) {
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 3, height: 14,
            decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      ],
    );
  }

  /// Navigate to the full results screen
  Future<void> _navigateToResults() async {
    final result = _currentSearchState.result;
    if (result == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          searchResult: result,
          searchService: widget.searchService,
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
        color: isDark ? const Color(0xFF1A2030) : const Color(0xFFE2EAF4),
        child: Icon(
          Icons.image_outlined,
          color: isDark ? Colors.white30 : Colors.black26,
        ),
      ),
    );
  }
}
