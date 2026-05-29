import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';
import 'details_screen.dart';

import '../theme/palette.dart';
class ResultsScreen extends StatefulWidget {
  final SearchResult searchResult;
  final ImageSearchService searchService;
  /// Thumbnail of the query image for image-to-image searches. Rendered in the
  /// header in place of the search-icon badge when non-null.
  final Uint8List? queryImage;

  const ResultsScreen({
    super.key,
    required this.searchResult,
    required this.searchService,
    this.queryImage,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

enum _RelevanceBucket {
  off(0.0, 'Off'),
  low(0.20, 'Low'),
  medium(0.45, 'Medium'),
  high(0.70, 'High');

  final double threshold;
  final String label;
  const _RelevanceBucket(this.threshold, this.label);
}

class _ResultsScreenState extends State<ResultsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  _RelevanceBucket _relevance = _RelevanceBucket.off;

  // Pool used for filtering. Starts as the original result; gets swapped to an
  // expanded top-N pool the first time a non-Off relevance is applied so the
  // threshold has more than just the post-combo-filter handful to keep.
  late SearchResult _activeResult = widget.searchResult;
  SearchResult? _expandedResult;
  bool _isExpanding = false;

  bool get _hasActiveFilters =>
      _startDate != null ||
      _endDate != null ||
      _relevance != _RelevanceBucket.off;

  /// Re-runs the underlying search with [forceTopN] temporarily set, so the
  /// relevance filter has the full top-N candidate pool to threshold against
  /// instead of the small post-combo-filter set.
  Future<void> _ensureExpandedPool() async {
    if (_expandedResult != null || _isExpanding) return;
    setState(() => _isExpanding = true);
    final svc = widget.searchService;
    final priorForce = svc.forceTopN;
    svc.forceTopN = svc.topK;
    try {
      final originalQuery = widget.searchResult.query;
      if (widget.queryImage != null) {
        await svc.searchByImage(widget.queryImage!.toList());
      } else if (originalQuery.isNotEmpty) {
        await svc.searchImages(originalQuery);
      }
      final fresh = svc.currentState.result;
      if (fresh != null && mounted) {
        _expandedResult = fresh;
        _activeResult = fresh;
      }
    } finally {
      svc.forceTopN = priorForce;
      if (mounted) setState(() => _isExpanding = false);
    }
  }

  void _applyRelevance(_RelevanceBucket r) {
    setState(() {
      _relevance = r;
      _activeResult = (r == _RelevanceBucket.off)
          ? widget.searchResult
          : (_expandedResult ?? widget.searchResult);
    });
    if (r != _RelevanceBucket.off && _expandedResult == null) {
      _ensureExpandedPool();
    }
  }

  List<int> get _filteredIndices {
    final total = _activeResult.images.length;

    final scores = _activeResult.scores;
    final topScore =
        (scores != null && scores.isNotEmpty) ? scores.first : 1.0;
    final minScore = _relevance != _RelevanceBucket.off
        ? topScore * _relevance.threshold
        : null;

    final end = _endDate != null
        ? DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)
        : null;

    final out = <int>[];
    for (int i = 0; i < total; i++) {
      final img = _activeResult.images[i];

      if (_startDate != null && img.createdAt != null) {
        if (img.createdAt!.isBefore(_startDate!)) continue;
      }
      if (end != null && img.createdAt != null) {
        if (img.createdAt!.isAfter(end)) continue;
      }

      if (minScore != null) {
        final score = _activeResult.scoreAt(i) ?? 0.0;
        if (score < minScore) continue;
      }

      out.add(i);
    }
    return out;
  }



  void _openFilterSheet() {
    var start = _startDate;
    var end = _endDate;
    var relevance = _relevance;
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
                      Text('Filter Results',
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
                            relevance = _RelevanceBucket.off;
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
                    relevance == _RelevanceBucket.off
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
                    children: _RelevanceBucket.values.map((r) {
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
                          _startDate = start;
                          _endDate = end;
                        });
                        _applyRelevance(relevance);
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


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = P.text(isDark);
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
            color: P.hairline(isDark),
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: Icon(Icons.tune,
                    color: _hasActiveFilters
                        ? P.accent(isDark)
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
                    decoration: BoxDecoration(
                      color: P.accent(isDark),
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
          if (_isExpanding)
            LinearProgressIndicator(
              minHeight: 2,
              valueColor: AlwaysStoppedAnimation<Color>(P.accent(isDark)),
              backgroundColor: P.accent(isDark).withValues(alpha: 0.12),
            ),
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
    final blue = P.accent(isDark);
    final blueSoft = P.accentSoft(isDark);
    final surface = P.surface(isDark);
    final border = P.border(isDark);
    final textMore = P.textMore(isDark);

    final total = _activeResult.resultCount;
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
            if (widget.queryImage != null)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: blueSoft, spreadRadius: 2)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(widget.queryImage!, fit: BoxFit.cover),
                ),
              )
            else
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
                  if (widget.searchResult.query.isNotEmpty)
                    Text('"${widget.searchResult.query}"',
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
                          onTap: () {
                            setState(() {
                              _startDate = null;
                              _endDate = null;
                            });
                            _applyRelevance(_RelevanceBucket.off);
                          },
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
    final blue = P.accent(isDark);
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
          final image = _activeResult.images[origIndex];
          final score = _activeResult.scoreAt(origIndex);
          final isBest = pos == 0;
          return Material(
            color: P.surfaceAlt(isDark),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetailsScreen(
                    image: image,
                    searchService: widget.searchService,
                    imageList: _activeResult.images,
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
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.star_rounded, size: 11, color: P.onAccent(isDark)),
                                const SizedBox(width: 4),
                                Text('Best match', style: TextStyle(color: P.onAccent(isDark), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                              ]),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(999)),
                              child: Text('#${pos + 1}', style: TextStyle(color: P.onAccent(isDark), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                            ),
                    ),
                    // Confidence bars (not for best match)
                    if (!isBest && score != null)
                      Positioned(
                        bottom: 6, right: 6,
                        child: _buildConfidenceBars(score, _topScore, isDark),
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

  double get _topScore {
    final scores = _activeResult.scores;
    return (scores != null && scores.isNotEmpty) ? scores.first : 1.0;
  }

  Widget _buildConfidenceBars(double score, double topScore, bool isDark) {
    final ratio = topScore > 0 ? score / topScore : 0.0;
    final filled = ratio >= 0.97 ? 3 : ratio >= 0.93 ? 2 : 1;
    final barColor = P.accent(isDark);
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
      color: P.surfaceHigh(isDark),
      child: Center(
        child: Icon(Icons.image_outlined,
            color: P.textFaint(isDark),
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
              color: P.accent(isDark).withValues(alpha: 0.12),
              border: Border.all(color: P.accent(isDark).withValues(alpha: 0.35), width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
                isFiltered ? Icons.filter_alt_off : Icons.search_off,
                size: 48,
                color: P.accent(isDark)),
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
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
                _applyRelevance(_RelevanceBucket.off);
              },
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Clear Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: P.accent(isDark),
                foregroundColor: P.onAccent(isDark),
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
                backgroundColor: P.accent(isDark),
                foregroundColor: P.onAccent(isDark),
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
    final accent = P.accent(isDark);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                  fontWeight:
                      hasDate ? FontWeight.w600 : FontWeight.normal),
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
