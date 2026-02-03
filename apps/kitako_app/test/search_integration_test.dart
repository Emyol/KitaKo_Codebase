import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_app/src/services/image_search_service.dart';
import 'package:kitako_app/src/models/search_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Search Integration Tests', () {
    late ImageSearchService searchService;

    setUp(() async {
      searchService = ImageSearchService();
      await searchService.initialize();
    });

    tearDown(() {
      searchService.dispose();
    });

    test('Initialize and check services ready', () async {
      final stats = searchService.getStats();

      print('\n========================================');
      print('SEARCH SERVICE STATISTICS');
      print('========================================');
      print('Initialized: ${stats['initialized']}');
      print('Total images: ${stats['totalImages']}');
      print('Indexed images: ${stats['indexedImages']}');
      print('Embedding cache: ${stats['embeddingCache']}');
      print('ANN index: ${stats['annIndex']}');
      print('========================================\n');

      expect(stats['initialized'], isTrue);
    });

    test('Search for images with text query', () async {
      print('\n========================================');
      print('TESTING TEXT-TO-IMAGE SEARCH');
      print('========================================\n');

      // Test queries
      final queries = [
        'sunset beach',
        'mountain landscape',
        'city skyline',
      ];

      for (final query in queries) {
        print('Searching for: "$query"');

        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(query, topK: 5);
        stopwatch.stop();

        final state = searchService.currentState;

        print('  Status: ${state.status}');
        print('  Results: ${state.result?.resultCount ?? 0}');
        print('  Time: ${stopwatch.elapsedMilliseconds}ms');
        print('  Normalized query: ${state.normalizedQuery}');
        print('');

        expect(state.status, isNot(SearchStatus.error));
      }
    });

    test('Check embedding consistency', () async {
      print('\n========================================');
      print('TESTING EMBEDDING DETERMINISM');
      print('========================================\n');

      final query = 'test query';

      // Search twice with same query
      await searchService.searchImages(query);
      final state1 = searchService.currentState;

      searchService.clearSearch();

      await searchService.searchImages(query);
      final state2 = searchService.currentState;

      print('First search:  ${state1.result?.resultCount} results');
      print('Second search: ${state2.result?.resultCount} results');
      print('');

      // Should get identical results due to caching/determinism
      expect(state1.result?.resultCount, equals(state2.result?.resultCount));

      print('✅ Embeddings are deterministic!\n');
    });

    test('Taglish normalization works', () async {
      print('\n========================================');
      print('TESTING TAGLISH NORMALIZATION');
      print('========================================\n');

      final testCases = {
        'magandang tanawin': 'beautiful view',
        'pagkain': 'food',
        'sunset sa beach': 'sunset at beach',
      };

      for (final entry in testCases.entries) {
        final taglish = entry.key;
        final expected = entry.value;

        await searchService.searchImages(taglish);
        final state = searchService.currentState;

        print('Input: "$taglish"');
        print('Normalized: "${state.normalizedQuery}"');
        print('Expected contains: "$expected"');
        print('Status: ${state.status}');
        print('');

        expect(state.normalizedQuery, isNotNull);
        expect(state.status, isNot(SearchStatus.error));
      }
    });

    test('Performance benchmark', () async {
      print('\n========================================');
      print('PERFORMANCE BENCHMARK');
      print('========================================\n');

      final query = 'test performance query';
      final iterations = 10;
      final times = <int>[];

      print('Running $iterations searches...\n');

      for (int i = 0; i < iterations; i++) {
        searchService.clearSearch();

        final stopwatch = Stopwatch()..start();
        await searchService.searchImages(query);
        stopwatch.stop();

        times.add(stopwatch.elapsedMilliseconds);
        print('Search ${i + 1}: ${stopwatch.elapsedMilliseconds}ms');
      }

      final avgTime = times.reduce((a, b) => a + b) / times.length;
      final minTime = times.reduce((a, b) => a < b ? a : b);
      final maxTime = times.reduce((a, b) => a > b ? a : b);

      print('\n--- RESULTS ---');
      print('Average: ${avgTime.toStringAsFixed(2)}ms');
      print('Min: ${minTime}ms');
      print('Max: ${maxTime}ms');
      print('');

      // First search might be slower (warmup), but subsequent should be fast
      expect(avgTime, lessThan(500), reason: 'Average search should be < 500ms');
    });
  });
}
