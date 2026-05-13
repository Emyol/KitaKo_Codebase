import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';
import 'details_screen.dart';

class ResultsScreen extends StatefulWidget {
  final SearchResult searchResult;
  final ImageSearchService searchService;

  const ResultsScreen({
    super.key,
    required this.searchResult,
    required this.searchService,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // ── Filter state ────────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;

  /// Minimum score as a fraction of the top result's score (0.0 = off, 0.8 = 80%).
  double _relevancePct = 0.0;

  /// null = show all.
  int? _maxResults;

  static const _maxResultsOptions = [10, 20, 50, 100];

  // ── Derived ─────────────────────────────────────────────────────────────────

  bool get _hasActiveFilters =>
      _startDate != null ||
      _endDate != null ||
      _relevancePct > 0.0 ||
      _maxResults != null;

  /// Returns indices into `widget.searchResult.images` that pass all filters.
  List<int> get _filteredIndices {
    final scores = widget.searchResult.scores;
    final topScore =
        (scores != null && scores.isNotEmpty) ? scores.first : 1.0;
    final minScore = _relevancePct > 0.0 ? topScore * _relevancePct : null;

    final end = _endDate != null
        ? DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)
        : null;

    final out = <int>[];
    for (int i = 0; i < widget.searchResult.images.length; i++) {
      final img = widget.searchResult.images[i];

      // ── Date range ──────────────────────────────────────────────────────────
      if (_startDate != null && img.createdAt != null) {
        if (img.createdAt!.isBefore(_startDate!)) continue;
      }
      if (end != null && img.createdAt != null) {
        if (img.createdAt!.isAfter(end)) continue;
      }

      // ── Relevance threshold ─────────────────────────────────────────────────
      if (minScore != null) {
        final score = widget.searchResult.scoreAt(i) ?? 0.0;
        if (score < minScore) continue;
      }

      out.add(i);
      if (_maxResults != null && out.length >= _maxResults!) break;
    }
    return out;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatScore(double? score) {
    if (score == null) return '?';
    return '${(score * 100).toStringAsFixed(1)}%';
  }

  Color _scoreColor(double? score) {
    if (score == null) return Colors.grey;
    if (score >= 0.20) return Colors.greenAccent;
    if (score >= 0.10) return Colors.yellowAccent;
    return Colors.orangeAccent;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Any';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // ── Filter bottom sheet ──────────────────────────────────────────────────────

  void _openFilterSheet() {
    // Local copies so the sheet can mutate without rebuilding the parent until
    // the user taps Apply.
    var start = _startDate;
    var end = _endDate;
    var relPct = _relevancePct;
    int? maxRes = _maxResults;

    final scores = widget.searchResult.scores;
    final topScore =
        (scores != null && scores.isNotEmpty) ? scores.first : 1.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
            final divColor =
                isDark ? Colors.white12 : Colors.black12;
            final labelStyle = TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            );
            final subStyle = TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black45,
            );

            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.tune, size: 20,
                          color: Color(0xFF4A90E2)),
                      const SizedBox(width: 8),
                      Text('Filter Results',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setSheet(() {
                            start = null;
                            end = null;
                            relPct = 0.0;
                            maxRes = null;
                          });
                        },
                        child: const Text('Reset',
                            style: TextStyle(color: Color(0xFF4A90E2))),
                      ),
                    ],
                  ),
                  Divider(color: divColor),

                  // ── Date Range ─────────────────────────────────────────────
                  Text('Date Range', style: labelStyle),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DateButton(
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
                        child: _DateButton(
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
                          onClear:
                              end != null ? () => setSheet(() => end = null) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: divColor),

                  // ── Relevance Threshold ────────────────────────────────────
                  Row(
                    children: [
                      Text('Relevance Threshold', style: labelStyle),
                      const Spacer(),
                      Text(
                        relPct > 0
                            ? '≥ ${(relPct * 100).round()}% of top'
                            : 'Off',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: relPct > 0
                              ? const Color(0xFF4A90E2)
                              : (isDark ? Colors.white38 : Colors.black38),
                        ),
                      ),
                    ],
                  ),
                  if (relPct > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Top score: ${_formatScore(topScore)}  →  '
                      'Min shown: ${_formatScore(topScore * relPct)}',
                      style: subStyle,
                    ),
                  ],
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      activeTrackColor: const Color(0xFF4A90E2),
                      thumbColor: const Color(0xFF4A90E2),
                      overlayColor:
                          const Color(0xFF4A90E2).withValues(alpha: 0.15),
                      inactiveTrackColor: isDark
                          ? Colors.white24
                          : Colors.black12,
                    ),
                    child: Slider(
                      value: relPct,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (v) => setSheet(() => relPct = v),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Off', style: subStyle),
                      Text('50%', style: subStyle),
                      Text('100%', style: subStyle),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: divColor),

                  // ── Max Results ────────────────────────────────────────────
                  Text('Display Count', style: labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ..._maxResultsOptions.map((n) => ChoiceChip(
                            label: Text('$n'),
                            selected: maxRes == n,
                            onSelected: (_) =>
                                setSheet(() => maxRes = maxRes == n ? null : n),
                            selectedColor: const Color(0xFF4A90E2),
                            labelStyle: TextStyle(
                              color: maxRes == n
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: maxRes == n
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          )),
                      ChoiceChip(
                        label: const Text('All'),
                        selected: maxRes == null,
                        onSelected: (_) => setSheet(() => maxRes = null),
                        selectedColor: const Color(0xFF4A90E2),
                        labelStyle: TextStyle(
                          color: maxRes == null
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: maxRes == null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: divColor),

                  // ── Location (placeholder) ────────────────────────────────
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16,
                          color: isDark ? Colors.white24 : Colors.black26),
                      const SizedBox(width: 6),
                      Text('Location',
                          style: labelStyle.copyWith(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.black26)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.black12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('GPS metadata required',
                            style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.black26)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Apply ──────────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          _startDate = start;
                          _endDate = end;
                          _relevancePct = relPct;
                          _maxResults = maxRes;
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Apply Filters',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final indices = _filteredIndices;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).appBarTheme.titleTextStyle?.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Results'),
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: Icon(Icons.tune,
                    color: _hasActiveFilters
                        ? const Color(0xFF4A90E2)
                        : Theme.of(context)
                            .appBarTheme
                            .titleTextStyle
                            ?.color),
                tooltip: 'Filter',
                onPressed: _openFilterSheet,
              ),
              if (_hasActiveFilters)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4A90E2),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQueryHeader(context, isDark, textColor),
          _buildResultsCountBar(context, isDark, textColor, indices),
          Expanded(
            child: indices.isNotEmpty
                ? _buildGrid(context, isDark, indices)
                : _buildNoResults(context, isDark, textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryHeader(
      BuildContext context, bool isDark, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              const Icon(Icons.search, color: Color(0xFF4A90E2), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"${widget.searchResult.query}"',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (widget.searchResult.searchTimeMs != null) ...[
            const SizedBox(height: 4),
            Text(
              'Completed in ${widget.searchResult.searchTimeMs}ms',
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsCountBar(BuildContext context, bool isDark,
      Color textColor, List<int> indices) {
    final total = widget.searchResult.resultCount;
    final shown = indices.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            _hasActiveFilters
                ? 'Showing $shown of $total result${total == 1 ? '' : 's'}'
                : '$total result${total == 1 ? '' : 's'} found',
            style: TextStyle(
                color: textColor.withValues(alpha: 0.7), fontSize: 14),
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _startDate = null;
                _endDate = null;
                _relevancePct = 0.0;
                _maxResults = null;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close,
                        size: 12, color: Color(0xFF4A90E2)),
                    const SizedBox(width: 3),
                    const Text('Clear filters',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4A90E2),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(
      BuildContext context, bool isDark, List<int> indices) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: indices.length,
        itemBuilder: (context, pos) {
          final origIndex = indices[pos];
          final image = widget.searchResult.images[origIndex];
          return _buildCard(context, image, origIndex, pos, isDark);
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, ImageItem image, int origIndex,
      int displayPos, bool isDark) {
    final score = widget.searchResult.scoreAt(origIndex);
    return Material(
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
      elevation: 3,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailsScreen(
              image: image,
              searchService: widget.searchService,
              imageList: widget.searchResult.images,
              currentIndex: origIndex,
              popCount: 2,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(image.path),
                        fit: BoxFit.cover,
                        cacheWidth: 256,
                        errorBuilder: (_, _, _) =>
                            _placeholder(image, isDark)),
                    // Rank badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _badge('#${displayPos + 1}',
                          const Color(0xFF4A90E2), Colors.white),
                    ),
                    // Score badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.trending_up,
                                size: 12, color: _scoreColor(score)),
                            const SizedBox(width: 4),
                            Text(_formatScore(score),
                                style: TextStyle(
                                    color: _scoreColor(score),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(image.name,
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(_formatFileSize(image.sizeBytes),
                          style: TextStyle(
                              color:
                                  (isDark ? Colors.white : Colors.black87)
                                      .withValues(alpha: 0.5),
                              fontSize: 11)),
                      if (image.createdAt != null) ...[
                        Text('  ·  ',
                            style: TextStyle(
                                color: (isDark
                                        ? Colors.white
                                        : Colors.black87)
                                    .withValues(alpha: 0.3),
                                fontSize: 11)),
                        Text(_formatDate(image.createdAt),
                            style: TextStyle(
                                color: (isDark
                                        ? Colors.white
                                        : Colors.black87)
                                    .withValues(alpha: 0.4),
                                fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _placeholder(ImageItem image, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
      child: Center(
        child: Icon(Icons.image_outlined,
            color: isDark
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.3),
            size: 48),
      ),
    );
  }

  Widget _buildNoResults(
      BuildContext context, bool isDark, Color textColor) {
    final isFiltered = _hasActiveFilters;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(
                  color: const Color(0xFF1E3A5F), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
                isFiltered ? Icons.filter_alt_off : Icons.search_off,
                size: 48,
                color: const Color(0xFF4A90E2)),
          ),
          const SizedBox(height: 20),
          Text(
            isFiltered
                ? 'No results match your filters'
                : 'No results found',
            style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'Try adjusting or clearing the filters'
                : 'Try a different search query',
            style: TextStyle(
                color: textColor.withValues(alpha: 0.6), fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (isFiltered)
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _startDate = null;
                _endDate = null;
                _relevancePct = 0.0;
                _maxResults = null;
              }),
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.search),
              label: const Text('New Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Small helpers ──────────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateButton({
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
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        side: BorderSide(
            color: hasDate
                ? const Color(0xFF4A90E2)
                : (isDark ? Colors.white24 : Colors.black26)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        backgroundColor: hasDate
            ? const Color(0xFF4A90E2).withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today,
              size: 14,
              color: hasDate
                  ? const Color(0xFF4A90E2)
                  : (isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _display,
              style: TextStyle(
                  fontSize: 12,
                  color: hasDate
                      ? const Color(0xFF4A90E2)
                      : (isDark ? Colors.white54 : Colors.black54),
                  fontWeight: hasDate
                      ? FontWeight.w600
                      : FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasDate && onClear != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close,
                  size: 14, color: Color(0xFF4A90E2)),
            ),
          ],
        ],
      ),
    );
  }
}
