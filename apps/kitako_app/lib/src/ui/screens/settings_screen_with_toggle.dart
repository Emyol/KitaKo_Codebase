import 'package:flutter/material.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import '../theme/theme_notifier.dart';
import '../../services/image_search_service.dart';

/// Settings screen with model version toggle
/// 
/// ⚠️ WARNING: Switching models requires re-indexing all images (2-3 minutes)
class SettingsScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService? searchService; // Optional for testing

  const SettingsScreen({
    super.key,
    required this.themeNotifier,
    this.searchService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _titleColour = false;
  bool _highlightColour = false;
  bool _systemSetting1 = false;
  bool _systemSetting2 = false;
  bool _systemSetting3 = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hasSearchService = widget.searchService != null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).appBarTheme.titleTextStyle?.color,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Personalization Section
          Text(
            'Personalization',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingTile(
            'Dark mode',
            widget.themeNotifier.isDarkMode,
            (value) {
              widget.themeNotifier.toggleTheme(value);
            },
            isDark,
            textColor,
          ),
          const SizedBox(height: 12),
          _buildSettingTile(
            'Title colour',
            _titleColour,
            (value) {
              setState(() {
                _titleColour = value;
              });
            },
            isDark,
            textColor,
          ),
          const SizedBox(height: 12),
          _buildSettingTile(
            'Highlight colour',
            _highlightColour,
            (value) {
              setState(() {
                _highlightColour = value;
              });
            },
            isDark,
            textColor,
          ),
          const SizedBox(height: 32),

          // Model Settings Section (if searchService available)
          if (hasSearchService) ...[
            Text(
              'Search Model',
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ Switching models requires re-indexing all images (~2-3 min)',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            _buildModelSelector(isDark, textColor),
            const SizedBox(height: 32),
          ],

          // System Section
          Text(
            'System',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingTile(
            'System setting 1',
            _systemSetting1,
            (value) {
              setState(() {
                _systemSetting1 = value;
              });
            },
            isDark,
            textColor,
          ),
          const SizedBox(height: 12),
          _buildSettingTile(
            'System setting 2',
            _systemSetting2,
            (value) {
              setState(() {
                _systemSetting2 = value;
              });
            },
            isDark,
            textColor,
          ),
          const SizedBox(height: 12),
          _buildSettingTile(
            'System setting 3',
            _systemSetting3,
            (value) {
              setState(() {
                _systemSetting3 = value;
              });
            },
            isDark,
            textColor,
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(bool isDark, Color textColor) {
    final currentVersion = widget.searchService?.embeddingService.modelVersion ?? 
                           SiglipModelVersion.siglip1;
    final config = widget.searchService?.embeddingService.modelConfig;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.model_training, color: textColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Current Model: ${currentVersion.name.toUpperCase()}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (config != null) ...[
            const SizedBox(height: 12),
            _buildInfoChip('Image Size', '${config.imageSize}×${config.imageSize}', isDark),
            const SizedBox(height: 4),
            _buildInfoChip('Vocabulary', '${config.vocabularySize} tokens', isDark),
            const SizedBox(height: 4),
            _buildInfoChip('Projection', config.hasProjectionLayer ? 'Yes' : 'No', isDark),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<SiglipModelVersion>(
              segments: const [
                ButtonSegment(
                  value: SiglipModelVersion.siglip1,
                  label: Text('SigLIP-1\n(Faster)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.speed, size: 18),
                ),
                ButtonSegment(
                  value: SiglipModelVersion.siglip2,
                  label: Text('SigLIP-2\n(Better)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.star, size: 18),
                ),
              ],
              selected: {currentVersion},
              onSelectionChanged: (selected) => _onModelSelected(selected.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isDark ? Colors.grey[300] : Colors.grey[700],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _onModelSelected(SiglipModelVersion newVersion) async {
    final currentVersion = widget.searchService?.embeddingService.modelVersion;
    
    if (currentVersion == newVersion) {
      return; // Already on this model
    }

    // Show warning dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Switch Model?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are about to switch from ${currentVersion?.name.toUpperCase()} to ${newVersion.name.toUpperCase()}.'),
            const SizedBox(height: 16),
            const Text(
              '⚠️ This will:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Re-index all 1000 images'),
            const Text('• Take ~2-3 minutes'),
            const Text('• Search will be unavailable during re-indexing'),
            const SizedBox(height: 16),
            Text(
              newVersion == SiglipModelVersion.siglip2
                  ? '✅ SigLIP-2 provides better search accuracy'
                  : '⚡ SigLIP-1 is faster but less accurate',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: newVersion == SiglipModelVersion.siglip2 
                    ? Colors.green 
                    : Colors.blue,
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Switch & Re-index'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Switching to ${newVersion.name.toUpperCase()}...'),
            const SizedBox(height: 8),
            const Text(
              'Re-indexing images, please wait...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      // Step 1: Switch the model
      final success = await widget.searchService!.embeddingService.switchToModel(newVersion);
      
      if (!success) {
        throw Exception('Failed to load ${newVersion.name} model');
      }

      // Step 2: Re-index all images with new model
      await widget.searchService!.reindexAllImages();
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        setState(() {}); // Refresh UI
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Switched to ${newVersion.name.toUpperCase()} successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to switch: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildSettingTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
    bool isDark,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: textColor, fontSize: 16)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF4A90E2),
            activeTrackColor: const Color(0xFF5BA3F5).withOpacity(0.5),
            inactiveThumbColor: isDark
                ? const Color(0xFF666666)
                : const Color(0xFF999999),
            inactiveTrackColor: isDark
                ? const Color(0xFF3A3A3A)
                : const Color(0xFFE0E0E0),
          ),
        ],
      ),
    );
  }
}
