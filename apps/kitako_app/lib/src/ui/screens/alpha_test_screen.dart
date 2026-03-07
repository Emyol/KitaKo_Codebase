import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:kitako_ann/kitako_ann.dart' as ann;
import 'package:kitako_ffi/kitako_ffi.dart' as ffi;
import 'package:image_picker/image_picker.dart';
import '../../services/image_search_service.dart';
import '../../models/search_models.dart';
import 'details_screen.dart';

/// Search algorithm options for alpha testing
enum SearchAlgorithm {
  /// Brute force - exact search, O(n) but 100% accurate
  bruteForce,
  
  /// IVF-PQ - Inverted File with Product Quantization
  /// Fast approximate search with configurable accuracy
  ivfPq,
  
  /// HNSW - Hierarchical Navigable Small World
  /// Graph-based approximate search using native FFI
  hnsw,
}

/// Alpha Testing Screen for Thesis Evaluation
///
/// This screen is designed for subjective alpha testing of different SigLIP models
/// with brute force search for accurate comparison.
///
/// Features:
/// - Model selection (SigLIP-1, SigLIP-2)
/// - Forced brute-force search (100% accuracy, no ANN approximation)
/// - Text-to-image and image-to-image search
/// - Detailed similarity scores for ranked results
/// - Search latency measurements
/// - Side-by-side comparison support
class AlphaTestScreen extends StatefulWidget {
  final ImageSearchService searchService;

  const AlphaTestScreen({super.key, required this.searchService});

  @override
  State<AlphaTestScreen> createState() => _AlphaTestScreenState();
}

class _AlphaTestScreenState extends State<AlphaTestScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Search state
  List<SearchResultWithScore> _results = [];
  bool _isSearching = false;
  bool _isInitializing = false;
  String? _errorMessage;
  
  // Timing metrics
  int _embeddingTimeMs = 0;
  int _searchTimeMs = 0;
  int _totalTimeMs = 0;
  String _lastQuery = '';
  
  // Model state
  late SiglipModelVersion _currentModel;
  late SiglipModelConfig? _currentConfig;
  int _indexedImageCount = 0;
  
  // Search algorithm selection
  SearchAlgorithm _selectedAlgorithm = SearchAlgorithm.bruteForce;
  
  // HNSW state
  ann.HnswAnnIndex? _hnswIndex;
  bool _hnswAvailable = false;
  bool _hnswReady = false;
  bool _hnswBuilding = false;
  
  // HNSW ef parameter (accuracy vs speed tradeoff)
  double _hnswEf = 100;
  
  // Last HNSW search metrics
  int _lastDistComps = 0;
  int _lastHops = 0;
  int _lastEfUsed = 0;
  
  // IVF-PQ tuning parameters
  int _ivfNumClusters = 32;
  int _ivfNumSubquantizers = 48;
  int _ivfNumProbes = 8;
  int _ivfTrainingIters = 25;
  bool _ivfRetraining = false;
  bool _ivfAdvancedExpanded = false;
  
  // IVF-PQ last search metrics
  int _lastIvfClustersProbed = 0;
  int _lastIvfDistComps = 0;
  int _lastIvfTotalCandidates = 0;
  int _lastIvfNumProbes = 0;
  int _lastIvfTotalVectors = 0;
  
  // Test history for comparison
  final List<TestResult> _testHistory = [];

  @override
  void initState() {
    super.initState();
    _currentModel = widget.searchService.embeddingService.modelVersion;
    _currentConfig = widget.searchService.embeddingService.modelConfig;
    _indexedImageCount = widget.searchService.getAllImages().length;
    _checkHnswAvailability();
    _initIvfPqParams();
  }
  
  /// Initialize IVF-PQ tuning parameters from current service config
  void _initIvfPqParams() {
    final config = widget.searchService.annSearchService.currentConfig;
    _ivfNumClusters = config.numClusters;
    _ivfNumSubquantizers = config.numSubquantizers;
    _ivfNumProbes = config.numProbes;
    _ivfTrainingIters = config.trainingIterations;
  }
  
  /// Check if HNSW native library is available
  void _checkHnswAvailability() {
    try {
      final ffiInstance = ffi.KitakoFfi();
      _hnswAvailable = ffiInstance.isAnnAvailable;
      debugPrint('HNSW available: $_hnswAvailable');
    } catch (e) {
      _hnswAvailable = false;
      debugPrint('HNSW not available: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _hnswIndex?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alpha Testing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'View Test History',
            onPressed: _showTestHistory,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Results',
            onPressed: _exportResults,
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Model Info Card
          SliverToBoxAdapter(
            child: _buildModelInfoCard(isDark, textColor, cardColor, borderColor),
          ),
          
          // Search Input Section
          SliverToBoxAdapter(
            child: _buildSearchSection(isDark, textColor, cardColor, borderColor),
          ),
          
          // Search Metrics
          if (_totalTimeMs > 0)
            SliverToBoxAdapter(
              child: _buildMetricsCard(isDark, textColor, cardColor, borderColor),
            ),
          
          // Results List
          _buildResultsSliver(isDark, textColor, cardColor, borderColor),
        ],
      ),
    );
  }

  Widget _buildModelInfoCard(bool isDark, Color textColor, Color cardColor, Color borderColor) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _currentModel == SiglipModelVersion.finetunedSiglip
                        ? Icons.auto_awesome
                        : _currentModel == SiglipModelVersion.siglip2 
                            ? Icons.star 
                            : Icons.speed,
                    color: _currentModel == SiglipModelVersion.finetunedSiglip
                        ? Colors.deepPurple
                        : _currentModel == SiglipModelVersion.siglip2 
                            ? Colors.amber 
                            : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentModel == SiglipModelVersion.finetunedSiglip
                        ? 'Model: FINE-TUNED'
                        : 'Model: ${_currentModel.name.toUpperCase()}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Switch'),
                onPressed: _isSearching ? null : _switchModel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildChip('${_currentConfig?.imageSize ?? 224}×${_currentConfig?.imageSize ?? 224}', Icons.image, isDark),
              _buildChip('${_currentConfig?.vocabularySize ?? 32000} tokens', Icons.text_fields, isDark),
              _buildChip('$_indexedImageCount images', Icons.photo_library, isDark),
            ],
          ),
          const SizedBox(height: 12),
          // Search Algorithm Selector
          _buildAlgorithmSelector(isDark, textColor, cardColor, borderColor),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, bool isDark, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight 
            ? Colors.green.withOpacity(0.2) 
            : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5)),
        borderRadius: BorderRadius.circular(16),
        border: isHighlight ? Border.all(color: Colors.green, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isHighlight ? Colors.green : Colors.grey),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isHighlight ? Colors.green : Colors.grey,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlgorithmSelector(bool isDark, Color textColor, Color cardColor, Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Search Algorithm',
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Build HNSW button (only if not ready yet)
            if (_hnswAvailable && !_hnswReady && !_hnswBuilding)
              TextButton.icon(
                icon: const Icon(Icons.build, size: 14),
                label: const Text('Build HNSW', style: TextStyle(fontSize: 11)),
                onPressed: _buildHnswIndex,
              ),
            if (_hnswBuilding)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildAlgorithmOption(
                algorithm: SearchAlgorithm.bruteForce,
                label: 'Brute Force',
                description: '100% accurate, O(n)',
                icon: Icons.search,
                color: Colors.green,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildAlgorithmOption(
                algorithm: SearchAlgorithm.ivfPq,
                label: 'IVF-PQ',
                description: 'Fast approximate',
                icon: Icons.bolt,
                color: Colors.orange,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildAlgorithmOption(
                algorithm: SearchAlgorithm.hnsw,
                label: 'HNSW',
                description: 'Graph-based (FFI)',
                icon: Icons.hub,
                color: Colors.purple,
                isDark: isDark,
              ),
            ),
          ],
        ),
        // HNSW ef slider (only visible when HNSW is selected and ready)
        if (_selectedAlgorithm == SearchAlgorithm.hnsw && _hnswReady) ...[
          const SizedBox(height: 12),
          _buildEfSlider(isDark, textColor),
        ],
        // HNSW diagnostic button (only visible when HNSW is ready)
        if (_hnswReady) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.analytics, size: 14),
                  label: const Text('HNSW vs Brute Force Diagnostic', style: TextStyle(fontSize: 11)),
                  onPressed: _isSearching ? null : _runHnswDiagnostic,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
        // Last HNSW metrics display
        if (_selectedAlgorithm == SearchAlgorithm.hnsw && _lastDistComps > 0) ...[
          const SizedBox(height: 8),
          _buildHnswMetrics(isDark, textColor),
        ],
        // IVF-PQ tuner (only visible when IVF-PQ is selected)
        if (_selectedAlgorithm == SearchAlgorithm.ivfPq) ...[
          const SizedBox(height: 12),
          _buildIvfPqTuner(isDark, textColor),
        ],
        // IVF-PQ diagnostic button
        if (_selectedAlgorithm == SearchAlgorithm.ivfPq && widget.searchService.annSearchService.isReady) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.analytics, size: 14),
                  label: const Text('IVF-PQ vs Brute Force Diagnostic', style: TextStyle(fontSize: 11)),
                  onPressed: _isSearching || _ivfRetraining ? null : _runIvfPqDiagnostic,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
        // IVF-PQ metrics display
        if (_selectedAlgorithm == SearchAlgorithm.ivfPq && _lastIvfDistComps > 0) ...[
          const SizedBox(height: 8),
          _buildIvfPqMetrics(isDark, textColor),
        ],
      ],
    );
  }

  Widget _buildEfSlider(bool isDark, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ef Search Parameter',
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'ef = ${_hnswEf.round()}',
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
                value: _hnswEf,
                min: 10,
                max: 500,
                divisions: 49,
                activeColor: Colors.purple,
                label: 'ef = ${_hnswEf.round()}',
                onChanged: (value) {
                  setState(() => _hnswEf = value);
                  _hnswIndex?.setEfSearch(value.round());
                },
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
    );
  }

  Widget _buildHnswMetrics(bool isDark, Color textColor) {
    final totalVectors = _hnswIndex?.size ?? 0;
    final isApproximate = _lastDistComps > 0 && _lastDistComps < totalVectors;
    final pctSearched = totalVectors > 0
        ? (_lastDistComps / totalVectors * 100).toStringAsFixed(1)
        : '?';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isApproximate
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isApproximate
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isApproximate ? Icons.check_circle : Icons.warning,
                size: 14,
                color: isApproximate ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                isApproximate
                    ? 'TRUE APPROXIMATE SEARCH'
                    : 'EFFECTIVELY BRUTE FORCE',
                style: TextStyle(
                fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isApproximate ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Distance computations: $_lastDistComps / $totalVectors ($pctSearched% of index)',
            style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
          ),
          Text(
            'Graph hops: $_lastHops | ef used: $_lastEfUsed | Layers: ${_hnswIndex?.getMaxLevel() ?? "?"}',
            style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  // ========== IVF-PQ Tuner Widgets ==========

  /// Valid numSubquantizers for 768-dimensional vectors
  static const List<int> _validSubquantizers = [8, 12, 16, 24, 32, 48, 64, 96];

  Widget _buildIvfPqTuner(bool isDark, Color textColor) {
    final isReady = widget.searchService.annSearchService.isReady;
    final totalImages = widget.searchService.annSearchService.indexSize;
    final minForTraining = widget.searchService.annSearchService.minVectorsForTraining;
    final canTrain = totalImages >= minForTraining;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
              if (isReady)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('TRAINED', style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
                ),
              if (!isReady && canTrain)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('NOT TRAINED', style: TextStyle(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.bold)),
                ),
              if (!canTrain)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('NEED $minForTraining+ images', style: const TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // nProbes slider (runtime adjustable)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('nProbes (search breadth)', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.7), fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('$_ivfNumProbes / $_ivfNumClusters', style: TextStyle(color: Colors.orange[700], fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          Row(
            children: [
              const Text('1', style: TextStyle(fontSize: 9, color: Colors.grey)),
              Expanded(
                child: Slider(
                  value: _ivfNumProbes.toDouble(),
                  min: 1,
                  max: _ivfNumClusters.toDouble(),
                  divisions: _ivfNumClusters - 1 > 0 ? _ivfNumClusters - 1 : 1,
                  activeColor: Colors.orange,
                  label: 'nProbes = $_ivfNumProbes',
                  onChanged: (value) {
                    setState(() => _ivfNumProbes = value.round());
                    widget.searchService.annSearchService.setNumProbes(value.round());
                  },
                ),
              ),
              Text('$_ivfNumClusters', style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          ),
          Text(
            _ivfNumProbes == _ivfNumClusters
                ? '⚠ Searching ALL clusters (100%) = brute force with PQ overhead'
                : '✓ Searching ${(_ivfNumProbes / _ivfNumClusters * 100).toStringAsFixed(0)}% of clusters',
            style: TextStyle(fontSize: 9, color: _ivfNumProbes == _ivfNumClusters ? Colors.orange : Colors.green[700]),
          ),
          const SizedBox(height: 8),
          // Advanced settings (expandable)
          GestureDetector(
            onTap: () => setState(() => _ivfAdvancedExpanded = !_ivfAdvancedExpanded),
            child: Row(
              children: [
                Icon(
                  _ivfAdvancedExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.orange[700],
                ),
                Text(
                  'Advanced Settings (requires retrain)',
                  style: TextStyle(fontSize: 11, color: Colors.orange[700], fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (_ivfAdvancedExpanded) ...[
            const SizedBox(height: 8),
            // numClusters preset buttons
            Text('Clusters (IVF partitions)', style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [8, 16, 32, 64, 128, 256].map((n) {
                final isSelected = _ivfNumClusters == n;
                return ChoiceChip(
                  label: Text('$n', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : null)),
                  selected: isSelected,
                  selectedColor: Colors.orange,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _ivfNumClusters = n;
                        if (_ivfNumProbes > n) _ivfNumProbes = n;
                      });
                    }
                  },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // numSubquantizers dropdown
            Row(
              children: [
                Text('Sub-quantizers: ', style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6))),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    value: _validSubquantizers.contains(_ivfNumSubquantizers)
                        ? _ivfNumSubquantizers
                        : 48,
                    isExpanded: true,
                    isDense: true,
                    style: TextStyle(fontSize: 12, color: textColor),
                    items: _validSubquantizers.map((n) {
                      final dimsPerSub = 768 ~/ n;
                      return DropdownMenuItem(
                        value: n,
                        child: Text('$n subs ($dimsPerSub dims/sub)', style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _ivfNumSubquantizers = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Training iterations slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Training iterations', style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6))),
                Text('$_ivfTrainingIters', style: TextStyle(fontSize: 11, color: Colors.orange[700], fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: _ivfTrainingIters.toDouble(),
              min: 10,
              max: 100,
              divisions: 18,
              activeColor: Colors.orange,
              label: '$_ivfTrainingIters iters',
              onChanged: (value) => setState(() => _ivfTrainingIters = value.round()),
            ),
            const SizedBox(height: 4),
            // Train / Retrain button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _ivfRetraining
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.model_training, size: 16),
                label: Text(
                  _ivfRetraining
                      ? 'Training...'
                      : isReady
                          ? 'Retrain with Settings'
                          : 'Train IVF-PQ Index',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: (!canTrain || _ivfRetraining) ? null : _retrainIvfPq,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (!canTrain)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Need at least $minForTraining indexed images to train. Currently: $totalImages.',
                  style: const TextStyle(fontSize: 9, color: Colors.red),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildIvfPqMetrics(bool isDark, Color textColor) {
    final isApproximate = _lastIvfDistComps > 0 && _lastIvfDistComps < _lastIvfTotalVectors;
    final pctSearched = _lastIvfTotalVectors > 0
        ? (_lastIvfDistComps / _lastIvfTotalVectors * 100).toStringAsFixed(1)
        : '?';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isApproximate
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isApproximate
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isApproximate ? Icons.check_circle : Icons.warning,
                size: 14,
                color: isApproximate ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 4),
              Text(
                isApproximate
                    ? 'TRUE APPROXIMATE SEARCH'
                    : 'EXHAUSTIVE (ALL VECTORS CHECKED)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isApproximate ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Clusters probed: $_lastIvfClustersProbed / ${widget.searchService.annSearchService.currentConfig.numClusters}',
            style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
          ),
          Text(
            'Distance computations: $_lastIvfDistComps / $_lastIvfTotalVectors ($pctSearched%)',
            style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
          ),
          Text(
            'nProbes used: $_lastIvfNumProbes | Candidates in probed clusters: $_lastIvfTotalCandidates',
            style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlgorithmOption({
    required SearchAlgorithm algorithm,
    required String label,
    required String description,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _selectedAlgorithm == algorithm;
    final isIvfPqReady = widget.searchService.annSearchService.isReady;
    
    // Determine if this option is disabled
    bool isDisabled = false;
    String disabledReason = description;
    
    if (algorithm == SearchAlgorithm.ivfPq && !isIvfPqReady) {
      // IVF-PQ can be selected to access tuner even if not trained
      isDisabled = false;
      disabledReason = 'Configure & train';
    } else if (algorithm == SearchAlgorithm.hnsw) {
      if (!_hnswAvailable) {
        isDisabled = true;
        disabledReason = 'FFI not available';
      } else if (!_hnswReady) {
        isDisabled = true;
        disabledReason = 'Build index first';
      }
    }
    
    return GestureDetector(
      onTap: isDisabled || _isSearching
          ? null
          : () => setState(() => _selectedAlgorithm = algorithm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.15)
              : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? color : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: isSelected ? color : Colors.grey[600],
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, size: 14, color: color),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isDisabled ? disabledReason : description,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection(bool isDark, Color textColor, Color cardColor, Color borderColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          // Text search field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Enter search query (e.g., "sunset beach", "red car")...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _performTextSearch(),
          ),
          const SizedBox(height: 12),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _isSearching 
                      ? const SizedBox(
                          width: 16, 
                          height: 16, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search),
                  label: Text(_isSearching ? 'Searching...' : 'Text Search'),
                  onPressed: _isSearching || _searchController.text.trim().isEmpty
                      ? null
                      : _performTextSearch,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.image_search),
                  label: const Text('Image Search'),
                  onPressed: _isSearching ? null : _performImageSearch,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard(bool isDark, Color textColor, Color cardColor, Color borderColor) {
    final algorithmName = switch (_selectedAlgorithm) {
      SearchAlgorithm.bruteForce => 'Brute Force',
      SearchAlgorithm.ivfPq => 'IVF-PQ',
      SearchAlgorithm.hnsw => 'HNSW',
    };
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2A1A) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricItem('Query', '"$_lastQuery"', Icons.text_snippet),
          _buildMetricItem('Algorithm', algorithmName, Icons.account_tree),
          _buildMetricItem('Embedding', '${_embeddingTimeMs}ms', Icons.memory),
          _buildMetricItem('Search', '${_searchTimeMs}ms', Icons.search),
          _buildMetricItem('Total', '${_totalTimeMs}ms', Icons.timer),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.green),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// Build results as a sliver for the CustomScrollView
  Widget _buildResultsSliver(bool isDark, Color textColor, Color cardColor, Color borderColor) {
    if (_isInitializing) {
      return const SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing model...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _errorMessage = null),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty && !_isSearching) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Alpha Testing Mode',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Enter a search query to test ${_currentModel.name.toUpperCase()} '
                  'with brute force search.\n\n'
                  'Results will show similarity scores for subjective evaluation.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                children: [
                  _buildSuggestedQuery('sunset'),
                  _buildSuggestedQuery('beach'),
                  _buildSuggestedQuery('food'),
                  _buildSuggestedQuery('selfie'),
                  _buildSuggestedQuery('dog'),
                  _buildSuggestedQuery('car'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_isSearching) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final result = _results[index];
            return _buildResultItem(result, index, isDark, textColor, cardColor, borderColor);
          },
          childCount: _results.length,
        ),
      ),
    );
  }

  Widget _buildSuggestedQuery(String query) {
    return ActionChip(
      label: Text(query),
      onPressed: () {
        _searchController.text = query;
        _performTextSearch();
      },
    );
  }

  Widget _buildResultItem(
    SearchResultWithScore result,
    int index,
    bool isDark,
    Color textColor,
    Color cardColor,
    Color borderColor,
  ) {
    final rank = index + 1;
    final isTopResult = index == 0;
    final similarityPercent = (result.similarity * 100).toStringAsFixed(2);
    
    // Color code by similarity
    Color scoreColor;
    if (result.similarity >= 0.3) {
      scoreColor = Colors.green;
    } else if (result.similarity >= 0.2) {
      scoreColor = Colors.orange;
    } else if (result.similarity >= 0.1) {
      scoreColor = Colors.amber;
    } else {
      scoreColor = Colors.grey;
    }

    return GestureDetector(
      onTap: () => _openImageDetails(result.image),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isTopResult ? Colors.green : borderColor,
            width: isTopResult ? 2 : 1,
          ),
          boxShadow: isTopResult
              ? [BoxShadow(color: Colors.green.withOpacity(0.2), blurRadius: 8)]
              : null,
        ),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isTopResult 
                    ? Colors.green 
                    : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isTopResult ? Colors.white : textColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: result.image.thumbnail != null
                  ? Image.memory(
                      result.image.thumbnail!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[300],
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
            ),
            const SizedBox(width: 12),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.image.name,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${result.image.width ?? '?'}×${result.image.height ?? '?'}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            
            // Similarity score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scoreColor.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$similarityPercent%',
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'similarity',
                    style: TextStyle(
                      color: scoreColor.withOpacity(0.8),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== Actions ==========

  /// Build HNSW index from current embeddings
  Future<void> _buildHnswIndex() async {
    if (_hnswBuilding || !_hnswAvailable) return;
    
    setState(() => _hnswBuilding = true);
    
    try {
      // Get all image embeddings from the ANNSearchService
      final allEmbeddings = widget.searchService.annSearchService.getAllEmbeddings();
      
      if (allEmbeddings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No embeddings available to build HNSW index')),
        );
        setState(() => _hnswBuilding = false);
        return;
      }
      
      debugPrint('Building HNSW index with ${allEmbeddings.length} vectors...');
      
      // Create HNSW index with SigLIP-768 config
      _hnswIndex = ann.HnswAnnIndex.siglip768(maxElements: allEmbeddings.length + 1000);
      await _hnswIndex!.initialize();
      
      // Add all vectors
      int id = 0;
      for (final entry in allEmbeddings.entries) {
        await _hnswIndex!.addVector(entry.value, id);
        id++;
      }
      
      setState(() {
        _hnswReady = true;
        _hnswBuilding = false;
      });
      
      debugPrint('HNSW index built with $id vectors');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('HNSW index built with $id vectors')),
        );
      }
    } catch (e) {
      debugPrint('Failed to build HNSW index: $e');
      setState(() => _hnswBuilding = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to build HNSW: $e')),
        );
      }
    }
  }
  
  /// Run comprehensive diagnostic comparing HNSW vs Brute Force
  Future<void> _runHnswDiagnostic() async {
    if (_hnswIndex == null || !_hnswReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Build HNSW index first')),
      );
      return;
    }
    
    setState(() => _isSearching = true);
    
    try {
      // Use a test query - either from search box or default
      final query = _searchController.text.trim().isEmpty ? 'sunset' : _searchController.text.trim();
      
      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════╗');
      debugPrint('║        HNSW DIAGNOSTIC COMPARISON            ║');
      debugPrint('╠══════════════════════════════════════════════╣');
      debugPrint('║ Query: "$query"');
      debugPrint('║ Index size: ${_hnswIndex!.size} vectors');
      debugPrint('╚══════════════════════════════════════════════╝');
      
      // Generate embedding for query
      final embedding = await widget.searchService.embeddingService.generateEmbedding(query);
      final float32Embedding = Float32List.fromList(embedding);
      const int k = 20;
      
      // 1. Brute Force baseline
      final bfStopwatch = Stopwatch()..start();
      final bfResults = await widget.searchService.annSearchService.searchSimilarWithScores(
        embedding, k: k, forceBruteForce: true,
      );
      bfStopwatch.stop();
      final bfIds = bfResults.map((r) => r.image.id).toList();
      
      // 2. HNSW at different ef values
      final diagnosticResults = <Map<String, dynamic>>[];
      
      for (final ef in [10, 20, 50, 100, 200, 500]) {
        _hnswIndex!.setEfSearch(ef);
        
        final sw = Stopwatch()..start();
        final metrics = await _hnswIndex!.searchWithMetrics(float32Embedding, k);
        sw.stop();
        
        // Convert HNSW results to image IDs for recall calculation
        final allEmbeddings = widget.searchService.annSearchService.getAllEmbeddings();
        final imageIds = allEmbeddings.keys.toList();
        
        final hnswImageIds = <String>[];
        for (final result in metrics.results) {
          if (result.id >= 0 && result.id < imageIds.length) {
            hnswImageIds.add(imageIds[result.id]);
          }
        }
        
        // Calculate recall@k
        final bfIdSet = bfIds.take(k).toSet();
        final hnswIdSet = hnswImageIds.take(k).toSet();
        final recall = bfIdSet.isEmpty ? 0.0 : bfIdSet.intersection(hnswIdSet).length / bfIdSet.length;
        
        diagnosticResults.add({
          'ef': ef,
          'timeMs': sw.elapsedMilliseconds,
          'distComps': metrics.distanceComputations,
          'hops': metrics.hops,
          'recall': recall,
          'pctSearched': (metrics.distanceComputations / _hnswIndex!.size * 100),
        });
        
        debugPrint('ef=$ef: ${sw.elapsedMilliseconds}ms, '
            'distComps=${metrics.distanceComputations}/${_hnswIndex!.size} '
            '(${(metrics.distanceComputations / _hnswIndex!.size * 100).toStringAsFixed(1)}%), '
            'recall@$k=${(recall * 100).toStringAsFixed(1)}%');
      }
      
      // Restore user's ef setting
      _hnswIndex!.setEfSearch(_hnswEf.round());
      
      setState(() => _isSearching = false);
      
      // Show results dialog
      if (mounted) {
        _showDiagnosticResults(query, k, bfStopwatch.elapsedMilliseconds, diagnosticResults);
      }
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostic failed: $e')),
        );
      }
    }
  }

  /// Show diagnostic results in a dialog
  void _showDiagnosticResults(String query, int k, int bfTimeMs, List<Map<String, dynamic>> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('HNSW vs Brute Force'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Query: "$query"', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Index: ${_hnswIndex!.size} vectors, ${_hnswIndex!.getMaxLevel() + 1} graph layers'),
                Text('Brute Force: ${bfTimeMs}ms (${_hnswIndex!.size} distance computations)'),
                const Divider(),
                const Text('HNSW Results by ef:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Table header
                Row(
                  children: const [
                    Expanded(flex: 2, child: Text('ef', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 2, child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 3, child: Text('Dist Comps', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 2, child: Text('% Index', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 2, child: Text('Recall', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                  ],
                ),
                const Divider(height: 8),
                ...results.map((r) {
                  final isApprox = r['distComps'] < _hnswIndex!.size;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('${r['ef']}', style: const TextStyle(fontSize: 11))),
                        Expanded(flex: 2, child: Text('${r['timeMs']}ms', style: const TextStyle(fontSize: 11))),
                        Expanded(flex: 3, child: Text('${r['distComps']}', style: TextStyle(fontSize: 11, color: isApprox ? Colors.green : Colors.orange))),
                        Expanded(flex: 2, child: Text('${(r['pctSearched'] as double).toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, color: isApprox ? Colors.green : Colors.orange))),
                        Expanded(flex: 2, child: Text('${((r['recall'] as double) * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11))),
                      ],
                    ),
                  );
                }),
                const Divider(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'If "Dist Comps" < total vectors at low ef, HNSW is truly doing '
                    'approximate search. If it equals total vectors, the graph is too dense '
                    'for the dataset size and HNSW effectively becomes brute force.\n\n'
                    'For small datasets (<5000), this is expected. HNSW shines on larger datasets.',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ========== IVF-PQ Action Methods ==========

  /// Retrain IVF-PQ index with current tuner settings
  Future<void> _retrainIvfPq() async {
    setState(() => _ivfRetraining = true);

    try {
      final config = ann.IvfPqConfig(
        dimension: 768,
        numClusters: _ivfNumClusters,
        numSubquantizers: _ivfNumSubquantizers,
        numCentroidsPerSubquantizer: 256,
        numProbes: _ivfNumProbes,
        trainingIterations: _ivfTrainingIters,
      );

      debugPrint('IVF-PQ Retrain: Starting with config');
      debugPrint('  clusters=$_ivfNumClusters, subs=$_ivfNumSubquantizers, '
          'probes=$_ivfNumProbes, iters=$_ivfTrainingIters');

      final stopwatch = Stopwatch()..start();
      final success = await widget.searchService.annSearchService.retrainWithConfig(config);
      stopwatch.stop();

      if (success) {
        setState(() {
          _ivfRetraining = false;
          _lastIvfDistComps = 0; // Reset metrics
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('IVF-PQ trained in ${stopwatch.elapsedMilliseconds}ms'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _ivfRetraining = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Training failed - not enough images'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _ivfRetraining = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Training error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Search using IVF-PQ with metrics tracking
  Future<List<SearchResultWithScore>> _searchWithIvfPq(List<double> embedding, int k) async {
    final annService = widget.searchService.annSearchService;

    if (!annService.isReady) {
      // Fall back to brute force if IVF-PQ not trained
      debugPrint('IVF-PQ: Not ready, falling back to brute force');
      return annService.searchSimilarWithScores(embedding, k: k, forceBruteForce: true);
    }

    debugPrint('========== IVF-PQ SEARCH ==========');
    debugPrint('IVF-PQ: nProbes = $_ivfNumProbes');

    final metricsResult = await annService.searchWithIvfPqMetrics(
      embedding,
      k: k,
      numProbes: _ivfNumProbes,
    );

    if (metricsResult == null) {
      debugPrint('IVF-PQ: searchWithMetrics returned null, falling back');
      return annService.searchSimilarWithScores(embedding, k: k, forceBruteForce: true);
    }

    // Capture metrics for UI display
    _lastIvfClustersProbed = metricsResult.clustersProbed;
    _lastIvfDistComps = metricsResult.distanceComputations;
    _lastIvfTotalCandidates = metricsResult.totalCandidates;
    _lastIvfNumProbes = metricsResult.numProbesUsed;
    _lastIvfTotalVectors = metricsResult.totalVectors;

    final total = metricsResult.totalVectors;
    final pct = total > 0 ? (metricsResult.distanceComputations / total * 100).toStringAsFixed(1) : '?';

    debugPrint('IVF-PQ: Clusters probed: ${metricsResult.clustersProbed}');
    debugPrint('IVF-PQ: Distance computations: ${metricsResult.distanceComputations} / $total ($pct%)');
    debugPrint('IVF-PQ: Results: ${metricsResult.results.length}');
    debugPrint('===================================');

    return metricsResult.results;
  }

  /// Run IVF-PQ diagnostic: compare different nProbes vs brute force
  Future<void> _runIvfPqDiagnostic() async {
    if (!widget.searchService.annSearchService.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IVF-PQ not trained yet')),
      );
      return;
    }

    // Use a common query for comparison
    final query = _searchController.text.trim().isEmpty
        ? 'photo of a person'
        : _searchController.text.trim();

    setState(() => _isSearching = true);

    try {
      // Generate query embedding
      final embedding = await widget.searchService.embeddingService.generateEmbedding(query);
      final annService = widget.searchService.annSearchService;
      final numClusters = annService.currentConfig.numClusters;

      // Get brute force ground truth
      final bfStopwatch = Stopwatch()..start();
      final bfResults = await annService.searchSimilarWithScores(
        embedding, k: 20, forceBruteForce: true,
      );
      bfStopwatch.stop();
      final bfIds = bfResults.map((r) => r.image.id).toSet();
      final bfTimeMs = bfStopwatch.elapsedMilliseconds;

      // Test different nProbe values
      final probeValues = <int>[];
      // Generate a spread of probe values up to numClusters
      for (final p in [1, 2, 4, 8, 12, 16, 24, 32, 48, 64, 128, 256]) {
        if (p <= numClusters) probeValues.add(p);
      }
      if (!probeValues.contains(numClusters)) probeValues.add(numClusters);

      final results = <Map<String, dynamic>>[];

      for (final nprobes in probeValues) {
        final sw = Stopwatch()..start();
        final metrics = await annService.searchWithIvfPqMetrics(
          embedding, k: 20, numProbes: nprobes,
        );
        sw.stop();

        if (metrics == null) continue;

        final ivfIds = metrics.results.map((r) => r.image.id).toSet();
        final recall = bfIds.isEmpty ? 0.0 : bfIds.intersection(ivfIds).length / bfIds.length;
        final pctSearched = metrics.totalVectors > 0
            ? metrics.distanceComputations / metrics.totalVectors * 100.0
            : 0.0;

        results.add({
          'nProbes': nprobes,
          'timeMs': sw.elapsedMilliseconds,
          'clustersProbed': metrics.clustersProbed,
          'distComps': metrics.distanceComputations,
          'pctSearched': pctSearched,
          'recall': recall,
          'totalVectors': metrics.totalVectors,
        });
      }

      setState(() => _isSearching = false);

      // Restore the user's nProbes after diagnostic
      annService.setNumProbes(_ivfNumProbes);

      // Show results dialog
      if (mounted) _showIvfPqDiagnosticResults(query, bfTimeMs, results);
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostic error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showIvfPqDiagnosticResults(String query, int bfTimeMs, List<Map<String, dynamic>> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('IVF-PQ Diagnostic', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Query: "$query"', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Config: ${widget.searchService.annSearchService.currentConfig.numClusters} clusters, '
                    '${widget.searchService.annSearchService.currentConfig.numSubquantizers} subs'),
                Text('Index: ${results.isNotEmpty ? results.first['totalVectors'] : "?"} vectors'),
                Text('Brute Force: ${bfTimeMs}ms (ground truth)'),
                const Divider(),
                const Text('IVF-PQ by nProbes:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Table header
                const Row(
                  children: [
                    Expanded(flex: 2, child: Text('nProbe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    Expanded(flex: 2, child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    Expanded(flex: 2, child: Text('Dists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    Expanded(flex: 2, child: Text('% Index', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    Expanded(flex: 2, child: Text('Recall', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                  ],
                ),
                const Divider(height: 8),
                ...results.map((r) {
                  final isApprox = (r['pctSearched'] as double) < 95.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('${r['nProbes']}', style: const TextStyle(fontSize: 10))),
                        Expanded(flex: 2, child: Text('${r['timeMs']}ms', style: const TextStyle(fontSize: 10))),
                        Expanded(flex: 2, child: Text('${r['distComps']}', style: TextStyle(fontSize: 10, color: isApprox ? Colors.green : Colors.orange))),
                        Expanded(flex: 2, child: Text('${(r['pctSearched'] as double).toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, color: isApprox ? Colors.green : Colors.orange))),
                        Expanded(flex: 2, child: Text('${((r['recall'] as double) * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10))),
                      ],
                    ),
                  );
                }),
                const Divider(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'The sweet spot is where recall remains high (>90%) while distance '
                    'computations (% Index) stay well below 100%.\n\n'
                    'For large datasets (10K+), even nProbes=1-4 can give good recall. '
                    'For small datasets, you may need higher nProbes.\n\n'
                    'More clusters = more selective IVF, faster per-query but slower training.',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Search using HNSW index with metrics tracking
  Future<List<SearchResultWithScore>> _searchWithHnsw(Float32List embedding, int k) async {
    if (_hnswIndex == null || !_hnswReady) {
      throw StateError('HNSW index not ready');
    }
    
    // Ensure ef is set to the user's chosen value
    _hnswIndex!.setEfSearch(_hnswEf.round());
    
    debugPrint('========== HNSW SEARCH ==========');
    debugPrint('HNSW: Index size = ${_hnswIndex!.size}');
    debugPrint('HNSW: Dimension = ${_hnswIndex!.dimension}');
    debugPrint('HNSW: isReady = ${_hnswIndex!.isReady}');
    debugPrint('HNSW: ef = ${_hnswEf.round()}');
    debugPrint('HNSW: Max graph layers = ${_hnswIndex!.getMaxLevel()}');
    debugPrint('HNSW: Searching for k=$k nearest neighbors');
    
    final stopwatch = Stopwatch()..start();
    final metricsResult = await _hnswIndex!.searchWithMetrics(embedding, k);
    stopwatch.stop();
    
    final results = metricsResult.results;
    
    // Capture metrics for UI display
    _lastDistComps = metricsResult.distanceComputations;
    _lastHops = metricsResult.hops;
    _lastEfUsed = metricsResult.efUsed;
    
    debugPrint('HNSW: Search completed in ${stopwatch.elapsedMilliseconds}ms');
    debugPrint('HNSW: Found ${results.length} results');
    debugPrint('HNSW: Distance computations: ${metricsResult.distanceComputations} / ${_hnswIndex!.size} '
        '(${(_lastDistComps / _hnswIndex!.size * 100).toStringAsFixed(1)}% of index)');
    debugPrint('HNSW: Graph hops: ${metricsResult.hops}');
    debugPrint('HNSW: ef used: ${metricsResult.efUsed}');
    
    final totalVectors = _hnswIndex!.size;
    if (_lastDistComps >= totalVectors) {
      debugPrint('⚠️ HNSW visited ALL vectors - effectively brute force! Lower ef to get true ANN.');
    } else {
      debugPrint('✅ HNSW used approximate search (visited ${(_lastDistComps / totalVectors * 100).toStringAsFixed(1)}% of vectors)');
    }
    
    if (results.isNotEmpty) {
      debugPrint('HNSW: Top 5 raw distances:');
      for (int i = 0; i < results.length && i < 5; i++) {
        debugPrint('  HNSW[$i]: id=${results[i].id}, distance=${results[i].distance.toStringAsFixed(6)}');
      }
    }
    
    // Convert HNSW results to SearchResultWithScore
    final allEmbeddings = widget.searchService.annSearchService.getAllEmbeddings();
    final imageIds = allEmbeddings.keys.toList();
    final allImages = widget.searchService.getAllImages();
    final imageMap = {for (var img in allImages) img.id: img};
    
    final searchResults = <SearchResultWithScore>[];
    for (final result in results) {
      if (result.id >= 0 && result.id < imageIds.length) {
        final imageId = imageIds[result.id];
        final image = imageMap[imageId];
        if (image != null) {
          // Convert distance to similarity (cosine distance to similarity)
          final similarity = 1.0 - result.distance;
          searchResults.add(SearchResultWithScore(
            image: image,
            similarity: similarity,
          ));
        }
      }
    }
    
    debugPrint('HNSW: Converted ${searchResults.length} results');
    debugPrint('==================================');
    
    return searchResults;
  }

  Future<void> _performTextSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _results = [];
    });

    try {
      final totalStopwatch = Stopwatch()..start();
      
      // Step 1: Generate embedding
      final embedStopwatch = Stopwatch()..start();
      final embedding = await widget.searchService.embeddingService.generateEmbedding(query);
      embedStopwatch.stop();
      
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║     ALPHA TEST SEARCH INITIATED        ║');
      debugPrint('╠════════════════════════════════════════╣');
      debugPrint('║ Query: "$query"');
      debugPrint('║ Selected Algorithm: ${_selectedAlgorithm.name.toUpperCase()}');
      debugPrint('║ HNSW Ready: $_hnswReady');
      debugPrint('║ HNSW Index: ${_hnswIndex != null ? "EXISTS" : "NULL"}');
      debugPrint('╚════════════════════════════════════════╝');
      
      // Step 2: Search using selected algorithm
      final searchStopwatch = Stopwatch()..start();
      List<SearchResultWithScore> results;
      
      if (_selectedAlgorithm == SearchAlgorithm.hnsw) {
        // Use HNSW
        debugPrint('>>> EXECUTING HNSW SEARCH PATH <<<');
        final float32Embedding = Float32List.fromList(embedding);
        results = await _searchWithHnsw(float32Embedding, 50);
      } else if (_selectedAlgorithm == SearchAlgorithm.ivfPq) {
        // Use IVF-PQ with metrics
        debugPrint('>>> EXECUTING IVF-PQ SEARCH PATH (nProbes=$_ivfNumProbes) <<<');
        results = await _searchWithIvfPq(embedding, 50);
      } else {
        // Use Brute Force (ground truth)
        debugPrint('>>> EXECUTING BRUTE FORCE SEARCH PATH <<<');
        results = await widget.searchService.annSearchService.searchSimilarWithScores(
          embedding,
          k: 50,
          forceBruteForce: true,
        );
      }
      searchStopwatch.stop();
      
      totalStopwatch.stop();

      // Load thumbnails for results
      final resultsWithThumbnails = <SearchResultWithScore>[];
      for (final result in results) {
        try {
          final imageWithThumb = await widget.searchService.imageLoader.getImageWithThumbnail(result.image.id);
          resultsWithThumbnails.add(SearchResultWithScore(
            image: imageWithThumb,
            similarity: result.similarity,
          ));
        } catch (e) {
          resultsWithThumbnails.add(result);
        }
      }
      
      // Log final results summary
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║     SEARCH RESULTS SUMMARY             ║');
      debugPrint('╠════════════════════════════════════════╣');
      debugPrint('║ Algorithm Used: ${_selectedAlgorithm.name.toUpperCase()}');
      debugPrint('║ Results Found: ${results.length}');
      debugPrint('║ Search Time: ${searchStopwatch.elapsedMilliseconds}ms');
      if (results.isNotEmpty) {
        debugPrint('║ Top 5 Similarities:');
        for (int i = 0; i < results.length && i < 5; i++) {
          debugPrint('║   [${i+1}] ${(results[i].similarity * 100).toStringAsFixed(2)}% - ${results[i].image.id}');
        }
      }
      debugPrint('╚════════════════════════════════════════╝');

      setState(() {
        _results = resultsWithThumbnails;
        _embeddingTimeMs = embedStopwatch.elapsedMilliseconds;
        _searchTimeMs = searchStopwatch.elapsedMilliseconds;
        _totalTimeMs = totalStopwatch.elapsedMilliseconds;
        _lastQuery = query;
        _isSearching = false;
      });

      // Add to test history
      _testHistory.add(TestResult(
        query: query,
        model: _currentModel,
        algorithm: _selectedAlgorithm,
        resultCount: results.length,
        topSimilarity: results.isNotEmpty ? results.first.similarity : 0,
        embeddingTimeMs: _embeddingTimeMs,
        searchTimeMs: _searchTimeMs,
        timestamp: DateTime.now(),
      ));

    } catch (e) {
      setState(() {
        _errorMessage = 'Search failed: $e';
        _isSearching = false;
      });
    }
  }

  Future<void> _performImageSearch() async {
    final ImagePicker picker = ImagePicker();
    
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      
      if (pickedFile == null) return;

      setState(() {
        _isSearching = true;
        _errorMessage = null;
        _results = [];
      });

      final imageBytes = await File(pickedFile.path).readAsBytes();
      final totalStopwatch = Stopwatch()..start();
      
      // Step 1: Generate image embedding
      final embedStopwatch = Stopwatch()..start();
      final embedding = await widget.searchService.embeddingService.generateImageEmbedding(imageBytes);
      embedStopwatch.stop();
      
      // Step 2: Search using selected algorithm
      final searchStopwatch = Stopwatch()..start();
      List<SearchResultWithScore> results;
      
      if (_selectedAlgorithm == SearchAlgorithm.hnsw) {
        // Use HNSW
        final float32Embedding = Float32List.fromList(embedding);
        results = await _searchWithHnsw(float32Embedding, 50);
      } else if (_selectedAlgorithm == SearchAlgorithm.ivfPq) {
        // Use IVF-PQ with metrics
        results = await _searchWithIvfPq(embedding, 50);
      } else {
        // Use Brute Force (ground truth)
        results = await widget.searchService.annSearchService.searchSimilarWithScores(
          embedding,
          k: 50,
          forceBruteForce: true,
        );
      }
      searchStopwatch.stop();
      
      totalStopwatch.stop();

      // Load thumbnails for results
      final resultsWithThumbnails = <SearchResultWithScore>[];
      for (final result in results) {
        try {
          final imageWithThumb = await widget.searchService.imageLoader.getImageWithThumbnail(result.image.id);
          resultsWithThumbnails.add(SearchResultWithScore(
            image: imageWithThumb,
            similarity: result.similarity,
          ));
        } catch (e) {
          resultsWithThumbnails.add(result);
        }
      }

      setState(() {
        _results = resultsWithThumbnails;
        _embeddingTimeMs = embedStopwatch.elapsedMilliseconds;
        _searchTimeMs = searchStopwatch.elapsedMilliseconds;
        _totalTimeMs = totalStopwatch.elapsedMilliseconds;
        _lastQuery = '[Image: ${pickedFile.name}]';
        _isSearching = false;
      });

      // Add to test history
      _testHistory.add(TestResult(
        query: '[Image Search]',
        model: _currentModel,
        algorithm: _selectedAlgorithm,
        resultCount: results.length,
        topSimilarity: results.isNotEmpty ? results.first.similarity : 0,
        embeddingTimeMs: _embeddingTimeMs,
        searchTimeMs: _searchTimeMs,
        timestamp: DateTime.now(),
      ));

    } catch (e) {
      setState(() {
        _errorMessage = 'Image search failed: $e';
        _isSearching = false;
      });
    }
  }

  Future<void> _switchModel() async {
    // Show model picker dialog with all 3 options
    final newModel = await showDialog<SiglipModelVersion>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Model'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ This will re-index all images (~2-3 minutes)',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...SiglipModelVersion.values.map((version) {
              final isCurrent = version == _currentModel;
              String label;
              String description;
              IconData icon;
              Color color;
              switch (version) {
                case SiglipModelVersion.siglip1:
                  label = 'SigLIP-1';
                  description = '32K vocab, 224×224, aligned';
                  icon = Icons.speed;
                  color = Colors.blue;
                  break;
                case SiglipModelVersion.siglip2:
                  label = 'SigLIP-2';
                  description = '256K vocab, 224×224, projection';
                  icon = Icons.star;
                  color = Colors.amber;
                  break;
                case SiglipModelVersion.finetunedSiglip:
                  label = 'Fine-tuned SigLIP';
                  description = '256K vocab, 224×224, Taglish-trained';
                  icon = Icons.auto_awesome;
                  color = Colors.deepPurple;
                  break;
              }
              return ListTile(
                leading: Icon(icon, color: color),
                title: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(description, style: const TextStyle(fontSize: 11)),
                trailing: isCurrent
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : null,
                enabled: !isCurrent,
                onTap: isCurrent ? null : () => Navigator.pop(context, version),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (newModel == null || !mounted) return;

    setState(() => _isInitializing = true);

    try {
      await widget.searchService.embeddingService.switchToModel(newModel);
      await widget.searchService.reindexAllImages();
      
      // Reset HNSW index - embeddings changed, old index is invalid
      _hnswIndex?.dispose();
      _hnswIndex = null;
      _hnswReady = false;
      
      // If HNSW was selected, fall back to brute force
      if (_selectedAlgorithm == SearchAlgorithm.hnsw) {
        _selectedAlgorithm = SearchAlgorithm.bruteForce;
      }

      setState(() {
        _currentModel = widget.searchService.embeddingService.modelVersion;
        _currentConfig = widget.searchService.embeddingService.modelConfig;
        _indexedImageCount = widget.searchService.getAllImages().length;
        _results = [];
        _isInitializing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Switched to ${newModel.name.toUpperCase()} (HNSW index cleared)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to switch model: $e';
        _isInitializing = false;
      });
    }
  }

  void _openImageDetails(ImageItem image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsScreen(
          image: image,
          searchService: widget.searchService,
        ),
      ),
    );
  }

  void _showTestHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Test History (${_testHistory.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear'),
                      onPressed: () {
                        setState(() => _testHistory.clear());
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: _testHistory.isEmpty
                      ? const Center(child: Text('No test history yet'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _testHistory.length,
                          itemBuilder: (context, index) {
                            final test = _testHistory[_testHistory.length - 1 - index];
                            final algorithmName = switch (test.algorithm) {
                              SearchAlgorithm.bruteForce => 'BF',
                              SearchAlgorithm.ivfPq => 'IVF',
                              SearchAlgorithm.hnsw => 'HNSW',
                            };
                            return ListTile(
                              leading: Icon(
                                test.model == SiglipModelVersion.finetunedSiglip
                                    ? Icons.auto_awesome
                                    : test.model == SiglipModelVersion.siglip2
                                        ? Icons.star
                                        : Icons.speed,
                                color: test.model == SiglipModelVersion.finetunedSiglip
                                    ? Colors.deepPurple
                                    : test.model == SiglipModelVersion.siglip2
                                        ? Colors.amber
                                        : Colors.blue,
                              ),
                              title: Text(test.query),
                              subtitle: Text(
                                '${test.model.name.toUpperCase()} | $algorithmName | '
                                'Top: ${(test.topSimilarity * 100).toStringAsFixed(1)}% | '
                                '${test.embeddingTimeMs + test.searchTimeMs}ms',
                              ),
                              trailing: Text(
                                '${test.timestamp.hour}:${test.timestamp.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _exportResults() {
    if (_testHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No test history to export')),
      );
      return;
    }

    // Build CSV content
    final buffer = StringBuffer();
    buffer.writeln('Timestamp,Model,Algorithm,Query,Top Similarity,Embedding Time (ms),Search Time (ms),Total Time (ms)');
    
    for (final test in _testHistory) {
      final algorithmName = switch (test.algorithm) {
        SearchAlgorithm.bruteForce => 'Brute Force',
        SearchAlgorithm.ivfPq => 'IVF-PQ',
        SearchAlgorithm.hnsw => 'HNSW',
      };
      buffer.writeln(
        '${test.timestamp.toIso8601String()},'
        '${test.model.name},'
        '$algorithmName,'
        '"${test.query.replaceAll('"', '""')}",'
        '${test.topSimilarity},'
        '${test.embeddingTimeMs},'
        '${test.searchTimeMs},'
        '${test.embeddingTimeMs + test.searchTimeMs}',
      );
    }

    // Show export dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Results'),
        content: SingleChildScrollView(
          child: SelectableText(
            buffer.toString(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Test result for history tracking
class TestResult {
  final String query;
  final SiglipModelVersion model;
  final SearchAlgorithm algorithm;
  final int resultCount;
  final double topSimilarity;
  final int embeddingTimeMs;
  final int searchTimeMs;
  final DateTime timestamp;

  TestResult({
    required this.query,
    required this.model,
    required this.algorithm,
    required this.resultCount,
    required this.topSimilarity,
    required this.embeddingTimeMs,
    required this.searchTimeMs,
    required this.timestamp,
  });
}
