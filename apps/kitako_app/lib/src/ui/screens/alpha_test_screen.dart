import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/search_models.dart';
import '../../services/image_search_service.dart';
import '../../services/embedding_service.dart';

/// Available search algorithm modes for the alpha test screen.
enum _SearchMethod {
  bruteForce('Brute Force', Icons.list_alt),
  ivfPq('IVF-PQ', Icons.speed),
  hnsw('HNSW', Icons.gps_fixed);

  final String label;
  final IconData icon;
  const _SearchMethod(this.label, this.icon);
}

/// Alpha-testing screen for inspecting search service internals.
///
/// Lets developers:
/// - Choose the active model variant
/// - Choose the search algorithm (Brute Force / IVF-PQ / HNSW)
/// - Run text queries and inspect per-result similarity scores
/// - Run a Recall@K accuracy comparison between ANN and brute-force
class AlphaTestScreen extends StatefulWidget {
  final ImageSearchService searchService;

  const AlphaTestScreen({super.key, required this.searchService});

  @override
  State<AlphaTestScreen> createState() => _AlphaTestScreenState();
}

class _AlphaTestScreenState extends State<AlphaTestScreen> {
  final TextEditingController _queryController = TextEditingController();

  bool _searching = false;
  bool _switchingModel = false;
  bool _runningRecall = false;

  _SearchMethod _searchMethod = _SearchMethod.bruteForce;

  int _elapsedMs = 0;
  int? _memoryDeltaBytes;
  SearchState _lastState = const SearchState();
  Map<String, dynamic>? _recallResult;

  // ── Helpers ──────────────────────────────────────────────────────────────

  EmbeddingService get _embedding => widget.searchService.embeddingService;

  Map<String, dynamic> get _indexStatus => widget.searchService.annIndexStatus;

  // ── Algorithm selection ──────────────────────────────────────────────────

  void _applySearchMethod(_SearchMethod method) {
    setState(() => _searchMethod = method);
    switch (method) {
      case _SearchMethod.bruteForce:
        widget.searchService.setForceBruteForce(true);
      case _SearchMethod.ivfPq:
        widget.searchService.setForceBruteForce(false);
        widget.searchService.setPreferredAlgorithm(false); // IVF-PQ
      case _SearchMethod.hnsw:
        widget.searchService.setForceBruteForce(false);
        widget.searchService.setPreferredAlgorithm(true); // HNSW
    }
  }

  // ── Model switch ─────────────────────────────────────────────────────────

  Future<void> _switchModel(ModelVariant variant) async {
    if (_switchingModel) return;
    setState(() => _switchingModel = true);
    try {
      final ok = await _embedding.switchToVariant(variant);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load ${variant.displayName}')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingModel = false);
    }
  }

  // ── Search ───────────────────────────────────────────────────────────────

  Future<void> _runQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _searching) return;

    if (!_embedding.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No model loaded — cannot search')),
      );
      return;
    }

    setState(() {
      _searching = true;
      _lastState = const SearchState();
      _recallResult = null;
    });

    try {
      final rssBefore = ProcessInfo.currentRss;
      final sw = Stopwatch()..start();
      await widget.searchService.searchImages(query);
      sw.stop();
      if (mounted) {
        setState(() {
          _elapsedMs = sw.elapsedMilliseconds;
          _memoryDeltaBytes = ProcessInfo.currentRss - rssBefore;
          _lastState = widget.searchService.currentState;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastState = SearchState(
            status: SearchStatus.error,
            query: _queryController.text.trim(),
            error: e.toString(),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Recall@K accuracy test ────────────────────────────────────────────────

  Future<void> _runRecallTest() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _runningRecall) return;

    if (!_embedding.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No model loaded — cannot test')),
      );
      return;
    }

    setState(() {
      _runningRecall = true;
      _recallResult = null;
    });

    try {
      // Generate the query embedding directly and run testAccuracy on the ANN
      // service (which compares ANN vs brute-force ground truth internally).
      final queryEmbedding =
          await _embedding.generateEmbedding(query);
      final result = await widget.searchService.annSearchService
          .testAccuracy(queryEmbedding, k: 10);
      if (mounted) setState(() => _recallResult = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recall test failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _runningRecall = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);

    final results = _lastState.result?.images ?? [];
    final scores = _lastState.result?.scores;
    final hasError = _lastState.status == SearchStatus.error;
    final indexCount = widget.searchService.indexedImageCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alpha Test'),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : null,
      ),
      body: Column(
        children: [
          // ── Settings Card ───────────────────────────────────────────────
          Container(
            color: surfaceColor,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                // Model row
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        'Model',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _switchingModel
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: LinearProgressIndicator(),
                            )
                          : DropdownButton<ModelVariant>(
                              isExpanded: true,
                              isDense: true,
                              value: _embedding.activeVariant,
                              hint: const Text('None loaded',
                                  style: TextStyle(fontSize: 13)),
                              onChanged: _switchingModel
                                  ? null
                                  : (v) {
                                      if (v != null) _switchModel(v);
                                    },
                              items: ModelVariant.values.map((v) {
                                return DropdownMenuItem(
                                  value: v,
                                  child: Text(v.displayName,
                                      style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Search method row
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        'Search',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: DropdownButton<_SearchMethod>(
                        isExpanded: true,
                        isDense: true,
                        value: _searchMethod,
                        onChanged: (v) {
                          if (v != null) _applySearchMethod(v);
                        },
                        items: _SearchMethod.values.map((v) {
                          return DropdownMenuItem(
                            value: v,
                            child: Row(
                              children: [
                                Icon(v.icon, size: 14,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54),
                                const SizedBox(width: 6),
                                Text(v.label,
                                    style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Model + index status
                Row(
                  children: [
                    Icon(
                      _embedding.isInitialized
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: _embedding.isInitialized
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _embedding.isInitialized
                            ? '${_embedding.activeVariant?.displayName ?? "Model"} · $indexCount indexed'
                            : 'No model loaded',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // ANN index status
                _AnnStatusRow(
                  indexStatus: _indexStatus,
                  activeMethod: _searchMethod,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Query Row ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      hintText: 'Search query…',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _runQuery(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _searching ? null : _runQuery,
                    child: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Run'),
                  ),
                ),
                const SizedBox(width: 6),
                // Recall@10 test button — only relevant for ANN algorithms
                if (_searchMethod != _SearchMethod.bruteForce)
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _runningRecall ? null : _runRecallTest,
                      child: _runningRecall
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Recall@10',
                              style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),

          // ── Stats Bar ───────────────────────────────────────────────────
          if (_lastState.status != SearchStatus.idle)
            Container(
              color: isDark
                  ? const Color(0xFF252525)
                  : const Color(0xFFEAEAEA),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                children: [
                  _StatChip(
                    label: '${_elapsedMs}ms',
                    icon: Icons.timer_outlined,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    label: '${results.length} results',
                    icon: Icons.photo_library_outlined,
                    isDark: isDark,
                  ),
                  if (scores != null && scores.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    _StatChip(
                      label: 'top ${scores.first.toStringAsFixed(3)}',
                      icon: Icons.star_outline,
                      isDark: isDark,
                    ),
                  ],
                  if (_lastState.normalizedQuery != null &&
                      _lastState.normalizedQuery != _lastState.query) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '→ "${_lastState.normalizedQuery}"',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // ── Recall result banner ─────────────────────────────────────────
          if (_recallResult != null)
            _RecallBanner(result: _recallResult!, isDark: isDark),

          // ── Per-query diagnostics ────────────────────────────────────────
          if (_lastState.status != SearchStatus.idle)
            _DiagnosticsPanel(
              embeddingTimeMs: _lastState.result?.embeddingTimeMs,
              indexSearchTimeMs: _lastState.result?.searchTimeMs,
              totalTimeMs: _elapsedMs,
              memoryDeltaBytes: _memoryDeltaBytes,
              isDark: isDark,
            ),

          const Divider(height: 1),

          // ── Results ─────────────────────────────────────────────────────
          Expanded(
            child: hasError
                ? _ErrorPanel(message: _lastState.error ?? 'Unknown error')
                : results.isEmpty
                    ? _EmptyPanel(
                        status: _lastState.status,
                        isDark: isDark,
                      )
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final image = results[i];
                          final score = scores != null && i < scores.length
                              ? scores[i]
                              : null;
                          return _ResultTile(
                            image: image,
                            rank: i + 1,
                            score: score,
                            isDark: isDark,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── ANN status row ─────────────────────────────────────────────────────────────

class _AnnStatusRow extends StatelessWidget {
  final Map<String, dynamic> indexStatus;
  final _SearchMethod activeMethod;
  final bool isDark;

  const _AnnStatusRow({
    required this.indexStatus,
    required this.activeMethod,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hnswSize = indexStatus['hnswSize'] as int? ?? 0;
    final hnswInit = indexStatus['hnswInitialized'] as bool? ?? false;
    final ivfSize = indexStatus['ivfpqSize'] as int? ?? 0;
    final ivfTrained = indexStatus['ivfpqTrained'] as bool? ?? false;
    final pending = indexStatus['pendingVectors'] as int? ?? 0;
    final color = isDark ? Colors.white54 : Colors.black54;

    String hnswLabel;
    if (!hnswInit) {
      hnswLabel = 'HNSW: unavailable';
    } else if (hnswSize == 0) {
      hnswLabel = 'HNSW: ready (empty)';
    } else {
      hnswLabel = 'HNSW: $hnswSize vectors';
    }

    String ivfLabel;
    if (!ivfTrained) {
      ivfLabel = pending > 0
          ? 'IVF-PQ: pending ($pending buffered)'
          : 'IVF-PQ: untrained';
    } else {
      ivfLabel = 'IVF-PQ: $ivfSize vectors';
    }

    return Row(
      children: [
        _AnnChip(
          label: hnswLabel,
          active: activeMethod == _SearchMethod.hnsw && hnswInit,
          color: color,
        ),
        const SizedBox(width: 10),
        _AnnChip(
          label: ivfLabel,
          active: activeMethod == _SearchMethod.ivfPq && ivfTrained,
          color: color,
        ),
      ],
    );
  }
}

class _AnnChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _AnnChip({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          active ? Icons.check_circle : Icons.circle_outlined,
          size: 11,
          color: active ? Colors.green : color,
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.green : color,
          ),
        ),
      ],
    );
  }
}

// ── Recall banner ──────────────────────────────────────────────────────────────

class _RecallBanner extends StatelessWidget {
  final Map<String, dynamic> result;
  final bool isDark;

  const _RecallBanner({required this.result, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final algorithm = result['algorithm'] as String? ?? '?';
    final recall = result['recallPercent'] as String? ?? '?';
    final correct = result['correctMatches'] as int? ?? 0;
    final k = result['k'] as int? ?? 10;
    final error = result['error'] as String?;

    final bgColor = isDark ? const Color(0xFF1A2A1A) : const Color(0xFFE8F5E9);
    final textColor = isDark ? Colors.green[300]! : Colors.green[800]!;

    if (error != null) {
      return Container(
        color: isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFEBEE),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          'Recall test error: $error',
          style: const TextStyle(fontSize: 12, color: Colors.red),
        ),
      );
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            'Recall@$k ($algorithm): $recall  ($correct/$k matches vs brute-force)',
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }
}

// ── Diagnostics panel ──────────────────────────────────────────────────────────

class _DiagnosticsPanel extends StatelessWidget {
  final int? embeddingTimeMs;
  final int? indexSearchTimeMs;
  final int totalTimeMs;
  final int? memoryDeltaBytes;
  final bool isDark;

  const _DiagnosticsPanel({
    required this.embeddingTimeMs,
    required this.indexSearchTimeMs,
    required this.totalTimeMs,
    required this.memoryDeltaBytes,
    required this.isDark,
  });

  static const _infos = <String, String>{
    'Query time':
        'ONNX inference time for the text query — tokenizing the input and '
        'running a forward pass through the text encoder to produce a 768-dim vector. '
        'The model weights stay loaded; this is just the per-query compute cost.',
    'Index search':
        'Time to scan the ANN index for the nearest neighbors to the query vector. '
        'Brute-force is O(n·d); IVF-PQ and HNSW trade a small accuracy loss for '
        'sub-linear lookup time.',
    'Total time':
        'Wall-clock time from pressing Run to results being ready, including '
        'embedding, index search, result filtering, and thumbnail loading.',
    'Memory (ΔRSS)':
        'Change in process RSS (Resident Set Size) during the search — how much '
        'additional physical RAM was allocated. Near-zero is normal when results '
        'and thumbnails are small. A large positive value may indicate thumbnail '
        'buffering or ORT scratch buffers.',
  };

  String _fmtDelta(int bytes) {
    final sign = bytes >= 0 ? '+' : '−';
    final abs = bytes.abs();
    if (abs >= 1024 * 1024 * 1024) {
      return '$sign${(abs / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (abs >= 1024 * 1024) {
      return '$sign${(abs / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (abs >= 1024) {
      return '$sign${(abs / 1024).toStringAsFixed(0)} KB';
    }
    return '$sign$abs B';
  }

  void _showInfo(BuildContext context, String label) {
    final desc = _infos[label] ?? '';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        content: Text(desc, style: const TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark ? Colors.white38 : Colors.black38;
    final valueColor = isDark ? Colors.white70 : Colors.black87;
    final hintColor = isDark ? Colors.white24 : Colors.black26;
    final bgColor = isDark ? const Color(0xFF1A1F2A) : const Color(0xFFEEF2FF);
    final borderColor =
        isDark ? const Color(0xFF2A3050) : const Color(0xFFBEC8EE);
    final accentColor =
        isDark ? Colors.blueAccent[100]! : Colors.indigo;

    final rows = <(String, String)>[
      ('Query time',    embeddingTimeMs != null ? '${embeddingTimeMs}ms' : '—'),
      ('Index search',  indexSearchTimeMs != null ? '${indexSearchTimeMs}ms' : '—'),
      ('Total time',    '${totalTimeMs}ms'),
      ('Memory (ΔRSS)', memoryDeltaBytes != null ? _fmtDelta(memoryDeltaBytes!) : '—'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Row(
              children: [
                Icon(Icons.speed_outlined, size: 12, color: accentColor),
                const SizedBox(width: 5),
                Text(
                  'DIAGNOSTICS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: accentColor,
                  ),
                ),
                const Spacer(),
                Icon(Icons.touch_app_outlined, size: 11, color: hintColor),
                const SizedBox(width: 3),
                Text(
                  'tap row for info',
                  style: TextStyle(fontSize: 10, color: hintColor),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 10, endIndent: 10),
          // Rows
          ...rows.map((row) {
            return InkWell(
              onTap: () => _showInfo(context, row.$1),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  children: [
                    Text(
                      row.$1,
                      style: TextStyle(fontSize: 11, color: labelColor),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline, size: 10, color: hintColor),
                    const Spacer(),
                    Text(
                      row.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: valueColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;

  const _StatChip({
    required this.label,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white54 : Colors.black54;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final ImageItem image;
  final int rank;
  final double? score;
  final bool isDark;

  const _ResultTile({
    required this.image,
    required this.rank,
    required this.score,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 52,
        height: 52,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: image.thumbnail != null
              ? Image.memory(image.thumbnail!, fit: BoxFit.cover)
              : Image.file(
                  File(image.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image, size: 28),
                ),
        ),
      ),
      title: Text(
        image.name,
        style: const TextStyle(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        image.path,
        style: const TextStyle(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: score != null ? _ScoreBadge(score: score!) : null,
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;

  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    // Kitako INT8 text-image cosine similarity observed range: ~0.08–0.11.
    // Image-image range: ~0.66–1.00 (no modality gap within same encoder).
    final color = score >= 0.10
        ? Colors.green
        : score >= 0.08
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        score.toStringAsFixed(3),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final SearchStatus status;
  final bool isDark;

  const _EmptyPanel({required this.status, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final String message;
    final IconData icon;
    if (status == SearchStatus.idle) {
      message = 'Enter a query and tap Run';
      icon = Icons.search;
    } else if (status == SearchStatus.noResults) {
      message = 'No results found';
      icon = Icons.image_not_supported_outlined;
    } else {
      message = 'Searching…';
      icon = Icons.hourglass_empty;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 48, color: isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;

  const _ErrorPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 18),
              SizedBox(width: 6),
              Text(
                'Error',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            message,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
