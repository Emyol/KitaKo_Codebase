import 'package:flutter/material.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import '../services/embedding_service.dart';

/// Example widget demonstrating how to toggle between SigLIP-1 and SigLIP-2
///
/// This can be integrated into a settings screen or debug menu
class ModelVersionToggle extends StatefulWidget {
  final EmbeddingService embeddingService;

  const ModelVersionToggle({
    super.key,
    required this.embeddingService,
  });

  @override
  State<ModelVersionToggle> createState() => _ModelVersionToggleState();
}

class _ModelVersionToggleState extends State<ModelVersionToggle> {
  bool _isSwitching = false;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    final currentVersion = widget.embeddingService.modelVersion;
    final config = widget.embeddingService.modelConfig;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SigLIP Model Version',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            
            // Current model info
            if (config != null) ...[
              _buildInfoRow('Current Version', currentVersion.name.toUpperCase()),
              _buildInfoRow('Image Size', '${config.imageSize}x${config.imageSize}'),
              _buildInfoRow('Vocabulary', '${config.vocabularySize} tokens'),
              _buildInfoRow('Embedding Dim', '${config.embeddingDimension}'),
              _buildInfoRow('Has Projection', config.hasProjectionLayer ? 'Yes' : 'No'),
              const SizedBox(height: 16),
            ],

            // Model selection
            SegmentedButton<SiglipModelVersion>(
              segments: const [
                ButtonSegment(
                  value: SiglipModelVersion.siglip1,
                  label: Text('SigLIP-1'),
                  icon: Icon(Icons.layers),
                ),
                ButtonSegment(
                  value: SiglipModelVersion.siglip2,
                  label: Text('SigLIP-2'),
                  icon: Icon(Icons.layers_outlined),
                ),
              ],
              selected: {currentVersion},
              onSelectionChanged: _isSwitching ? null : _onModelSelected,
            ),
            
            const SizedBox(height: 16),
            
            // Status message
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Loading indicator
            if (_isSwitching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Model comparison info
            ExpansionTile(
              title: const Text('Model Comparison'),
              children: [
                _buildComparisonTable(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildComparisonTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade300),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: const [
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('Feature', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('SigLIP-1', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('SigLIP-2', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        _buildComparisonRow('Image Size', '224x224', '256x256'),
        _buildComparisonRow('Vocabulary', '32K', '256K'),
        _buildComparisonRow('Projection', 'No', 'Yes'),
        _buildComparisonRow('Speed', 'Faster', 'Slower'),
        _buildComparisonRow('Accuracy', 'Good', 'Better'),
      ],
    );
  }

  TableRow _buildComparisonRow(String feature, String v1, String v2) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(feature),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(v1, style: const TextStyle(fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(v2, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  void _onModelSelected(Set<SiglipModelVersion> selected) async {
    final newVersion = selected.first;
    if (newVersion == widget.embeddingService.modelVersion) {
      return;
    }

    setState(() {
      _isSwitching = true;
      _statusMessage = 'Switching to ${newVersion.name}...';
    });

    try {
      final success = await widget.embeddingService.switchToModel(newVersion);
      
      setState(() {
        _isSwitching = false;
        if (success) {
          _statusMessage = 'Successfully switched to ${newVersion.name}';
        } else {
          _statusMessage = 'Failed to switch to ${newVersion.name}';
        }
      });

      // Clear status message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _statusMessage = '';
          });
        }
      });
    } catch (e) {
      setState(() {
        _isSwitching = false;
        _statusMessage = 'Error: $e';
      });
    }
  }
}

/// Example usage in a settings or debug screen:
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:provider/provider.dart';
/// 
/// class DebugSettingsScreen extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     final embeddingService = Provider.of<EmbeddingService>(context);
///     
///     return Scaffold(
///       appBar: AppBar(title: const Text('Debug Settings')),
///       body: ListView(
///         children: [
///           ModelVersionToggle(embeddingService: embeddingService),
///           // Other debug options...
///         ],
///       ),
///     );
///   }
/// }
/// ```
