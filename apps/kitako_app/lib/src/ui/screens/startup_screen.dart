import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/embedding_service.dart';
import '../../services/image_search_service.dart';
import '../../state/settings_controller.dart';
import '../theme/theme_notifier.dart';
import 'home_screen.dart';

/// Gates access to the gallery until `ImageSearchService` finishes loading
/// models, restoring the cache, and embedding any new images.
///
/// Subscribes to [ImageSearchService.indexingProgressStream] and advances to
/// [HomeScreen] only when [IndexingPhase.ready] is emitted.
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
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  StreamSubscription<IndexingProgress>? _progressSub;
  IndexingProgress _progress =
      const IndexingProgress(phase: IndexingPhase.idle, message: 'Starting…');

  bool _navigated = false;
  bool _startTriggered = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _animationController.forward();

    _progress = widget.searchService.lastProgress;
    _progressSub =
        widget.searchService.indexingProgressStream.listen(_onProgress);

    // Kick off initialization after first frame so the animation is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInit());
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _animationController.dispose();
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
      // If init returned but we never saw a ready/error phase, synthesize one.
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
    if (p.phase == IndexingPhase.ready) {
      _goHome();
    }
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          themeNotifier: widget.themeNotifier,
          searchService: widget.searchService,
          settingsController: widget.settingsController,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _buildLogo(),
                const SizedBox(height: 32),
                _buildStatus(),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        width: 160,
        height: 160,
      ),
    );
  }

  Widget _buildStatus() {
    if (_progress.phase == IndexingPhase.error) {
      return Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE57373), size: 32),
          const SizedBox(height: 12),
          Text(
            _progress.message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFE57373), fontSize: 14),
          ),
          if (_progress.error != null) ...[
            const SizedBox(height: 6),
            Text(
              _progress.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      );
    }

    if (_progress.phase == IndexingPhase.embeddingPartialFailure) {
      final failed = _progress.failedCount ?? 0;
      return Column(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFFB74D), size: 32),
          const SizedBox(height: 12),
          Text(
            _progress.message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 14),
          ),
          if (_progress.error != null) ...[
            const SizedBox(height: 6),
            Text(
              _progress.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => widget.searchService
                    .continueAfterEmbeddingFailure(retry: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('Retry $failed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => widget.searchService
                    .continueAfterEmbeddingFailure(retry: false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                  side: const BorderSide(color: Color(0xFF444444)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                child: const Text('Skip'),
              ),
            ],
          ),
        ],
      );
    }

    final fraction = _progress.fraction;

    return Column(
      children: [
        SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: fraction,
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
            backgroundColor: const Color(0xFF2A2A2A),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _progress.message.isEmpty ? 'Starting…' : _progress.message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
        ),
        if (fraction != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: const Color(0xFF2A2A2A),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
            ),
          ),
        ],
      ],
    );
  }
}
