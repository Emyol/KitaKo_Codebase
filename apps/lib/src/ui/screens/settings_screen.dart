import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/embedding_service.dart';
import '../../services/image_search_service.dart';
import '../../services/search_history_service.dart';
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
  late bool _useAccuracyMode;
  int _galleryColumns = 3;

  static const List<ModelVariant> _variants = [
    ModelVariant.kitakoFp32,
    ModelVariant.kitakoMixed,
    ModelVariant.kitakoInt8,
  ];

  static const _kColKey = 'gallery_columns';

  @override
  void initState() {
    super.initState();
    _useAccuracyMode = widget.searchService.preferHnsw ?? true;
    _loadGalleryColumns();
  }

  Future<void> _loadGalleryColumns() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() =>
          _galleryColumns = (prefs.getInt(_kColKey) ?? 3).clamp(2, 6));
    }
  }

  Future<void> _setGalleryColumns(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kColKey, count);
    if (mounted) setState(() => _galleryColumns = count);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _onVariantTap(ModelVariant variant) async {
    if (variant == widget.settingsController.selectedVariant) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch embedding model?'),
        content: Text(
          'Switch to ${variant.displayName}? The app will reload the model '
          'and may re-embed images if the vision encoder changed.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBlocking(
      title: 'Switching model',
      subtitle: 'Loading ${variant.displayName}…',
      action: () async {
        await widget.settingsController.setSelectedVariant(variant);
        final ok = await widget.searchService.switchVariant(variant);
        if (!ok) {
          throw StateError(
            'Failed to load ${variant.displayName}. '
            'Verify the ONNX files are present.',
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
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear')),
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

  Future<void> _onClearHistoryTap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear search history?'),
        content: const Text('All recent search queries will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    final hs = SearchHistoryService();
    await hs.load();
    await hs.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search history cleared'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg         = isDark ? const Color(0xFF0E1116) : const Color(0xFFF4F7FB);
    final surface    = isDark ? const Color(0xFF161B22) : Colors.white;
    final border     = isDark ? const Color(0xFF1F2733) : const Color(0xFFE2E8F0);
    final hairline   = isDark ? const Color(0x1F60A5FA) : const Color(0x192563EB);
    final blue       = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
    final blueSoft   = isDark ? const Color(0x2E3B82F6) : const Color(0xFFDBEAFE);
    final titleColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF0B2545);
    final textColor  = isDark ? Colors.white : const Color(0xFF0F172A);
    final textDim    = isDark ? const Color(0xC7FFFFFF) : const Color(0xFF475569);
    final textMore   = isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B);
    final textFaint  = isDark ? const Color(0x61FFFFFF) : const Color(0xFF94A3B8);
    final surfaceHigh= isDark ? const Color(0xFF222A36) : const Color(0xFFE2EAF4);
    final red        = isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

    final selected = widget.settingsController.selectedVariant;
    final isReady  = widget.searchService.embeddingService.isInitialized;
    final indexed  = widget.searchService.indexedImageCount;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: titleColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: titleColor,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: hairline,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // ── APPEARANCE ──────────────────────────────────────────────────────
          _SectionLabel(label: 'Appearance', blue: blue, textDim: textDim),
          _KKCard(
            surface: surface,
            border: border,
            isDark: isDark,
            children: [
              _KKRow(
                icon: Icons.dark_mode_outlined,
                label: 'Dark mode',
                sub: 'Match your system theme by default',
                right: _KKToggle(
                  on: widget.themeNotifier.isDarkMode,
                  blue: blue,
                  surfaceHigh: surfaceHigh,
                ),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
                onTap: () => widget.themeNotifier
                    .toggleTheme(!widget.themeNotifier.isDarkMode),
              ),
              // Gallery columns
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: blueSoft,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.grid_view, size: 16, color: blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gallery columns',
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          Text(
                              '$_galleryColumns column${_galleryColumns == 1 ? '' : 's'} · pinch to adjust',
                              style:
                                  TextStyle(color: textMore, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [2, 3, 4, 5, 6].map((n) {
                        final sel = n == _galleryColumns;
                        return GestureDetector(
                          onTap: () => _setGalleryColumns(n),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 30,
                            height: 30,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: sel ? blue : surfaceHigh,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: sel ? blue : border, width: 1.5),
                            ),
                            child: Center(
                              child: Text('$n',
                                  style: TextStyle(
                                    color:
                                        sel ? Colors.white : textColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── SEARCH ──────────────────────────────────────────────────────────
          _SectionLabel(label: 'Search', blue: blue, textDim: textDim),
          _KKCard(
            surface: surface,
            border: border,
            isDark: isDark,
            children: [
              // Search mode header + 2-col choice cards
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _iconBadge(Icons.gps_fixed, blue, blueSoft),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Search mode',
                                  style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              Text('Trade off recall against latency',
                                  style: TextStyle(
                                      color: textMore, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _KKChoiceCard(
                            label: 'Performance',
                            sub: 'IVF-PQ · faster',
                            icon: Icons.speed_outlined,
                            selected: !_useAccuracyMode,
                            blue: blue,
                            surface: surface,
                            border: border,
                            textColor: textColor,
                            textMore: textMore,
                            isDark: isDark,
                            onTap: () {
                              setState(() => _useAccuracyMode = false);
                              widget.searchService.setPreferredAlgorithm(false);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KKChoiceCard(
                            label: 'Accuracy',
                            sub: 'HNSW · higher recall',
                            icon: Icons.gps_fixed,
                            selected: _useAccuracyMode,
                            blue: blue,
                            surface: surface,
                            border: border,
                            textColor: textColor,
                            textMore: textMore,
                            isDark: isDark,
                            onTap: () {
                              setState(() => _useAccuracyMode = true);
                              widget.searchService.setPreferredAlgorithm(true);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: hairline),
              _KKRow(
                icon: Icons.language_outlined,
                label: 'Taglish normalization',
                sub: '"nagshopping aq" → "nag shopping ako"',
                right: _KKToggle(
                    on: true, blue: blue, surfaceHigh: surfaceHigh),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
              ),
              _KKRow(
                icon: Icons.history,
                label: 'Clear search history',
                sub: 'Remove all recent queries from this device',
                right:
                    Icon(Icons.chevron_right, size: 18, color: textFaint),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
                last: true,
                onTap: _onClearHistoryTap,
              ),
            ],
          ),

          // ── MODELS ──────────────────────────────────────────────────────────
          _SectionLabel(label: 'Models', blue: blue, textDim: textDim),
          _KKCard(
            surface: surface,
            border: border,
            isDark: isDark,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _iconBadge(Icons.memory, blue, blueSoft),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Embedding model',
                                  style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              Text('SigLIP image + text encoder pair',
                                  style: TextStyle(
                                      color: textMore, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var i = 0; i < _variants.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _KKChoiceCard(
                              label: const ['FP32', 'Hybrid', 'INT8'][i],
                              sub: const [
                                'Full precision',
                                'FP32 + INT8',
                                'Smallest'
                              ][i],
                              icon: const [
                                Icons.high_quality,
                                Icons.memory,
                                Icons.speed_outlined
                              ][i],
                              selected: selected == _variants[i],
                              blue: blue,
                              surface: surface,
                              border: border,
                              textColor: textColor,
                              textMore: textMore,
                              isDark: isDark,
                              onTap: () => _onVariantTap(_variants[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: hairline),
              _KKRow(
                icon: Icons.image_outlined,
                label: 'Image encoder',
                sub: 'kitako_image_encoder_fp32 · 190 MB',
                right: _KKStatusPill(
                    status: isReady ? 'Ready' : 'Missing',
                    isDark: isDark),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
              ),
              _KKRow(
                icon: Icons.search,
                label: 'Text encoder',
                sub: 'kitako_text_encoder_int8 · 23 MB',
                right: _KKStatusPill(
                    status: isReady ? 'Ready' : 'Missing',
                    isDark: isDark),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
                last: true,
              ),
            ],
          ),

          // ── INDEXING & STORAGE ───────────────────────────────────────────────
          _SectionLabel(
              label: 'Indexing & Storage', blue: blue, textDim: textDim),
          _KKCard(
            surface: surface,
            border: border,
            isDark: isDark,
            children: [
              _KKRow(
                icon: Icons.refresh,
                label: 'Re-index gallery',
                sub: '$indexed photo${indexed == 1 ? '' : 's'} indexed',
                right:
                    Icon(Icons.chevron_right, size: 18, color: textFaint),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
              ),
              _KKRow(
                icon: Icons.storage_outlined,
                label: 'Embedding cache',
                sub: 'Wipe cached embeddings to free space',
                right: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline, size: 14, color: red),
                    const SizedBox(width: 4),
                    Text('Clear',
                        style: TextStyle(
                            color: red,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
                last: true,
                onTap: _onClearCacheTap,
              ),
            ],
          ),

          // ── ABOUT ────────────────────────────────────────────────────────────
          _SectionLabel(label: 'About', blue: blue, textDim: textDim),
          _KKCard(
            surface: surface,
            border: border,
            isDark: isDark,
            children: [
              _KKRow(
                icon: Icons.info_outline,
                label: 'Version',
                sub: '2.0.0 · v2-system-ric',
                right: Text('build 142',
                    style: TextStyle(color: textMore, fontSize: 12)),
                blue: blue,
                blueSoft: blueSoft,
                textColor: textColor,
                textMore: textMore,
                hairline: hairline,
                last: true,
              ),
            ],
          ),

          if (kDebugMode) ...[
            _SectionLabel(label: 'Debug', blue: blue, textDim: textDim),
            _KKCard(
              surface: surface,
              border: border,
              isDark: isDark,
              children: [
                _KKRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Debug build',
                  sub: 'Model switching enabled in this build',
                  right: const SizedBox.shrink(),
                  blue: blue,
                  blueSoft: blueSoft,
                  textColor: textColor,
                  textMore: textMore,
                  hairline: hairline,
                  last: true,
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'KitaKo · semantic photo search · runs on-device',
            textAlign: TextAlign.center,
            style: TextStyle(color: textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _iconBadge(IconData icon, Color blue, Color blueSoft) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
          color: blueSoft, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 16, color: blue),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color blue;
  final Color textDim;

  const _SectionLabel(
      {required this.label, required this.blue, required this.textDim});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
                color: blue, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _KKCard extends StatelessWidget {
  final Color surface;
  final Color border;
  final bool isDark;
  final List<Widget> children;

  const _KKCard({
    required this.surface,
    required this.border,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0F2A4A).withValues(alpha: 0.04),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _KKRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final Widget right;
  final Color blue;
  final Color blueSoft;
  final Color textColor;
  final Color textMore;
  final Color hairline;
  final bool last;
  final VoidCallback? onTap;

  const _KKRow({
    required this.icon,
    required this.label,
    this.sub,
    required this.right,
    required this.blue,
    required this.blueSoft,
    required this.textColor,
    required this.textMore,
    required this.hairline,
    this.last = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: blueSoft,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                if (sub != null)
                  Text(sub!,
                      style: TextStyle(
                          color: textMore, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          right,
        ],
      ),
    );

    if (!last) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hairline)),
        ),
        child: content,
      );
    }

    if (onTap != null) {
      return InkWell(onTap: onTap, child: content);
    }
    return content;
  }
}

class _KKToggle extends StatelessWidget {
  final bool on;
  final Color blue;
  final Color surfaceHigh;

  const _KKToggle(
      {required this.on, required this.blue, required this.surfaceHigh});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 42,
      height: 26,
      decoration: BoxDecoration(
        color: on ? blue : surfaceHigh,
        borderRadius: BorderRadius.circular(13),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 3,
                  offset: Offset(0, 1))
            ],
          ),
        ),
      ),
    );
  }
}

class _KKChoiceCard extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final Color blue;
  final Color surface;
  final Color border;
  final Color textColor;
  final Color textMore;
  final bool isDark;
  final VoidCallback onTap;

  const _KKChoiceCard({
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.blue,
    required this.surface,
    required this.border,
    required this.textColor,
    required this.textMore,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? blue : (isDark ? surface : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? blue : border, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: selected ? Colors.white : blue),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                )),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : textMore,
                  fontSize: 11,
                )),
          ],
        ),
      ),
    );
  }
}

class _KKStatusPill extends StatelessWidget {
  final String status;
  final bool isDark;

  const _KKStatusPill({required this.status, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color bg;

    if (status == 'Ready') {
      color = isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
      bg = const Color(0x1F10B981);
    } else if (status == 'Loading') {
      color = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
      bg = const Color(0x24F59E0B);
    } else {
      color = isDark ? const Color(0x8CFFFFFF) : const Color(0xFF64748B);
      bg = isDark ? const Color(0xFF222A36) : const Color(0xFFF1F5F9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(status,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Full-screen modal shown while a blocking operation runs.
class _BlockingOverlay extends StatelessWidget {
  final String title;
  final String subtitle;

  const _BlockingOverlay({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF1F2733)),
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
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
              ),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF60A5FA), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
