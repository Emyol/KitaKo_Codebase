import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;
import '../../models/search_models.dart';
import '../../services/image_loader_service.dart';
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
  bool _switchingDataset = false;
  bool _retrainingIvfpq = false;
  bool _headerVisible = true;

  _SearchMethod _searchMethod = _SearchMethod.bruteForce;

  // ── HNSW tuning state ──
  double _hnswEf = 50;

  // ── IVF-PQ tuning state ──
  bool _ivfAdvancedExpanded = false;
  // Staged values for retrain (committed when the user taps Retrain).
  int? _ivfClustersStaged;
  int? _ivfSubquantizersStaged;
  int? _ivfProbesStaged;
  int? _ivfTrainingItersStaged;

  static const List<int> _validIvfSubquantizers = [8, 12, 16, 24, 32, 48, 64, 96];

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

  // ── IVF-PQ retrain ───────────────────────────────────────────────────────

  Future<void> _retrainIvfpq() async {
    if (_retrainingIvfpq) return;
    setState(() => _retrainingIvfpq = true);
    try {
      final ok = await widget.searchService.retrainIvfpq(
        numClusters: _ivfClustersStaged,
        numSubquantizers: _ivfSubquantizersStaged,
        numProbes: _ivfProbesStaged,
        trainingIterations: _ivfTrainingItersStaged,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'IVF-PQ retrained — staged params applied'
                : 'IVF-PQ retrain failed (need ≥50 indexed images)'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retrainingIvfpq = false);
    }
  }

  // ── Dataset switch ───────────────────────────────────────────────────────

  Future<void> _switchDataset(TestDataset dataset) async {
    if (_switchingDataset) return;
    setState(() => _switchingDataset = true);
    try {
      final ok = await widget.searchService.setActiveDataset(dataset.dirName);
      if (mounted) {
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${dataset.label} dataset not found on disk — '
                'see docs/development/TEST_DATASETS.md',
              ),
            ),
          );
        } else {
          // Re-run last query against the new active dataset, if any.
          if (_queryController.text.trim().isNotEmpty &&
              _lastState.status == SearchStatus.success) {
            _runQuery();
          }
        }
      }
    } finally {
      if (mounted) setState(() => _switchingDataset = false);
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
          if (_headerVisible)
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
                const SizedBox(height: 8),
                // Algorithm selector — 3-button row (face-style)
                _AlgorithmSelector(
                  selected: _searchMethod,
                  onChanged: _applySearchMethod,
                  isDark: isDark,
                ),
                // Conditional tuning panels
                if (_searchMethod == _SearchMethod.hnsw) ...[
                  const SizedBox(height: 10),
                  _HnswTunerPanel(
                    ef: _hnswEf,
                    onChanged: (v) {
                      setState(() => _hnswEf = v);
                      widget.searchService.setHnswEfSearch(v.round());
                    },
                    isDark: isDark,
                  ),
                ],
                if (_searchMethod == _SearchMethod.ivfPq) ...[
                  const SizedBox(height: 10),
                  _IvfpqTunerPanel(
                    activeConfig: widget.searchService.annSearchService
                        .activeIvfpqConfig,
                    indexSize: widget.searchService.indexedImageCount,
                    advancedExpanded: _ivfAdvancedExpanded,
                    onAdvancedToggled: (v) =>
                        setState(() => _ivfAdvancedExpanded = v),
                    stagedClusters: _ivfClustersStaged,
                    stagedSubquantizers: _ivfSubquantizersStaged,
                    stagedProbes: _ivfProbesStaged,
                    stagedTrainingIters: _ivfTrainingItersStaged,
                    onClustersChanged: (v) => setState(() {
                      _ivfClustersStaged = v;
                      if (_ivfProbesStaged != null && _ivfProbesStaged! > v) {
                        _ivfProbesStaged = v;
                      }
                    }),
                    onSubquantizersChanged: (v) =>
                        setState(() => _ivfSubquantizersStaged = v),
                    onProbesChanged: (v) =>
                        setState(() => _ivfProbesStaged = v),
                    onTrainingItersChanged: (v) =>
                        setState(() => _ivfTrainingItersStaged = v),
                    validSubquantizers: _validIvfSubquantizers,
                    onRetrain: _retrainingIvfpq ? null : _retrainIvfpq,
                    isRetraining: _retrainingIvfpq,
                    isDark: isDark,
                  ),
                ],
                const SizedBox(height: 8),
                // Dataset toggle row
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        'Dataset',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _switchingDataset
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: LinearProgressIndicator(),
                            )
                          : _DatasetToggle(
                              activeDirName:
                                  widget.searchService.activeDataset,
                              available:
                                  widget.searchService.availableDatasets,
                              onChanged: _switchDataset,
                              isDark: isDark,
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

          // ── Header toggle strip ─────────────────────────────────────────
          _HeaderToggleStrip(
            visible: _headerVisible,
            onToggle: () => setState(() => _headerVisible = !_headerVisible),
            isDark: isDark,
          ),

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
              imageEp: _embedding.imageEp,
              textEp: _embedding.textEp,
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

// ──────────────────────────────────────────────────────────────────────────
// Algorithm selector — 3-button row (face-branch style adapted to v2 services)
// ──────────────────────────────────────────────────────────────────────────

class _AlgorithmSelector extends StatelessWidget {
  final _SearchMethod selected;
  final ValueChanged<_SearchMethod> onChanged;
  final bool isDark;

  const _AlgorithmSelector({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  static const _options = <_AlgoOption>[
    _AlgoOption(
      method: _SearchMethod.bruteForce,
      label: 'Brute Force',
      description: '100% accurate, O(n)',
      icon: Icons.search,
      color: Colors.green,
    ),
    _AlgoOption(
      method: _SearchMethod.ivfPq,
      label: 'IVF-PQ',
      description: 'Fast approximate',
      icon: Icons.bolt,
      color: Colors.orange,
    ),
    _AlgoOption(
      method: _SearchMethod.hnsw,
      label: 'HNSW',
      description: 'Graph-based (FFI)',
      icon: Icons.hub,
      color: Colors.purple,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _AlgorithmButton(
              option: _options[i],
              isSelected: selected == _options[i].method,
              onTap: () => onChanged(_options[i].method),
              isDark: isDark,
            ),
          ),
        ],
      ],
    );
  }
}

class _AlgoOption {
  final _SearchMethod method;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const _AlgoOption({
    required this.method,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _AlgorithmButton extends StatelessWidget {
  final _AlgoOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _AlgorithmButton({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? option.color.withOpacity(0.15) : base,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? option.color
                : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              option.icon,
              color: isSelected
                  ? option.color
                  : (isDark ? Colors.white60 : Colors.black54),
              size: 18,
            ),
            const SizedBox(height: 4),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? option.color
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            Text(
              option.description,
              style: TextStyle(
                fontSize: 9,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// HNSW tuner — runtime ef slider
// ──────────────────────────────────────────────────────────────────────────

class _HnswTunerPanel extends StatelessWidget {
  final double ef;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _HnswTunerPanel({
    required this.ef,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.hub, size: 14, color: Colors.purple[700]),
                  const SizedBox(width: 4),
                  Text(
                    'HNSW ef Search',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple[700],
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ef = ${ef.round()}',
                  style: const TextStyle(
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('10', style: TextStyle(fontSize: 9, color: Colors.grey)),
              Expanded(
                child: Slider(
                  value: ef.clamp(10, 500),
                  min: 10,
                  max: 500,
                  divisions: 49,
                  activeColor: Colors.purple,
                  label: 'ef = ${ef.round()}',
                  onChanged: onChanged,
                ),
              ),
              const Text('500', style: TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
          Text(
            'Low ef = faster but less accurate. High ef = slower but more accurate.',
            style: TextStyle(fontSize: 9, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// IVF-PQ tuner — staged params + retrain
// ──────────────────────────────────────────────────────────────────────────

class _IvfpqTunerPanel extends StatelessWidget {
  final ann.IvfPqConfig? activeConfig;
  final int indexSize;
  final bool advancedExpanded;
  final ValueChanged<bool> onAdvancedToggled;

  final int? stagedClusters;
  final int? stagedSubquantizers;
  final int? stagedProbes;
  final int? stagedTrainingIters;

  final ValueChanged<int> onClustersChanged;
  final ValueChanged<int> onSubquantizersChanged;
  final ValueChanged<int> onProbesChanged;
  final ValueChanged<int> onTrainingItersChanged;

  final List<int> validSubquantizers;
  final VoidCallback? onRetrain;
  final bool isRetraining;
  final bool isDark;

  const _IvfpqTunerPanel({
    required this.activeConfig,
    required this.indexSize,
    required this.advancedExpanded,
    required this.onAdvancedToggled,
    required this.stagedClusters,
    required this.stagedSubquantizers,
    required this.stagedProbes,
    required this.stagedTrainingIters,
    required this.onClustersChanged,
    required this.onSubquantizersChanged,
    required this.onProbesChanged,
    required this.onTrainingItersChanged,
    required this.validSubquantizers,
    required this.onRetrain,
    required this.isRetraining,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final canTrain = indexSize >= 50;
    final clusters = stagedClusters ?? activeConfig?.numClusters ?? 16;
    final probes = stagedProbes ?? activeConfig?.numProbes ?? clusters;
    final subs = stagedSubquantizers ?? activeConfig?.numSubquantizers ?? 64;
    final iters =
        stagedTrainingIters ?? activeConfig?.trainingIterations ?? 50;

    final dirty = stagedClusters != null ||
        stagedSubquantizers != null ||
        stagedProbes != null ||
        stagedTrainingIters != null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + status chip
          Row(
            children: [
              Icon(Icons.tune, size: 14, color: Colors.orange[700]),
              const SizedBox(width: 4),
              Text(
                'IVF-PQ Configuration',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
              const Spacer(),
              _StatusChip(
                text: activeConfig != null
                    ? 'TRAINED'
                    : (canTrain ? 'NOT TRAINED' : 'NEED 50+ images'),
                color: activeConfig != null
                    ? Colors.green
                    : (canTrain ? Colors.amber : Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // nProbes slider — staged-only (retrain to apply)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'nProbes (search breadth)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$probes / $clusters',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('1', style: TextStyle(fontSize: 9, color: Colors.grey)),
              Expanded(
                child: Slider(
                  value: probes.clamp(1, clusters).toDouble(),
                  min: 1,
                  max: clusters.toDouble(),
                  divisions: clusters > 1 ? clusters - 1 : 1,
                  activeColor: Colors.orange,
                  label: 'nProbes = $probes',
                  onChanged: (v) => onProbesChanged(v.round()),
                ),
              ),
              Text('$clusters', style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
          Text(
            probes >= clusters
                ? '⚠ All clusters probed (= brute force with PQ overhead)'
                : '✓ Probing ${(probes / clusters * 100).toStringAsFixed(0)}% of clusters',
            style: TextStyle(
              fontSize: 9,
              color: probes >= clusters ? Colors.orange : Colors.green[700],
            ),
          ),
          const SizedBox(height: 8),
          // Advanced toggle
          GestureDetector(
            onTap: () => onAdvancedToggled(!advancedExpanded),
            child: Row(
              children: [
                Icon(
                  advancedExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.orange[700],
                ),
                Text(
                  'Advanced settings',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (advancedExpanded) ...[
            const SizedBox(height: 6),
            Text(
              'Clusters (IVF partitions)',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [8, 16, 32, 64, 128, 256].map((n) {
                final isSelected = clusters == n;
                return ChoiceChip(
                  label: Text('$n', style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  selectedColor: Colors.orange,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (sel) {
                    if (sel) onClustersChanged(n);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Sub-quantizers: ',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    value: validSubquantizers.contains(subs) ? subs : 64,
                    isExpanded: true,
                    isDense: true,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    items: validSubquantizers.map((n) {
                      return DropdownMenuItem(
                        value: n,
                        child: Text(
                          '$n subs (${768 ~/ n} dims/sub)',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) onSubquantizersChanged(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Training iterations',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                Text(
                  '$iters',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              value: iters.clamp(5, 100).toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              activeColor: Colors.orange,
              label: '$iters iters',
              onChanged: (v) => onTrainingItersChanged(v.round()),
            ),
          ],
          const SizedBox(height: 8),
          // Retrain button — only enabled when staged params differ
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: isRetraining
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 14),
              label: Text(
                isRetraining
                    ? 'Retraining…'
                    : (dirty
                        ? 'Apply staged params (retrain)'
                        : 'Retrain with current params'),
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: canTrain ? onRetrain : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Compact dataset selector for the alpha screen. Renders a `SegmentedButton`
/// over the two known test datasets; missing-on-disk datasets render disabled.
class _DatasetToggle extends StatelessWidget {
  final String? activeDirName;
  final Set<String> available;
  final ValueChanged<TestDataset> onChanged;
  final bool isDark;

  const _DatasetToggle({
    required this.activeDirName,
    required this.available,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (TestDataset.all.every((d) => !available.contains(d.dirName))) {
      return Text(
        'No test datasets found',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      );
    }

    final selected = <TestDataset>{
      for (final d in TestDataset.all)
        if (d.dirName == activeDirName) d,
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<TestDataset>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
        ),
        segments: TestDataset.all.map((d) {
          final present = available.contains(d.dirName);
          return ButtonSegment<TestDataset>(
            value: d,
            label: Text(present ? d.label : '${d.label} (missing)'),
            enabled: present,
          );
        }).toList(),
        selected: selected,
        emptySelectionAllowed: true,
        onSelectionChanged: (sel) {
          if (sel.isNotEmpty) onChanged(sel.first);
        },
      ),
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
  final String imageEp;
  final String textEp;
  final bool isDark;

  const _DiagnosticsPanel({
    required this.embeddingTimeMs,
    required this.indexSearchTimeMs,
    required this.totalTimeMs,
    required this.memoryDeltaBytes,
    required this.imageEp,
    required this.textEp,
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
    'Vision EP':
        'Execution provider active for the image encoder. '
        'nnapi = Android neural-net accelerator, coreml = Apple ML, '
        'xnnpack = optimised CPU (SIMD), cpu = plain ONNX CPU fallback.',
    'Text EP':
        'Execution provider active for the text encoder. '
        'Same options as Vision EP — the two encoders may land on different backends '
        'if the hardware accelerator rejects a particular graph.',
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
      ('Vision EP',     imageEp),
      ('Text EP',       textEp),
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
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _FullImageViewer(image: image),
      ),
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

// ── Header toggle strip ────────────────────────────────────────────────────────

class _HeaderToggleStrip extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;
  final bool isDark;

  const _HeaderToggleStrip({
    required this.visible,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        height: 22,
        color: isDark ? const Color(0xFF141414) : const Color(0xFFECECEC),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              visible ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(width: 4),
            Text(
              visible ? 'Hide settings' : 'Show settings',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full image viewer ──────────────────────────────────────────────────────────

class _FullImageViewer extends StatelessWidget {
  final ImageItem image;

  const _FullImageViewer({required this.image});

  @override
  Widget build(BuildContext context) {
    final imageWidget = image.thumbnail != null
        ? Image.memory(image.thumbnail!, fit: BoxFit.contain)
        : Image.file(
            File(image.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 64),
          );

    return Dialog(
      backgroundColor: Colors.black87,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 8.0,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: imageWidget,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 12,
            right: 48,
            child: Text(
              image.name,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
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
