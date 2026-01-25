import 'package:flutter/material.dart';
import '../theme/theme_notifier.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const SettingsScreen({super.key, required this.themeNotifier});

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
