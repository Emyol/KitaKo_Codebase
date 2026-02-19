import 'package:flutter/material.dart';
import '../theme/theme_notifier.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const SettingsScreen({super.key, required this.themeNotifier});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// false = Performance (IVF-PQ), true = Accuracy (HNSW)
  bool _useAccuracyMode = false;

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
        ],
      ),
    );
  }

  Widget _buildSearchModeTile(bool isDark, Color textColor, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
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
                  onTap: () => setState(() => _useAccuracyMode = false),
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
                  onTap: () => setState(() => _useAccuracyMode = true),
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
    final selectedBg = const Color(0xFF4A90E2);
    final unselectedBg = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF0F0F0);
    final selectedFg = Colors.white;
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
            color: selected ? selectedBg : (isDark ? const Color(0xFF555555) : const Color(0xFFD0D0D0)),
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
                color: selected ? selectedFg.withValues(alpha: 0.8) : unselectedFg.withValues(alpha: 0.6),
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
                  color: Colors.black.withValues(alpha: 0.05),
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
}
