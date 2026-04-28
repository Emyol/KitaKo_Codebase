import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/embedding_service.dart';
import '../../services/image_search_service.dart';
import '../../state/settings_controller.dart';
import '../theme/theme_notifier.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService searchService;
  final SettingsController settingsController;

  const SettingsScreen({
    super.key,
    required this.themeNotifier,
    required this.searchService,
    required this.settingsController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// false = Performance (IVF-PQ), true = Accuracy (HNSW)
  late bool _useAccuracyMode;

  /// Variants exposed to the dev-mode switcher (scope: first two sets only).
  static const List<ModelVariant> _devVariants = [
    ModelVariant.kitakoFp32,
    ModelVariant.kitakoMixed,
  ];

  @override
  void initState() {
    super.initState();
    _useAccuracyMode = widget.searchService.preferHnsw ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;

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
          const SizedBox(height: 32),

          // Search Section
          Text(
            'Search',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSearchModeTile(isDark, textColor, subtitleColor),

          // Developer Section (debug builds only).
          if (kDebugMode) ...[
            const SizedBox(height: 32),
            Text(
              'Developer',
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildModelSwitcher(isDark, textColor, subtitleColor),
            const SizedBox(height: 12),
            _buildClearCacheTile(isDark, textColor, subtitleColor),
          ],
        ],
      ),
    );
  }

  // ─────────────────────── Developer widgets ───────────────────────

  Widget _buildModelSwitcher(
      bool isDark, Color textColor, Color subtitleColor) {
    final selected = widget.settingsController.selectedVariant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Embedding model',
            style: TextStyle(color: textColor, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Switch the ONNX model pair used for text/image embeddings. '
            'Visible only in debug builds.',
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: _devVariants
                .map(
                  (v) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: v == _devVariants.last ? 0 : 12,
                      ),
                      child: _buildVariantButton(
                        variant: v,
                        selected: selected == v,
                        isDark: isDark,
                        onTap: () => _onVariantTap(v),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantButton({
    required ModelVariant variant,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const selectedBg = Color(0xFF4A90E2);
    final unselectedBg =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF0F0F0);
    const selectedFg = Colors.white;
    final unselectedFg = isDark ? Colors.white70 : Colors.black87;

    // Short label derived from the variant.
    final short = variant == ModelVariant.kitakoFp32 ? 'FP32+FP32' : 'FP32+INT8';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? selectedBg
                : (isDark
                    ? const Color(0xFF555555)
                    : const Color(0xFFD0D0D0)),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              variant == ModelVariant.kitakoFp32
                  ? Icons.high_quality
                  : Icons.balance,
              color: selected ? selectedFg : unselectedFg,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              short,
              style: TextStyle(
                color: selected ? selectedFg : unselectedFg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              variant.displayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? selectedFg.withValues(alpha: 0.8)
                    : unselectedFg.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearCacheTile(
      bool isDark, Color textColor, Color subtitleColor) {
    final current =
        widget.searchService.embeddingService.activeVariant?.visionEncoderId ??
            '(none)';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clear embedding cache',
            style: TextStyle(color: textColor, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Wipes the cached embeddings for the current vision encoder '
            '($current). Next search will re-embed all images.',
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear cache'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE57373),
                side: const BorderSide(color: Color(0xFFE57373)),
              ),
              onPressed: _onClearCacheTap,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Actions ───────────────────────

  Future<void> _onVariantTap(ModelVariant variant) async {
    final controller = widget.settingsController;
    if (variant == controller.selectedVariant) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch embedding model?'),
        content: Text(
          'Switch to ${variant.displayName}? '
          'The app will reload the model and may re-embed images if the '
          'vision encoder changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runBlocking(
      title: 'Switching model',
      subtitle: 'Loading ${variant.displayName}…',
      action: () async {
        await controller.setSelectedVariant(variant);
        final ok = await widget.searchService.switchVariant(variant);
        if (!ok) {
          throw StateError(
            'Failed to load ${variant.displayName}. '
            'Verify the ONNX files are present (push via ADB if needed).',
          );
        }
      },
    );

    if (mounted) setState(() {});
  }

  Future<void> _onClearCacheTap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear embedding cache?'),
        content: const Text(
          'This wipes cached embeddings for the current vision encoder. '
          'Your images will be re-embedded on next search.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runBlocking(
      title: 'Clearing cache',
      subtitle: 'Removing cached embeddings…',
      action: () => widget.searchService.clearCurrentEncoderCache(),
    );
    if (mounted) setState(() {});
  }

  /// Shows a blocking modal dialog while [action] runs, then dismisses it.
  /// Surfaces any thrown error as a snackbar.
  Future<void> _runBlocking({
    required String title,
    required String subtitle,
    required Future<void> Function() action,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BlockingOverlay(title: title, subtitle: subtitle),
    );
    try {
      await action();
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ─────────────────────── Existing widgets ───────────────────────

  Widget _buildSearchModeTile(
      bool isDark, Color textColor, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search mode',
            style: TextStyle(color: textColor, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            _useAccuracyMode
                ? 'Accuracy mode uses HNSW for higher recall'
                : 'Performance mode uses IVF-PQ for faster search',
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildModeButton(
                  label: 'Performance',
                  subtitle: 'IVF-PQ',
                  icon: Icons.speed,
                  selected: !_useAccuracyMode,
                  onTap: () {
                    setState(() => _useAccuracyMode = false);
                    widget.searchService.setPreferredAlgorithm(false);
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModeButton(
                  label: 'Accuracy',
                  subtitle: 'HNSW',
                  icon: Icons.gps_fixed,
                  selected: _useAccuracyMode,
                  onTap: () {
                    setState(() => _useAccuracyMode = true);
                    widget.searchService.setPreferredAlgorithm(true);
                  },
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    const selectedBg = Color(0xFF4A90E2);
    final unselectedBg =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF0F0F0);
    const selectedFg = Colors.white;
    final unselectedFg = isDark ? Colors.white70 : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? selectedBg
                : (isDark
                    ? const Color(0xFF555555)
                    : const Color(0xFFD0D0D0)),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? selectedFg : unselectedFg, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? selectedFg : unselectedFg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: selected
                    ? selectedFg.withValues(alpha: 0.8)
                    : unselectedFg.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
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
      decoration: _cardDecoration(isDark),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: textColor, fontSize: 16)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF4A90E2),
            activeTrackColor: const Color(0xFF5BA3F5).withValues(alpha: 0.5),
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

  BoxDecoration _cardDecoration(bool isDark) {
    return BoxDecoration(
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
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }
}

/// Full-screen modal shown while a blocking operation runs
/// (model switch, cache clear).
class _BlockingOverlay extends StatelessWidget {
  final String title;
  final String subtitle;

  const _BlockingOverlay({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
