import 'package:flutter/material.dart';
import 'dart:io';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/image_search_service.dart';
import '../../models/search_models.dart';
import 'details_screen.dart';

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
  
  // Test history for comparison
  final List<TestResult> _testHistory = [];

  @override
  void initState() {
    super.initState();
    _currentModel = widget.searchService.embeddingService.modelVersion;
    _currentConfig = widget.searchService.embeddingService.modelConfig;
    _indexedImageCount = widget.searchService.getAllImages().length;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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
      body: Column(
        children: [
          // Model Info Card
          _buildModelInfoCard(isDark, textColor, cardColor, borderColor),
          
          // Search Input Section
          _buildSearchSection(isDark, textColor, cardColor, borderColor),
          
          // Search Metrics
          if (_totalTimeMs > 0)
            _buildMetricsCard(isDark, textColor, cardColor, borderColor),
          
          // Results List
          Expanded(
            child: _buildResultsList(isDark, textColor, cardColor, borderColor),
          ),
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
                    _currentModel == SiglipModelVersion.siglip2 
                        ? Icons.star 
                        : Icons.speed,
                    color: _currentModel == SiglipModelVersion.siglip2 
                        ? Colors.amber 
                        : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Model: ${_currentModel.name.toUpperCase()}',
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
              _buildChip('Brute Force', Icons.search, isDark, isHighlight: true),
            ],
          ),
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

  Widget _buildResultsList(bool isDark, Color textColor, Color cardColor, Color borderColor) {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing model...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
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
      );
    }

    if (_results.isEmpty && !_isSearching) {
      return Center(
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
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultItem(result, index, isDark, textColor, cardColor, borderColor);
      },
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
      
      // Step 2: Brute force search (directly using ANNSearchService)
      final searchStopwatch = Stopwatch()..start();
      final results = await widget.searchService.annSearchService.searchSimilarWithScores(
        embedding,
        k: 50, // Get top 50 for alpha testing
        forceBruteForce: true, // Force brute force search
      );
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
        _lastQuery = query;
        _isSearching = false;
      });

      // Add to test history
      _testHistory.add(TestResult(
        query: query,
        model: _currentModel,
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
      
      // Step 2: Brute force search
      final searchStopwatch = Stopwatch()..start();
      final results = await widget.searchService.annSearchService.searchSimilarWithScores(
        embedding,
        k: 50,
        forceBruteForce: true,
      );
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
    final newModel = _currentModel == SiglipModelVersion.siglip1
        ? SiglipModelVersion.siglip2
        : SiglipModelVersion.siglip1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Model?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Switch to ${newModel.name.toUpperCase()}?'),
            const SizedBox(height: 16),
            const Text(
              '⚠️ This will re-index all images (~2-3 minutes)',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isInitializing = true);

    try {
      await widget.searchService.embeddingService.switchToModel(newModel);
      await widget.searchService.reindexAllImages();

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
            content: Text('✅ Switched to ${newModel.name.toUpperCase()}'),
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
                            return ListTile(
                              leading: Icon(
                                test.model == SiglipModelVersion.siglip2
                                    ? Icons.star
                                    : Icons.speed,
                                color: test.model == SiglipModelVersion.siglip2
                                    ? Colors.amber
                                    : Colors.blue,
                              ),
                              title: Text(test.query),
                              subtitle: Text(
                                '${test.model.name.toUpperCase()} | '
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
    buffer.writeln('Timestamp,Model,Query,Top Similarity,Embedding Time (ms),Search Time (ms),Total Time (ms)');
    
    for (final test in _testHistory) {
      buffer.writeln(
        '${test.timestamp.toIso8601String()},'
        '${test.model.name},'
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
  final int resultCount;
  final double topSimilarity;
  final int embeddingTimeMs;
  final int searchTimeMs;
  final DateTime timestamp;

  TestResult({
    required this.query,
    required this.model,
    required this.resultCount,
    required this.topSimilarity,
    required this.embeddingTimeMs,
    required this.searchTimeMs,
    required this.timestamp,
  });
}
