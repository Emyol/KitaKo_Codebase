import 'package:flutter/material.dart';

import '../services/model_download_service.dart';

/// Widget that ensures ML models are downloaded before showing child content.
///
/// Shows a download progress UI when models are not yet cached.
class ModelDownloadGate extends StatefulWidget {
  /// The widget to show once models are ready
  final Widget child;

  /// Optional widget to show while checking model status
  final Widget? loadingPlaceholder;

  /// Callback when models are ready
  final VoidCallback? onReady;

  /// Whether to download automatically or show a prompt
  final bool autoDownload;

  const ModelDownloadGate({
    super.key,
    required this.child,
    this.loadingPlaceholder,
    this.onReady,
    this.autoDownload = true, // Changed to true for automatic download
  });

  @override
  State<ModelDownloadGate> createState() => _ModelDownloadGateState();
}

class _ModelDownloadGateState extends State<ModelDownloadGate> {
  final _downloadService = ModelDownloadService();

  bool _isChecking = true;
  bool _modelsReady = false;
  bool _isDownloading = false;
  String? _error;

  String _currentModel = '';
  double _currentProgress = 0.0;
  int _downloadedCount = 0;

  @override
  void initState() {
    super.initState();
    _checkModels();
  }

  Future<void> _checkModels() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    try {
      // Check if either SigLIP-1 or SigLIP-2 is available
      final siglip1Ready = await _downloadService.isSiglip1Available();
      final siglip2Ready = await _downloadService.isSiglip2Available();

      debugPrint('ModelDownloadGate: SigLIP-1 ready: $siglip1Ready, SigLIP-2 ready: $siglip2Ready');

      if (siglip1Ready || siglip2Ready) {
        debugPrint('ModelDownloadGate: Models already available, showing app');
        setState(() {
          _modelsReady = true;
          _isChecking = false;
        });
        widget.onReady?.call();
      } else {
        debugPrint('ModelDownloadGate: No models found');
        setState(() => _isChecking = false);

        if (widget.autoDownload) {
          debugPrint('ModelDownloadGate: Starting auto-download');
          await _startDownload();
        }
      }
    } catch (e) {
      debugPrint('ModelDownloadGate: Error checking models: $e');
      setState(() {
        _isChecking = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _error = null;
      _downloadedCount = 0;
    });

    try {
      // Only download SigLIP-1 models (auto-downloadable)
      final siglip1Models = ModelDownloadService.models.entries
          .where((e) => e.value.modelType == ModelType.siglip1Quantized)
          .toList();

      for (final entry in siglip1Models) {
        final modelKey = entry.key;
        
        setState(() {
          _currentModel = modelKey;
          _currentProgress = 0.0;
        });

        await _downloadService.downloadModel(
          modelKey,
          onProgress: (progress) {
            setState(() => _currentProgress = progress);
          },
        );

        setState(() => _downloadedCount++);
      }

      setState(() {
        _isDownloading = false;
        _modelsReady = true;
      });
      widget.onReady?.call();
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return widget.loadingPlaceholder ??
          const Center(child: CircularProgressIndicator());
    }

    if (_modelsReady) {
      return widget.child;
    }

    return _buildDownloadPrompt(context);
  }

  Widget _buildDownloadPrompt(BuildContext context) {
    final theme = Theme.of(context);
    final totalModels = ModelDownloadService.models.length;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Icon(
                _isDownloading ? Icons.downloading : Icons.cloud_download,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                _isDownloading ? 'Downloading Models...' : 'Download Required',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                _isDownloading
                    ? 'Please wait while the AI models are downloaded. '
                        'This is a one-time download.'
                    : 'KitaKo needs to download AI models to enable '
                        'semantic image search. This is a one-time download '
                        'of about ${_downloadService.totalDownloadSizeFormatted}.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Progress or Download Button
              if (_isDownloading) ...[
                // Current model
                Text(
                  _getModelDisplayName(_currentModel),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _currentProgress,
                    minHeight: 12,
                  ),
                ),
                const SizedBox(height: 8),

                // Progress text
                Text(
                  '${(_currentProgress * 100).toInt()}% • '
                  'Model $_downloadedCount of $totalModels',
                  style: theme.textTheme.bodySmall,
                ),
              ] else ...[
                // Download SigLIP-1 automatically prompt
                Text(
                  'Download AI Models',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                Text(
                  'To enable semantic image search, download the SigLIP-1 models (~210 MB).',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                
                // SigLIP-1 Auto-download
                FilledButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Models Now'),
                ),
                const SizedBox(height: 16),
                
                // Advanced options
                TextButton(
                  onPressed: () => _showAdvancedOptions(context),
                  child: const Text('Advanced Options (SigLIP-2)'),
                ),
              ],

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _checkModels,
                  child: const Text('Retry'),
                ),
              ],

              // Skip option - continue without models
              if (!_isDownloading) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Models not hosted yet? You can continue with demo mode.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _modelsReady = true);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue without models (Demo Mode)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelTile(
    BuildContext context,
    String modelKey,
    ModelInfo info,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.memory,
            size: 20,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              info.description,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            info.sizeFormatted,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelOptionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String size,
    required List<MapEntry<String, ModelInfo>> models,
    required VoidCallback onDownload,
    required IconData icon,
    required String buttonText,
    bool isRecommended = false,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isRecommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'RECOMMENDED',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  size,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...models.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.fiber_manual_record,
                        size: 8,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value.description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onDownload,
                icon: Icon(icon),
                label: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSiglip2Instructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SigLIP-2 Setup Instructions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SigLIP-2 models are too large for automatic download. '
                'Follow these steps to set them up manually:',
              ),
              const SizedBox(height: 16),
              const Text(
                '1. From your PC, use ADB to push models:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const SelectableText(
                  'adb push siglip2_vision_model_fp32.onnx /data/local/tmp/\n'
                  'adb push siglip2_text_model_fp32.onnx /data/local/tmp/',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '2. Restart the app',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'The app will automatically copy the models from /data/local/tmp/ '
                'to its cache directory on startup.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Model files are located in your workspace:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '<workspace>/assets/models/siglip2_vision_model_fp32.onnx\n'
                '<workspace>/assets/models/siglip2_text_model_fp32.onnx',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showAdvancedOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Advanced Model Options'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose between different model quality levels:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // SigLIP-1
              const Text(
                'SigLIP-1 (Quantized) - ~210 MB',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '✓ Auto-download from HuggingFace\n'
                '✓ Fast download (~30 seconds)\n'
                '✓ Good search quality\n'
                '✓ Works immediately',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              
              // SigLIP-2
              const Text(
                'SigLIP-2 (Full Precision) - ~1.5 GB ⭐',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '✓ Best search accuracy\n'
                '✓ Proper embedding alignment\n'
                '✓ Recommended for production\n'
                '⚠ Requires manual setup via ADB',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _showSiglip2Instructions(context);
            },
            child: const Text('Setup SigLIP-2'),
          ),
        ],
      ),
    );
  }

  String _getModelDisplayName(String key) {
    final info = ModelDownloadService.models[key];
    return info?.description ?? key;
  }
}
