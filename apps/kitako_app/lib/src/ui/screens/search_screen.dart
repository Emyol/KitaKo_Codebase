import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/image_search_service.dart';
import '../../models/search_models.dart';

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
  late SearchState _currentSearchState;

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
  }

  @override
  void dispose() {
    _searchSubscription?.cancel();
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
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
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
                  return Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
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
                              image.name,
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
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    // Default state - show logo
    return Center(
      child: Container(
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
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
