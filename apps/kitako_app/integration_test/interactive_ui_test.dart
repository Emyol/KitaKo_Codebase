import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_app/main.dart';
import 'package:kitako_app/src/ui/screens/home_screen.dart';

/// Interactive UI Test - Full Dry Run
///
/// This launches the real app and keeps it running for 5 MINUTES
/// so you can:
/// 1. Wait for full image indexing to complete
/// 2. Navigate through the UI manually
/// 3. Enter your own search queries
/// 4. See real search results
///
/// Run on device: flutter test integration_test/interactive_ui_test.dart -d [device_id]
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void log(String message) {
    debugPrint('[DryRun] $message');
  }

  group('KitaKo Dry Run', () {
    testWidgets('Full app dry run - 5 minute interactive session', (tester) async {
      log('');
      log('════════════════════════════════════════════════════════════');
      log(' KITAKO DRY RUN - FULL INTERACTIVE SESSION');
      log('════════════════════════════════════════════════════════════');
      log('');
      log('This will run the app for 5 MINUTES so you can:');
      log('  ✓ Wait for all images to fully index');
      log('  ✓ Navigate through the app');
      log('  ✓ Enter your own search queries');
      log('  ✓ See real search results');
      log('');
      log('Watch the console for indexing progress...');
      log('');

      // Launch the actual app
      await tester.pumpWidget(const KitaKoApp());
      log('✓ App launched');

      // Keep pumping to let the app run and index
      const totalMinutes = 5;
      const totalSeconds = totalMinutes * 60;

      for (var i = 0; i < totalSeconds; i++) {
        await tester.pump(const Duration(seconds: 1));

        // Status updates
        if (i == 5) {
          final homeScreen = find.byType(HomeScreen);
          if (homeScreen.evaluate().isNotEmpty) {
            log('✓ Home screen displayed');
          }
        }

        // Log every 30 seconds
        if (i > 0 && i % 30 == 0) {
          final minutes = (totalSeconds - i) ~/ 60;
          final seconds = (totalSeconds - i) % 60;
          log('⏱️  ${minutes}m ${seconds}s remaining - Interact with app now!');
        }
      }

      log('');
      log('════════════════════════════════════════════════════════════');
      log(' DRY RUN COMPLETE');
      log('════════════════════════════════════════════════════════════');
    });
  });
}
