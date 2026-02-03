import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/ui/screens/startup_screen.dart';
import 'src/ui/theme/theme_notifier.dart';
import 'src/services/image_search_service.dart';
import 'src/services/model_download_service.dart';
import 'src/widgets/model_download_gate.dart';

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
  final ImageSearchService _searchService = ImageSearchService();

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
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
          // Dark Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF1A1A1A),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4A90E2),
              secondary: Color(0xFF5BA3F5),
              surface: Color(0xFF2A2A2A),
              background: Color(0xFF1A1A1A),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1A1A1A),
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: Color(0xFF1E3A5F),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              hintStyle: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 16,
              ),
            ),
          ),
          // Light Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4A90E2),
              secondary: Color(0xFF5BA3F5),
              surface: Colors.white,
              background: Color(0xFFF5F5F5),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F5F5),
              elevation: 0,
              centerTitle: false,
              iconTheme: IconThemeData(color: Color(0xFF1E3A5F)),
              titleTextStyle: TextStyle(
                color: Color(0xFF1E3A5F),
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
            autoDownload: true, // Auto-download on first launch
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
