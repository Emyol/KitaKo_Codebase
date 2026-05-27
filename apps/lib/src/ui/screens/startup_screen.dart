import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/embedding_service.dart';
import '../../services/image_search_service.dart';
import '../../state/settings_controller.dart';
import '../theme/theme_notifier.dart';
import 'home_screen.dart';

// ── Theme palette ─────────────────────────────────────────────────────────────
// All colors that differ between dark and light mode live here. Pick a palette
// in build() via `widget.themeNotifier.isDarkMode` and pass it down.
class _Palette {
  // Background gradient stops
  final Color bgTop, bgBot;

  // Primary accent (rings, progress, dots)
  final Color blue;

  // Text
  final Color text, textMore, textFaint;
  final Color msgColor, pctColor;

  // Status card surface
  final Color surface, border;

  // Progress ring track
  final Color track;

  // Water-layer colors + opacities. Index 0 = deepest, 3 = shallowest.
  final List<Color> waterColors;
  final List<double> waterOpacities;

  // Mask color for the water vertical fade (matches bg).
  final Color waterMask;

  const _Palette({
    required this.bgTop,
    required this.bgBot,
    required this.blue,
    required this.text,
    required this.textMore,
    required this.textFaint,
    required this.msgColor,
    required this.pctColor,
    required this.surface,
    required this.border,
    required this.track,
    required this.waterColors,
    required this.waterOpacities,
    required this.waterMask,
  });
}

const _darkPalette = _Palette(
  bgTop:      Color(0xFF0B1220),
  bgBot:      Color(0xFF050811),
  blue:       Color(0xFF387DF4),
  text:       Color(0xFFFFFFFF),
  textMore:   Color(0x8CFFFFFF), // 0.55 alpha
  textFaint:  Color(0x61FFFFFF), // 0.38 alpha
  msgColor:   Color(0xB3FFFFFF), // 0.70 alpha
  pctColor:   Color(0xFF93C5FD),
  surface:    Color(0xFF161B22),
  border:     Color(0xFF1F2733),
  track:      Color(0x1AFFFFFF), // white @ 0.10
  waterColors: [
    Color(0xFF0B2545), // navy
    Color(0xFF1156CD), // blue-deep
    Color(0xFF387DF4), // blue
    Color(0xFF7BABFF), // blue-soft
  ],
  waterOpacities: [0.32, 0.26, 0.22, 0.18],
  waterMask: Color(0xFF000000),
);

const _lightPalette = _Palette(
  bgTop:      Color(0xFFFFFFFF),
  bgBot:      Color(0xFFFFFFFF),
  blue:       Color(0xFF1156CD),
  text:       Color(0xFF0F172A),
  textMore:   Color(0xFF64748B), // slate-500
  textFaint:  Color(0xFF94A3B8), // slate-400
  msgColor:   Color(0xFF475569), // slate-600
  pctColor:   Color(0xFF1D4ED8),
  surface:    Color(0xFFFFFFFF),
  border:     Color(0xFFE2E8F0),
  track:      Color(0x1A0F172A), // slate @ 0.10
  waterColors: [
    Color(0xFF1156CD),
    Color(0xFF387DF4),
    Color(0xFF7BABFF),
    Color(0xFFBFDBFE),
  ],
  waterOpacities: [0.10, 0.12, 0.18, 0.32],
  waterMask: Color(0xFFFFFFFF),
);

// Mode-independent status colors
const _kAmber = Color(0xFFF59E0B);
const _kRed   = Color(0xFFEF4444);

class StartupScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService searchService;
  final SettingsController settingsController;

  const StartupScreen({
    super.key,
    required this.themeNotifier,
    required this.searchService,
    required this.settingsController,
  });

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late AnimationController _loopCtrl;
  late AnimationController _dotCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  StreamSubscription<IndexingProgress>? _progressSub;
  IndexingProgress _progress =
      const IndexingProgress(phase: IndexingPhase.idle, message: 'Starting…');

  bool _navigated = false;
  bool _startTriggered = false;
  int _startTimeMs = 0;

  _Palette get _palette =>
      widget.themeNotifier.isDarkMode ? _darkPalette : _lightPalette;

  @override
  void initState() {
    super.initState();
    _startTimeMs = DateTime.now().millisecondsSinceEpoch;

    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _entryCtrl.forward();

    // Drives water repaints and ring spin at ~60 fps.
    _loopCtrl = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();

    // Cycles through 4 dot position sets; each set holds for ~4 s then crossfades.
    _dotCtrl = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _progress = widget.searchService.lastProgress;
    _progressSub =
        widget.searchService.indexingProgressStream.listen(_onProgress);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startInit());
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _entryCtrl.dispose();
    _loopCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  void _startInit() {
    if (_startTriggered) return;
    _startTriggered = true;

    widget.searchService
        .initialize(
      preferredVariant: widget.settingsController.selectedVariant,
      prewarmVariants: const [
        ModelVariant.kitakoFp32,
        ModelVariant.kitakoMixed,
      ],
    )
        .then((ok) {
      if (!mounted) return;
      if (_progress.phase != IndexingPhase.ready &&
          _progress.phase != IndexingPhase.error) {
        _onProgress(IndexingProgress(
          phase: ok ? IndexingPhase.ready : IndexingPhase.error,
          message: ok ? 'Ready' : 'Startup failed',
          error: ok ? null : 'initialize() returned false',
        ));
      }
    });
  }

  void _onProgress(IndexingProgress p) {
    if (!mounted) return;
    setState(() => _progress = p);
    if (p.phase == IndexingPhase.ready ||
        p.phase == IndexingPhase.embedding ||
        p.phase == IndexingPhase.loadingGallery) {
      _goHome();
    }
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => HomeScreen(
          themeNotifier: widget.themeNotifier,
          searchService: widget.searchService,
          settingsController: widget.settingsController,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
          child: child,
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _startTriggered = false;
      _progress = const IndexingProgress(
          phase: IndexingPhase.idle, message: 'Retrying…');
    });
    _startInit();
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      widget.searchService.continueAfterNoImages(directoryPath: path);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Rebuild on theme toggle so colors flip live.
    return AnimatedBuilder(
      animation: widget.themeNotifier,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final p = _palette;
    return Scaffold(
      body: Stack(
        children: [
          // Base gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.bgTop, p.bgBot],
                ),
              ),
            ),
          ),

          // Animated water layers at bottom
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: size.height * 0.46,
            child: _buildWater(p),
          ),

          // Animated accent dots — four position sets, slow crossfade cycle
          Positioned.fill(child: _buildAnimatedDots(size, p)),

          // Foreground content
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogoArea(),
                    const SizedBox(height: 56),
                    _buildStatusArea(p),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ambient helpers ────────────────────────────────────────────────────────

  Widget _buildWater(_Palette p) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, p.waterMask, p.waterMask],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: AnimatedBuilder(
        animation: _loopCtrl,
        builder: (_, _) => CustomPaint(
          painter: _WaterPainter(
            startTimeMs: _startTimeMs,
            colors: p.waterColors,
            opacities: p.waterOpacities,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // 4 position sets; each dot: (topF, bottomF, leftF, rightF, size, opacity)
  // Null fractions mean that edge is not constrained.
  static const _dotSets = [
    [ // set 0 — corners
      (top: 0.12, bot: null, lft: 0.16, rgt: null, sz: 4.0, op: 0.65),
      (top: 0.20, bot: null, lft: null, rgt: 0.18, sz: 3.0, op: 0.50),
      (top: null, bot: 0.22, lft: 0.13, rgt: null, sz: 5.0, op: 0.45),
      (top: null, bot: 0.14, lft: null, rgt: 0.26, sz: 3.0, op: 0.55),
      (top: 0.48, bot: null, lft: 0.07, rgt: null, sz: 3.0, op: 0.38),
    ],
    [ // set 1 — mid-edges
      (top: 0.08, bot: null, lft: 0.42, rgt: null, sz: 3.0, op: 0.55),
      (top: 0.34, bot: null, lft: 0.06, rgt: null, sz: 4.0, op: 0.50),
      (top: null, bot: 0.28, lft: null, rgt: 0.10, sz: 5.0, op: 0.45),
      (top: null, bot: 0.09, lft: 0.28, rgt: null, sz: 3.0, op: 0.60),
      (top: 0.26, bot: null, lft: null, rgt: 0.07, sz: 3.0, op: 0.42),
    ],
    [ // set 2 — scattered
      (top: 0.17, bot: null, lft: 0.58, rgt: null, sz: 5.0, op: 0.50),
      (top: 0.06, bot: null, lft: null, rgt: 0.32, sz: 3.0, op: 0.65),
      (top: null, bot: 0.19, lft: 0.44, rgt: null, sz: 4.0, op: 0.50),
      (top: null, bot: 0.34, lft: null, rgt: 0.14, sz: 3.0, op: 0.45),
      (top: 0.44, bot: null, lft: null, rgt: 0.42, sz: 4.0, op: 0.40),
    ],
    [ // set 3 — diagonal
      (top: 0.27, bot: null, lft: 0.09, rgt: null, sz: 5.0, op: 0.45),
      (top: 0.11, bot: null, lft: null, rgt: 0.11, sz: 4.0, op: 0.55),
      (top: null, bot: 0.11, lft: 0.33, rgt: null, sz: 3.0, op: 0.55),
      (top: null, bot: 0.27, lft: null, rgt: 0.36, sz: 4.0, op: 0.60),
      (top: 0.40, bot: null, lft: 0.32, rgt: null, sz: 3.0, op: 0.38),
    ],
  ];

  Widget _buildAnimatedDots(Size screen, _Palette p) {
    return AnimatedBuilder(
      animation: _dotCtrl,
      builder: (_, _) {
        // Map 0..1 → 0..4 across 4 sets; last 20% of each slot crossfades.
        final v = _dotCtrl.value * 4;
        final cur = v.floor() % 4;
        final nxt = (cur + 1) % 4;
        final pos = v - v.floor();
        final t = pos > 0.80 ? (pos - 0.80) / 0.20 : 0.0;

        final alphas = List.generate(4, (i) {
          if (i == cur) return 1.0 - t;
          if (i == nxt) return t;
          return 0.0;
        });

        final widgets = <Widget>[];
        for (var s = 0; s < _dotSets.length; s++) {
          final a = alphas[s];
          if (a <= 0) continue;
          for (final d in _dotSets[s]) {
            widgets.add(Positioned(
              top:    d.top != null ? screen.height * d.top! : null,
              bottom: d.bot != null ? screen.height * d.bot! : null,
              left:   d.lft != null ? screen.width  * d.lft! : null,
              right:  d.rgt != null ? screen.width  * d.rgt! : null,
              child: Opacity(
                opacity: a,
                child: Container(
                  width: d.sz, height: d.sz,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.blue.withValues(alpha: d.op),
                    boxShadow: [
                      BoxShadow(
                        color: p.blue.withValues(alpha: d.op * 0.6),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ));
          }
        }
        return Stack(children: widgets);
      },
    );
  }

  // ── Logo ───────────────────────────────────────────────────────────────────

  Widget _buildLogoArea() {
    const logoSize = 180.0;
    return AnimatedBuilder(
      animation: _entryCtrl,
      builder: (_, child) => Opacity(
        opacity: _fadeAnim.value,
        child: Transform.scale(scale: _scaleAnim.value, child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: SvgPicture.asset(
          'assets/images/logo.svg',
          width: logoSize, height: logoSize,
        ),
      ),
    );
  }

  // ── Status area ────────────────────────────────────────────────────────────

  Widget _buildStatusArea(_Palette p) {
    if (_progress.phase == IndexingPhase.error) {
      return _StatusCard(
        palette: p,
        icon: Icons.error_outline_rounded,
        iconColor: _kRed,
        message: _progress.message,
        detail: _progress.error,
        actions: SizedBox(
          width: double.infinity,
          child: _PillButton(
            palette: p,
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onPressed: _retry,
          ),
        ),
      );
    }

    if (_progress.phase == IndexingPhase.noImagesFound) {
      return _StatusCard(
        palette: p,
        icon: Icons.photo_library_outlined,
        iconColor: _kAmber,
        message: 'No images found',
        detail: 'We couldn\'t find any images on this device. '
            'You can browse your files to select a folder.',
        actions: Row(
          children: [
            Expanded(
              child: _PillButton(
                palette: p,
                label: 'Browse',
                icon: Icons.folder_open_rounded,
                onPressed: _pickDirectory,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PillButton.outlined(
                palette: p,
                label: 'Skip',
                onPressed: () => widget.searchService
                    .continueAfterNoImages(),
              ),
            ),
          ],
        ),
      );
    }

    if (_progress.phase == IndexingPhase.embeddingPartialFailure) {
      final failed = _progress.failedCount ?? 0;
      return _StatusCard(
        palette: p,
        icon: Icons.warning_amber_rounded,
        iconColor: _kAmber,
        message: _progress.message,
        detail: _progress.error,
        actions: Row(
          children: [
            Expanded(
              child: _PillButton(
                palette: p,
                label: 'Retry $failed',
                icon: Icons.refresh_rounded,
                onPressed: () => widget.searchService
                    .continueAfterEmbeddingFailure(retry: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PillButton.outlined(
                palette: p,
                label: 'Skip',
                onPressed: () => widget.searchService
                    .continueAfterEmbeddingFailure(retry: false),
              ),
            ),
          ],
        ),
      );
    }

    return _buildNormalProgress(p);
  }

  String _friendlyMessage() {
    final done = _progress.done;
    final total = _progress.total;
    return switch (_progress.phase) {
      IndexingPhase.idle             => 'Getting ready…',
      IndexingPhase.loadingModel     => 'Loading AI models…',
      IndexingPhase.prewarmingVariants => 'Checking models…',
      IndexingPhase.restoringCache   => 'Picking up where we left off…',
      IndexingPhase.loadingGallery   => 'Scanning your gallery…',
      IndexingPhase.noImagesFound    => 'No images found…',
      IndexingPhase.embedding        => done != null && total != null
          ? 'Organizing your photos · $done / $total'
          : 'Organizing your photos…',
      IndexingPhase.savingCache      => 'Saving your photo index…',
      IndexingPhase.switchingVariant => 'Switching models…',
      _ => _progress.message.isEmpty ? 'Starting…' : _progress.message,
    };
  }

  Widget _buildNormalProgress(_Palette p) {
    final fraction = _progress.fraction;
    final message = _friendlyMessage();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _loopCtrl,
          builder: (_, _) => CustomPaint(
            painter: _RingPainter(
              fraction: fraction,
              spinAngle: fraction == null
                  ? _loopCtrl.value * 2 * math.pi
                  : 0.0,
              trackColor: p.track,
              progressColor: p.blue,
            ),
            size: const Size(36, 36),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: p.msgColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (fraction != null) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                backgroundColor: p.track,
                valueColor: AlwaysStoppedAnimation<Color>(p.blue),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(fraction * 100).round()}%',
            style: TextStyle(
              color: p.pctColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double? fraction;
  final double spinAngle;
  final Color trackColor;
  final Color progressColor;

  const _RingPainter({
    required this.fraction,
    required this.spinAngle,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const r = 16.0;
    const sw = 2.5;

    canvas.drawCircle(
      center, r,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );

    final sweep = fraction != null
        ? fraction! * 2 * math.pi
        : math.pi / 2; // 25% arc for indeterminate

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      spinAngle - math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      fraction != old.fraction ||
      spinAngle != old.spinAngle ||
      trackColor != old.trackColor ||
      progressColor != old.progressColor;
}

// Four layered water waves animated at different speeds.
// Each layer draws two tile-widths of cubic-bezier wave then translates
// left by its time offset, creating a seamless horizontal loop.
class _WaterPainter extends CustomPainter {
  final int startTimeMs;
  final List<Color> colors;
  final List<double> opacities;

  const _WaterPainter({
    required this.startTimeMs,
    required this.colors,
    required this.opacities,
  });

  // (durationSec, reverse, pathIndex) per layer
  static const _layerMotion = [
    (38, false, 0),
    (28, true,  1),
    (20, false, 2),
    (14, true,  3),
  ];

  // Normalized wave shape per path: (baseY, c1Y, c2Y) as fractions of wave height.
  static const _shapes = [
    (0.50, 0.20, 0.80),
    (0.55, 0.30, 0.85),
    (0.45, 0.15, 0.75),
    (0.60, 0.35, 0.90),
  ];

  // Wave height as fraction of container (46% screen) height.
  static const _hFracs = [0.54, 0.43, 0.32, 0.23];

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = DateTime.now().millisecondsSinceEpoch - startTimeMs;

    for (var i = 0; i < _layerMotion.length; i++) {
      final (dur, rev, pIdx) = _layerMotion[i];
      final (baseY, c1Y, c2Y) = _shapes[pIdx];
      final waveH = size.height * _hFracs[i];
      final yOff = size.height - waveH;
      final t = (elapsed % (dur * 1000)) / (dur * 1000);
      final offset = (rev ? 1.0 - t : t) * size.width;

      canvas.drawPath(
        _buildWave(size.width, size.height, waveH, yOff,
            baseY, c1Y, c2Y, offset),
        Paint()
          ..color = colors[i].withValues(alpha: opacities[i])
          ..style = PaintingStyle.fill,
      );
    }
  }

  static Path _buildWave(
    double w, double canvasH, double waveH, double yOff,
    double baseY, double c1Y, double c2Y,
    double offset,
  ) {
    final path = Path();
    final period = w / 4; // 4 crests per tile
    final sx = -offset;

    path.moveTo(sx, yOff + baseY * waveH);
    for (var tile = 0; tile < 2; tile++) {
      final tx = sx + tile * w;
      for (var i = 0; i < 4; i++) {
        final x0 = tx + i * period;
        path.cubicTo(
          x0 + period / 3,     yOff + c1Y * waveH,
          x0 + 2 * period / 3, yOff + c2Y * waveH,
          x0 + period,         yOff + baseY * waveH,
        );
      }
    }
    path.lineTo(sx + 2 * w, canvasH);
    path.lineTo(sx, canvasH);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_) => true;
}

// ── Status card (error / partial-failure) ──────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final _Palette palette;
  final IconData icon;
  final Color iconColor;
  final String message;
  final String? detail;
  final Widget actions;

  const _StatusCard({
    required this.palette,
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.detail,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textFaint, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          actions,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final _Palette palette;
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool _outlined;

  const _PillButton({
    required this.palette,
    required this.label,
    this.icon,
    required this.onPressed,
  }) : _outlined = false;

  const _PillButton.outlined({
    required this.palette,
    required this.label,
    required this.onPressed,
  })  : icon = null,
        _outlined = true;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );
    const padding = EdgeInsets.symmetric(vertical: 12);

    if (_outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textMore,
          side: BorderSide(color: palette.border),
          padding: padding,
          shape: shape,
        ),
        child: Text(label),
      );
    }

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.blue,
          foregroundColor: Colors.white,
          padding: padding,
          shape: shape,
        ),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.blue,
        foregroundColor: Colors.white,
        padding: padding,
        shape: shape,
      ),
      child: Text(label),
    );
  }
}
