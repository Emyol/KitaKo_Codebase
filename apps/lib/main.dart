import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/services/crash_logger.dart';
import 'src/ui/screens/startup_screen.dart';
import 'src/ui/screens/eula_screen.dart';
import 'src/ui/screens/permission_screen.dart';
import 'src/ui/theme/theme_notifier.dart';
import 'src/services/face_service.dart';
import 'src/services/image_search_service.dart';
import 'src/services/model_download_service.dart';
import 'src/state/settings_controller.dart';
import 'src/widgets/model_download_gate.dart';

/// KitaKo - Image Retrieval Mobile Application
/// Platform: Android & iOS
/// Orientation: Portrait only
void main() {
  // runZonedGuarded catches uncaught async errors that escape Flutter's
  // own error handling (e.g. errors from completers, timers, or isolates
  // that aren't awaited). Combined with the FlutterError + PlatformDispatcher
  // hooks installed below, this gives us three nets to catch crashes
  // before they take down the app.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize the on-disk crash log first so subsequent failures
    // during boot are captured.
    await CrashLogger.instance.init();

    // 1) Framework errors (build/render/layout/gestures).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashLogger.instance.log(
        'flutter',
        details.exception,
        details.stack,
        message: details.context?.toString(),
      );
    };

    // 2) Async errors that escape the Flutter framework (platform channels,
    // engine callbacks). Returning true marks the error as handled so the
    // engine doesn't terminate the isolate.
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashLogger.instance.log('platform', error, stack);
      return true;
    };

    // Lock app to portrait orientation for mobile
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Restore saved preferences (defaults on first launch).
    final themeNotifier = await ThemeNotifier.load();
    final settingsController = await SettingsController.load();

    // Print model diagnostics at startup (await so it shows before app loads)
    await ModelDownloadService().printModelSetupInstructions();

    runApp(KitaKoApp(
      themeNotifier: themeNotifier,
      settingsController: settingsController,
    ));
  }, (error, stack) {
    // 3) Last-resort net for anything the other two didn't catch.
    CrashLogger.instance.log('zone', error, stack);
  });
}

class KitaKoApp extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final SettingsController settingsController;

  const KitaKoApp({
    super.key,
    required this.themeNotifier,
    required this.settingsController,
  });

  @override
  State<KitaKoApp> createState() => _KitaKoAppState();
}

class _KitaKoAppState extends State<KitaKoApp> with WidgetsBindingObserver {
  late final ThemeNotifier _themeNotifier = widget.themeNotifier;
  late final SettingsController _settingsController = widget.settingsController;

  /// Face service — optional, gracefully disabled if models not present.
  final FaceService _faceService = FaceService();
  late final ImageSearchService _searchService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchService = ImageSearchService(faceService: _faceService);
    // Defer face init until the search service finishes its embedding pass.
    // Loading face ONNX sessions concurrently with the SigLIP embedding loop
    // (each image decode ~48 MB + the model itself ~625 MB) causes OOM.
    // We listen for the first terminal phase (ready or error) and only then
    // start the face pipeline, when the heavy buffers have been released.
    _searchService.indexingProgressStream
        .firstWhere((p) =>
            p.phase == IndexingPhase.ready ||
            p.phase == IndexingPhase.error)
        .then((_) async {
          // Load face models so they're ready when the user opens People.
          // Indexing itself is user-initiated from the People screen.
          await _faceService.tryAutoInitialize();
        })
        .ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeNotifier.dispose();
    _settingsController.dispose();
    _faceService.dispose();
    _searchService.dispose();
    super.dispose();
  }

  /// Android dispatches this when the OS is under memory pressure and is
  /// about to start killing background processes. Free non-essential
  /// in-memory buffers before we get killed.
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    debugPrint('KitaKoApp: memory pressure — releasing transient buffers');
    CrashLogger.instance.log(
      'lifecycle',
      'didHaveMemoryPressure',
      null,
      message: 'releasing transient buffers',
    );
    try {
      _searchService.releaseTransientMemory();
    } catch (e, s) {
      CrashLogger.instance.log('lifecycle', e, s,
          message: 'releaseTransientMemory failed');
    }
  }

  /// Track app foreground/background transitions. We do NOT release the
  /// ONNX session on `paused` — releasing OrtEnv prevents subsequent
  /// model loading and the session itself is mmap-backed so it costs
  /// little to keep. We only release transient caches when Android
  /// signals real memory pressure (via [didHaveMemoryPressure]).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('KitaKoApp: lifecycle → ${state.name}');
    if (state == AppLifecycleState.detached) {
      // OS is shutting us down. Flush whatever we can.
      try {
        _searchService.releaseTransientMemory();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeNotifier,
      builder: (context, _) {
        return MaterialApp(
          title: 'KitaKo',
          debugShowCheckedModeBanner: false,
          themeMode: _themeNotifier.themeMode,
          // Dark Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0E1116),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF3B82F6),
              secondary: Color(0xFF60A5FA),
              surface: Color(0xFF161B22),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0E1116),
              elevation: 0,
              centerTitle: false,
              iconTheme: IconThemeData(color: Color(0xFF60A5FA)),
              titleTextStyle: TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            dividerColor: const Color(0x1F60A5FA),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              hintStyle: const TextStyle(
                color: Color(0x8CFFFFFF),
                fontSize: 16,
              ),
            ),
          ),
          // Light Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F7FB),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              secondary: Color(0xFF3B82F6),
              surface: Color(0xFFFFFFFF),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF4F7FB),
              elevation: 0,
              centerTitle: false,
              iconTheme: IconThemeData(color: Color(0xFF0B2545)),
              titleTextStyle: TextStyle(
                color: Color(0xFF0B2545),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            dividerColor: const Color(0x192563EB),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              hintStyle: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 16,
              ),
            ),
          ),
          home: _AppGate(
            themeNotifier: _themeNotifier,
            searchService: _searchService,
            settingsController: _settingsController,
          ),
        );
      },
    );
  }
}

/// Gates the app through EULA acceptance before showing the startup/home flow.
class _AppGate extends StatefulWidget {
  final ThemeNotifier themeNotifier;
  final ImageSearchService searchService;
  final SettingsController settingsController;

  const _AppGate({
    required this.themeNotifier,
    required this.searchService,
    required this.settingsController,
  });

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  // null = still loading from SharedPreferences
  bool? _permissionsRequested;
  bool? _eulaAccepted;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _permissionsRequested =
            prefs.getBool('permissions_requested') ?? false;
        _eulaAccepted = prefs.getBool('eula_accepted') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Still loading prefs — show blank
    if (_permissionsRequested == null || _eulaAccepted == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // Step 1: permissions (shown once before anything else)
    if (!_permissionsRequested!) {
      return PermissionScreen(
        onComplete: () => setState(() => _permissionsRequested = true),
      );
    }

    // Step 2: EULA
    if (!_eulaAccepted!) {
      return EulaScreen(
        onAccepted: () => setState(() => _eulaAccepted = true),
      );
    }

    // Step 3: app
    return ModelDownloadGate(
      autoDownload: true,
      child: StartupScreen(
        themeNotifier: widget.themeNotifier,
        searchService: widget.searchService,
        settingsController: widget.settingsController,
      ),
    );
  }
}
