import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import '../../services/camera_capture_service.dart';
import '../../services/image_search_service.dart';
import '../../services/search_history_service.dart';
import '../../models/search_models.dart';
import 'results_screen.dart';

import '../theme/palette.dart';
const _kSuggestedQueries = <String>[
  'sunset sa beach',
  'kumakain sa labas',
  'selfie namin sa park',
  'aso ko sa bahay',
  'birthday party ng bata',
  'lakad sa mall',
  'pamilya sa hapag',
  'gabi na sa kalsada',
  'mga bulaklak sa garden',
  'swimming sa pool',
  'road trip namin',
  'cat napping sa sofa',
  'view sa bundok',
  'kainan sa restaurant',
  'group photo ng barkada',
  'ulan sa labas',
  'street food sa palengke',
  'cooking sa kusina',
  'baby na tulog',
  'sports sa field',
  'building sa city',
  'coffee sa cafe',
  'beach na may palm trees',
  'graduation ceremony',
  'christmas tree sa bahay',
  'fireworks sa gabi',
  'market na maraming tao',
  'painting sa wall',
  'boat sa dagat',
  'hiking trail sa gubat',
  'wedding na may flowers',
  'playground ng mga bata',
  'train station platform',
  'rainy day sa window',
  'pet na naglalaro',
  'desk na may laptop',
  'car sa parking lot',
  'plaza na may fountain',
  'farm na may hayop',
  'museum na may paintings',
  'jeepney sa kalsada',
  'skyline ng city sa gabi',
  'old church sa plaza',
  'mga prutas sa basket',
  'tricycle sa kanto',
  'concert sa stage',
  'rice field na green',
  'fish sa aquarium',
  'shoes sa shoe rack',
  'simbahan sa umaga',
];

final _suggestRng = Random();

List<String> _pickSuggestions(int count) {
  final pool = List<String>.of(_kSuggestedQueries);
  pool.shuffle(_suggestRng);
  return pool.take(count).toList();
}

enum _SearchRelevance {
  off(0.0, 'Off'),
  low(0.20, 'Low'),
  medium(0.45, 'Medium'),
  high(0.70, 'High');

  final double threshold;
  final String label;
  const _SearchRelevance(this.threshold, this.label);
}

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
  // Set true when this screen kicks off a search; only then will the listener
  // auto-push ResultsScreen. Find-similar searches initiated from other
  // screens (home long-press, details) push their own ResultsScreen directly,
  // so search_screen must stay quiet to avoid a duplicate navigation.
  bool _initiatedSearch = false;
  List<String> _idleSuggestions = _pickSuggestions(5);
  List<String> _historySuggestions = _pickSuggestions(5);
  List<String> _noResultsSuggestions = _pickSuggestions(5);

  // -- Metadata filter state --------------------------------------------------
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  _SearchRelevance _filterRelevance = _SearchRelevance.off;
  bool get _hasActiveFilters =>
      _filterStartDate != null ||
      _filterEndDate != null ||
      _filterRelevance != _SearchRelevance.off;

  String get _filterSummary {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final parts = <String>[];
    if (_filterStartDate != null && _filterEndDate != null) {
      parts.add('${fmt(_filterStartDate!)} — ${fmt(_filterEndDate!)}');
    } else if (_filterStartDate != null) {
      parts.add('From ${fmt(_filterStartDate!)}');
    } else if (_filterEndDate != null) {
      parts.add('Until ${fmt(_filterEndDate!)}');
    }
    if (_filterRelevance != _SearchRelevance.off) {
      parts.add('Relevance: ${_filterRelevance.label}');
    }
    return parts.join(' · ');
  }


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
      // Auto-navigate to ResultsScreen only for searches initiated by this
      // screen — find-similar from home/details pushes its own ResultsScreen.
      if (state.status == SearchStatus.success &&
          state.result != null &&
          _initiatedSearch &&
          !_hasNavigated) {
        _hasNavigated = true;
        _initiatedSearch = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToResults().then((_) {
              if (mounted) setState(() => _hasNavigated = false);
            });
          }
        });
      }
    });

  }

  void _onSearchTextChanged() => setState(() {});

  void _reshuffleSuggestions() {
    _idleSuggestions = _pickSuggestions(5);
    _historySuggestions = _pickSuggestions(5);
    _noResultsSuggestions = _pickSuggestions(5);
  }

  @override
  void deactivate() {
    _reshuffleSuggestions();
    super.deactivate();
  }

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
    _initiatedSearch = true;
    widget.searchService.searchImages(query);
  }

  void _openFilterSheet() {
    var start = _filterStartDate;
    var end = _filterEndDate;
    var relevance = _filterRelevance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bg = P.surface(isDark);
            final divColor = isDark ? Colors.white12 : Colors.black12;
            final labelStyle = TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: P.textDim(isDark),
            );
            final blue = P.accent(isDark);

            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.tune, size: 20, color: blue),
                      const SizedBox(width: 8),
                      Text('Search Filters',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: P.text(isDark))),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setSheet(() {
                            start = null;
                            end = null;
                            relevance = _SearchRelevance.off;
                          });
                        },
                        child: Text('Reset',
                            style: TextStyle(color: blue)),
                      ),
                    ],
                  ),
                  Divider(color: divColor),

                  // -- Date Range --
                  Text('Date Range', style: labelStyle),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DateChip(
                          label: 'From',
                          date: start,
                          isDark: isDark,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: start ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (d != null) setSheet(() => start = d);
                          },
                          onClear: start != null
                              ? () => setSheet(() => start = null)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateChip(
                          label: 'To',
                          date: end,
                          isDark: isDark,
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: end ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (d != null) setSheet(() => end = d);
                          },
                          onClear: end != null
                              ? () => setSheet(() => end = null)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: divColor),

                  // -- Relevance --
                  Text('Relevance', style: labelStyle),
                  const SizedBox(height: 4),
                  Text(
                    relevance == _SearchRelevance.off
                        ? 'Show all results regardless of score'
                        : 'Only show results above ${(relevance.threshold * 100).round()}% match',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _SearchRelevance.values.map((r) {
                      final selected = relevance == r;
                      return ChoiceChip(
                        label: Text(r.label),
                        selected: selected,
                        onSelected: (_) => setSheet(() => relevance = r),
                        selectedColor: blue,
                        labelStyle: TextStyle(
                          color: selected
                              ? P.onAccent(isDark)
                              : (P.textDim(isDark)),
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // -- Apply --
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          _filterStartDate = start;
                          _filterEndDate = end;
                          _filterRelevance = relevance;
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Apply Filters',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.tune,
                  color: Theme.of(context).appBarTheme.titleTextStyle?.color,
                  size: 24,
                ),
                onPressed: _openFilterSheet,
              ),
              if (_hasActiveFilters)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
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
          // Active filter indicator
          if (_hasActiveFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark
                  ? P.accent(isDark).withValues(alpha: 0.10)
                  : P.accent(isDark).withValues(alpha: 0.06),
              child: Row(
                children: [
                  Icon(Icons.filter_alt, size: 14,
                      color: P.accent(isDark)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _filterSummary,
                      style: TextStyle(
                        fontSize: 12,
                        color: P.chipText(isDark),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _filterStartDate = null;
                      _filterEndDate = null;
                      _filterRelevance = _SearchRelevance.off;
                    }),
                    child: Icon(Icons.close, size: 16,
                        color: P.accent(isDark)),
                  ),
                ],
              ),
            ),
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
                        color: P.surface(isDark),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: P.accent(isDark),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (P.accent(isDark)).withValues(alpha: 0.35),
                            blurRadius: 0, spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search, size: 20,
                              color: P.accent(isDark)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              style: TextStyle(
                                color: P.text(isDark),
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
                                    color: P.textMore(isDark)),
                              ),
                            ),
                          // Photo chip inside pill
                          Container(
                            margin: const EdgeInsets.only(right: 8, left: 6),
                            padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                            decoration: BoxDecoration(
                              color: P.chipBg(isDark),
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
                                          color: P.chipText(isDark)),
                                      const SizedBox(width: 4),
                                      Text('Photo',
                                          style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w600,
                                            color: P.chipText(isDark),
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
                        color: P.accent(isDark),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.send, color: P.onAccent(isDark), size: 22),
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
    final textColor = P.text(isDark);

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
                    color: P.accent(isDark).withValues(alpha: 0.8),
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
      final blue = P.accent(isDark);
      final blueSoft = P.accentSoft(isDark);
      final surface = P.surface(isDark);
      final border = P.border(isDark);
      final suggestions = _currentSearchState.suggestions?.isNotEmpty == true
          ? _currentSearchState.suggestions!
          : _noResultsSuggestions;

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Soft rounded icon
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: blueSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.search_off_rounded, size: 40, color: blue),
              ),
              const SizedBox(height: 20),
              Text('No results found',
                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              const SizedBox(height: 6),
              Text('Try one of these instead',
                  style: TextStyle(color: P.textMore(isDark), fontSize: 14)),
              const SizedBox(height: 16),
              // Clickable suggestion chips — single-line horizontal scroll
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = suggestions[i];
                    return GestureDetector(
                      onTap: () {
                        _searchController.text = s;
                        _performSearch();
                      },
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
                            Icon(Icons.search, size: 13, color: blue),
                            const SizedBox(width: 6),
                            Text(s, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
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
    final blue = P.accent(isDark);
    final surface = P.surface(isDark);
    final border = P.border(isDark);
    final textMore = P.textMore(isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabelRow('Suggested', isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _idleSuggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _idleSuggestions[i];
                return GestureDetector(
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
                );
              },
            ),
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
    final blue = P.accent(isDark);
    final blueSoft = P.accentSoft(isDark);
    final surface = P.surface(isDark);
    final border = P.border(isDark);
    final hairline = P.hairline(isDark);
    final textFaint = P.textFaint(isDark);
    final chipBg = P.chipBg(isDark);
    final chipText = P.chipText(isDark);

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suggested chips
          _buildSectionLabel('Suggested', isDark),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _historySuggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _historySuggestions[i];
                return GestureDetector(
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
                );
              },
            ),
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
    final blue = P.accent(isDark);
    final textColor = P.text(isDark);
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

    final filtered = _applyFilters(result);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          searchResult: filtered,
          searchService: widget.searchService,
          queryImage: _currentSearchState.queryImage,
        ),
      ),
    );
  }

  SearchResult _applyFilters(SearchResult result) {
    if (!_hasActiveFilters) return result;

    final endOfDay = _filterEndDate != null
        ? DateTime(_filterEndDate!.year, _filterEndDate!.month,
            _filterEndDate!.day, 23, 59, 59)
        : null;

    final hasScores = result.scores != null && result.scores!.isNotEmpty;
    final topScore = hasScores ? result.scores!.first : 1.0;
    final minScore = _filterRelevance != _SearchRelevance.off
        ? topScore * _filterRelevance.threshold
        : null;

    final images = <ImageItem>[];
    final scores = <double>[];

    for (int i = 0; i < result.images.length; i++) {
      final img = result.images[i];
      if (_filterStartDate != null && img.createdAt != null) {
        if (img.createdAt!.isBefore(_filterStartDate!)) continue;
      }
      if (endOfDay != null && img.createdAt != null) {
        if (img.createdAt!.isAfter(endOfDay)) continue;
      }
      if (minScore != null && hasScores) {
        final score = result.scoreAt(i) ?? 0.0;
        if (score < minScore) continue;
      }
      images.add(img);
      if (result.scores != null && i < result.scores!.length) {
        scores.add(result.scores![i]);
      }
    }

    return SearchResult(
      images: images,
      scores: result.scores != null ? scores : null,
      query: result.query,
      embeddingTimeMs: result.embeddingTimeMs,
      searchTimeMs: result.searchTimeMs,
      totalScanned: result.totalScanned,
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
              subtitle: const Text('Saves to gallery and indexes for search'),
              onTap: () {
                Navigator.pop(context);
                _captureAndSearch();
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
      _initiatedSearch = true;
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

  /// Open the in-app camera, save the capture to the gallery, embed and
  /// index it so it becomes searchable, then run an image-to-image search
  /// using the same photo.
  ///
  /// Pipeline mirrors a real camera app: capture → gallery → embed → index
  /// → search. The save and the search both consume the captured bytes
  /// in-memory so there is no redundant disk I/O.
  Future<void> _captureAndSearch() async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    try {
      final captureService = CameraCaptureService();
      final result = await captureService.captureAndSave(
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (result == null) return; // user cancelled

      // Surface gallery-save outcome so the user knows the photo persisted.
      if (mounted && messenger != null) {
        final String text;
        if (result.savedToGallery) {
          text = 'Photo saved to gallery — indexing…';
        } else if (result.saveError != null) {
          // Truncate so a long Kotlin stack trace doesn't blow up the bar.
          final err = result.saveError!;
          final short = err.length > 120 ? '${err.substring(0, 120)}…' : err;
          text = 'Capture OK, gallery save failed: $short';
        } else {
          text = 'Photo captured (gallery save skipped)';
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(text),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: result.savedToGallery ? 2 : 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      // Embed + register in the ANN index in-place so the new photo is
      // immediately a search candidate. Skipped silently if save failed.
      if (result.savedAsset != null) {
        await widget.searchService
            .indexCapturedPhoto(result.savedAsset!, result.bytes);
      }

      // Run the image-to-image search against the just-captured bytes —
      // works regardless of whether indexing succeeded.
      _initiatedSearch = true;
      await widget.searchService.searchByImage(result.bytes);
    } catch (e) {
      if (mounted && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Camera capture failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  /// Pick an image from the gallery and perform image-to-image search.
  ///
  /// Kept as a separate path from [_captureAndSearch]: gallery picks reuse
  /// existing assets so they don't need to be saved or re-indexed.
  // ignore: unused_element
  Future<void> _performImageSearch(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      _initiatedSearch = true;
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
        color: P.surfaceAlt(isDark),
        child: Icon(
          Icons.image_outlined,
          color: isDark ? Colors.white30 : Colors.black26,
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateChip({
    required this.label,
    required this.date,
    required this.isDark,
    required this.onTap,
    this.onClear,
  });

  String get _display {
    if (date == null) return label;
    return '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final accent = P.accent(isDark);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        side: BorderSide(
            color: hasDate ? accent : P.border(isDark)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        backgroundColor: hasDate
            ? accent.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today,
              size: 14,
              color: hasDate ? accent : P.textFaint(isDark)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _display,
              style: TextStyle(
                  fontSize: 12,
                  color: hasDate ? accent : P.textMore(isDark),
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasDate && onClear != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, size: 14, color: accent),
            ),
          ],
        ],
      ),
    );
  }
}
