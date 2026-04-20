import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/ui/screens/startup_screen.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/theme/theme_notifier.dart';
import 'src/services/image_search_service.dart';
import 'src/services/face_service.dart';
import 'src/services/model_download_service.dart';
import 'src/ui/widgets/model_download_gate.dart';

/// KitaKo - Image Retrieval Mobile Application
/// Platform: Android & iOS
/// Orientation: Portrait only
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app to portrait orientation for mobile
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Print model setup instructions for development
  ModelDownloadService().printModelSetupInstructions();

  runApp(const KitaKoApp());
}

class KitaKoApp extends StatefulWidget {
  const KitaKoApp({super.key});

  @override
  State<KitaKoApp> createState() => _KitaKoAppState();
}

class _KitaKoAppState extends State<KitaKoApp> {
  final ThemeNotifier _themeNotifier = ThemeNotifier();
  final FaceService _faceService = FaceService();
  late final ImageSearchService _searchService;

  @override
  void initState() {
    super.initState();
    _searchService = ImageSearchService(faceService: _faceService);
    _initializeService();
  }

  Future<void> _initializeService() async {
    // Try to auto-initialize face recognition (non-blocking).
    // If models aren't present, _faceService.isAvailable will be false
    // and all face features silently disable.
    await _faceService.tryAutoInitialize();

    await _searchService.initialize();
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    _searchService.dispose();
    super.dispose();
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
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppColors.background,
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              secondary: AppColors.primaryLight,
              surface: AppColors.surface,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.background,
              elevation: 0,
              centerTitle: false,
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ),
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              secondary: AppColors.primaryLight,
              surface: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F5F5),
              elevation: 0,
              centerTitle: false,
              iconTheme: IconThemeData(color: AppColors.primaryDark),
              titleTextStyle: TextStyle(
                color: AppColors.primaryDark,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              hintStyle: const TextStyle(
                color: Color(0xFF999999),
                fontSize: 16,
              ),
            ),
          ),
          home: ModelDownloadGate(
            autoDownload: true,
            child: StartupScreen(
              themeNotifier: _themeNotifier,
              searchService: _searchService,
            ),
          ),
        );
      },
    );
  }
}
