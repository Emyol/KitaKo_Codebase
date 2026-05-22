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

/// Coarse relevance buckets shown to the user instead of a continuous slider.
///
/// Each bucket maps to a minimum score as a fraction of the top result's
/// score. `off` means no relevance filtering at all.
enum _RelevanceBucket {
  off(0.0, 'Off'),
  veryLow(0.20, 'Very Low'),
  low(0.40, 'Low'),
  average(0.60, 'Average'),
  high(0.80, 'High'),
  veryHigh(0.95, 'Very High');

  final double threshold;
  final String label;
  const _RelevanceBucket(this.threshold, this.label);
}

class _ResultsScreenState extends State<ResultsScreen> {
  // â”€â”€ Filter state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  DateTime? _startDate;
  DateTime? _endDate;

  /// Selected relevance bucket. `off` means no filtering.
  _RelevanceBucket _relevance = _RelevanceBucket.off;

  /// null = show all.
  int? _maxResults;

  static const _maxResultsOptions = [10, 20, 50, 100];

  // â”€â”€ Derived â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  bool get _hasActiveFilters =>
      _startDate != null ||
      _endDate != null ||
      _relevance != _RelevanceBucket.off ||
      _maxResults != null;

  /// Returns indices into `widget.searchResult.images` that pass all filters.
  List<int> get _filteredIndices {
    final scores = widget.searchResult.scores;
    final topScore =
        (scores != null && scores.isNotEmpty) ? scores.first : 1.0;
    final minScore = _relevance != _RelevanceBucket.off
        ? topScore * _relevance.threshold
        : null;

    final end = _endDate != null
        ? DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)
        : null;

    final out = <int>[];
    for (int i = 0; i < widget.searchResult.images.length; i++) {
      final img = widget.searchResult.images[i];

      // â”€â”€ Date range â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (_startDate != null && img.createdAt != null) {
        if (img.createdAt!.isBefore(_startDate!)) continue;
      }
      if (end != null && img.createdAt != null) {
        if (img.createdAt!.isAfter(end)) continue;
      }

      // â”€â”€ Relevance threshold â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (minScore != null) {
        final score = widget.searchResult.scoreAt(i) ?? 0.0;
        if (score < minScore) continue;
      }

      out.add(i);
      if (_maxResults != null && out.length >= _maxResults!) break;
    }
    return out;
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _formatScore(double? score) {
    if (score == null) return '?';
    return '${(score * 100).toStringAsFixed(1)}%';
  }


  // â”€â”€ Filter bottom sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _openFilterSheet() {
    // Local copies so the sheet can mutate without rebuilding the parent until
    // the user taps Apply.
    var start = _startDate;
    var end = _endDate;
    var relevance = _relevance;
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
            final bg = isDark ? const Color(0xFF161B22) : Colors.white;
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
                          color: Color(0xFF3B82F6)),
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
                            relevance = _RelevanceBucket.off;
                            maxRes = null;
                          });
                        },
                        child: const Text('Reset',
                            style: TextStyle(color: Color(0xFF3B82F6))),
                      ),
                    ],
                  ),
                  Divider(color: divColor),

                  // â”€â”€ Date Range â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

                  // â”€â”€ Relevance Threshold â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  Row(
                    children: [
                      Text('Relevance', style: labelStyle),
                      const Spacer(),
                      // Tiny score indicator: still surfaces the underlying %
                      // so users who care can verify what the bucket means.
                      Text(
                        relevance == _RelevanceBucket.off
                            ? 'Off'
                            : 'â‰¥ ${(relevance.threshold * 100).round()}% of top',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: relevance == _RelevanceBucket.off
                              ? (isDark ? Colors.white38 : Colors.black38)
                              : const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                  if (relevance != _RelevanceBucket.off) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Top score: ${_formatScore(topScore)}  â†’  '
                      'Min shown: ${_formatScore(topScore * relevance.threshold)}',
                      style: subStyle,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _RelevanceBucket.values.map((b) {
                      final selected = relevance == b;
                      return ChoiceChip(
                        label: Text(b.label),
                        selected: selected,
                        onSelected: (_) => setSheet(() => relevance = b),
                        selectedColor: const Color(0xFF3B82F6),
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: divColor),

                  // â”€â”€ Max Results â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                            selectedColor: const Color(0xFF3B82F6),
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
                        selectedColor: const Color(0xFF3B82F6),
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

                  // â”€â”€ Location (placeholder) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

                  // â”€â”€ Apply â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          _startDate = start;
                          _endDate = end;
                          _relevance = relevance;
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

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: isDark
                ? const Color(0x1F60A5FA)
                : const Color(0x192563EB),
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: Icon(Icons.tune,
                    color: _hasActiveFilters
                        ? const Color(0xFF3B82F6)
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
                      color: Color(0xFF3B82F6),
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
          _buildQueryHeader(context, isDark, textColor, indices),
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
      BuildContext context, bool isDark, Color textColor, List<int> indices) {
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final blueSoft = isDark ? const Color(0x2E3B82F6) : const Color(0xFFDBEAFE);
    final surface = isDark ? const Color(0xFF161B22) : Colors.white;
    final border = isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0);
    final textMore = isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B);

    final total = widget.searchResult.resultCount;
    final shown = indices.length;
    final subtitle = _hasActiveFilters
        ? '$shown of $total match${total == 1 ? '' : 'es'} · filtered'
        : '$total match${total == 1 ? '' : 'es'} · ranked by similarity';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF0F2A4A).withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration:
                  BoxDecoration(color: blueSoft, shape: BoxShape.circle),
              child: Icon(
                  widget.searchResult.query.isEmpty
                      ? Icons.image_search
                      : Icons.search,
                  size: 16,
                  color: blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      widget.searchResult.query.isEmpty
                          ? 'Similar Images'
                          : '"${widget.searchResult.query}"',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Expanded(
                        child: Text(subtitle,
                            style: TextStyle(
                                color: textMore, fontSize: 11, height: 1.4)),
                      ),
                      if (_hasActiveFilters)
                        GestureDetector(
                          onTap: () => setState(() {
                            _startDate = null;
                            _endDate = null;
                            _relevance = _RelevanceBucket.off;
                            _maxResults = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.close, size: 10, color: blue),
                                const SizedBox(width: 2),
                                Text('Clear',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: blue,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
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


  Widget _buildGrid(BuildContext context, bool isDark, List<int> indices) {
    final blue = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: indices.length,
        itemBuilder: (context, pos) {
          final origIndex = indices[pos];
          final image = widget.searchResult.images[origIndex];
          final score = widget.searchResult.scoreAt(origIndex);
          final isBest = pos == 0;
          return Material(
            color: isDark ? const Color(0xFF1A2030) : const Color(0xFFE2EAF4),
            borderRadius: BorderRadius.circular(14),
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
              borderRadius: BorderRadius.circular(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(image.path),
                        fit: BoxFit.cover, cacheWidth: 256,
                        errorBuilder: (_, _, _) => _placeholder(image, isDark)),
                    // Rank / Best match badge
                    Positioned(
                      top: 6, left: 6,
                      child: isBest
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(999)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                                Icon(Icons.star_rounded, size: 11, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Best match', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                              ]),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(999)),
                              child: Text('#${pos + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                            ),
                    ),
                    // Confidence bars (not for best match)
                    if (!isBest && score != null)
                      Positioned(
                        bottom: 6, right: 6,
                        child: _buildConfidenceBars(score, isDark),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfidenceBars(double score, bool isDark) {
    final filled = score >= 0.85 ? 3 : score >= 0.70 ? 2 : 1;
    final barColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1726).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 3,
              height: [6.0, 9.0, 12.0][i],
              decoration: BoxDecoration(
                color: i < filled ? barColor : Colors.white.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _placeholder(ImageItem image, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF222A36) : const Color(0xFFE2EAF4),
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
                  color: isDark ? const Color(0xFF1F2733) : const Color(0xFFBFD3E8), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
                isFiltered ? Icons.filter_alt_off : Icons.search_off,
                size: 48,
                color: const Color(0xFF3B82F6)),
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
                _relevance = _RelevanceBucket.off;
                _maxResults = null;
              }),
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
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
                backgroundColor: const Color(0xFF3B82F6),
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

// â”€â”€ Small helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                ? const Color(0xFF3B82F6)
                : (isDark ? Colors.white24 : Colors.black26)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        backgroundColor: hasDate
            ? const Color(0xFF3B82F6).withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today,
              size: 14,
              color: hasDate
                  ? const Color(0xFF3B82F6)
                  : (isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _display,
              style: TextStyle(
                  fontSize: 12,
                  color: hasDate
                      ? const Color(0xFF3B82F6)
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
                  size: 14, color: Color(0xFF3B82F6)),
            ),
          ],
        ],
      ),
    );
  }
}
