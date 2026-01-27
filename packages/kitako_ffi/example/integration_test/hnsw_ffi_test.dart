/// Flutter integration test for HNSW ANN with native FFI
///
/// Run with: flutter test integration_test/hnsw_ffi_test.dart
/// Or for a specific device: flutter test integration_test/hnsw_ffi_test.dart -d windows

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_ffi/kitako_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('HNSW FFI Integration Tests', () {
    late KitakoFfi ffi;

    setUpAll(() {
      ffi = KitakoFfi();
    });

    test('FFI library loads successfully', () {
      expect(ffi, isNotNull);
    });

    test('ANN functions are available', () {
      expect(ffi.isAnnAvailable, isTrue,
          reason: 'Native library should have HNSW support compiled in');
    });

    test('dummy embedding returns 768 dimensions', () {
      final embedding = ffi.dummyEmbedding768();
      expect(embedding, isNotNull);
      expect(embedding!.length, equals(768));
    });

    group('ANN Index Operations', () {
      late dynamic handle;
      const int dimensions = 768;
      const int numVectors = 100;

      setUp(() {
        handle = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
      });

      tearDown(() {
        ffi.annFree(handle);
      });

      test('creates ANN index handle', () {
        expect(handle, isNotNull);
      });

      test('initializes index with parameters', () {
        ffi.annInitIndex(handle, maxElements: numVectors, M: 16, efConstruction: 100);
        expect(ffi.annGetDim(handle), equals(dimensions));
        expect(ffi.annGetCount(handle), equals(0));
      });

      test('adds items and retrieves count', () {
        ffi.annInitIndex(handle, maxElements: numVectors, M: 16, efConstruction: 100);

        // Add 10 test vectors
        for (int i = 0; i < 10; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        expect(ffi.annGetCount(handle), equals(10));
      });

      test('searches for nearest neighbors', () {
        ffi.annInitIndex(handle, maxElements: numVectors, M: 16, efConstruction: 100);

        // Add vectors
        final vectors = <int, Float32List>{};
        for (int i = 0; i < 50; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          vectors[i] = vec;
          ffi.annAddItem(handle, vec, i);
        }

        // Search with vector #25 as query
        final query = vectors[25]!;
        final results = ffi.annSearch(handle, query, 5);

        expect(results, isNotEmpty);
        expect(results.length, equals(5));

        // Top result should be the query itself
        expect(results.first.id, equals(25));
        expect(results.first.distance, closeTo(0.0, 0.001));
      });

      test('sets efSearch parameter', () {
        ffi.annInitIndex(handle, maxElements: numVectors, M: 16, efConstruction: 100);

        // Add some vectors
        for (int i = 0; i < 20; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        // Set higher efSearch for better recall
        ffi.annSetEf(handle, 200);

        // Search should still work
        final query = _createNormalizedVector(dimensions, seed: 10);
        final results = ffi.annSearch(handle, query, 5);
        expect(results, isNotEmpty);
      });
    });

    group('Index Persistence', () {
      const int dimensions = 768;

      test('saves and loads index', () async {
        // Create and populate index
        final handle1 = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annInitIndex(handle1, maxElements: 100, M: 16, efConstruction: 100);

        final vectors = <int, Float32List>{};
        for (int i = 0; i < 50; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          vectors[i] = vec;
          ffi.annAddItem(handle1, vec, i);
        }

        // Save to temp file
        final tempDir = Directory.systemTemp.createTempSync('hnsw_ffi_test_');
        final indexPath = '${tempDir.path}/test_index.bin';

        ffi.annSave(handle1, indexPath);
        expect(File(indexPath).existsSync(), isTrue);

        ffi.annFree(handle1);

        // Load in new handle
        final handle2 = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annLoad(handle2, indexPath);
        expect(ffi.annGetCount(handle2), equals(50));
        expect(ffi.annGetDim(handle2), equals(dimensions));

        // Verify search works on loaded index
        final query = vectors[25]!;
        final results = ffi.annSearch(handle2, query, 5);
        expect(results.first.id, equals(25));

        ffi.annFree(handle2);

        // Cleanup
        tempDir.deleteSync(recursive: true);
      });
    });

    group('Space Types', () {
      const int dimensions = 128; // Smaller for faster tests

      test('Inner Product space', () {
        final handle = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annInitIndex(handle, maxElements: 10, M: 16, efConstruction: 50);

        for (int i = 0; i < 5; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        final query = _createNormalizedVector(dimensions, seed: 2);
        final results = ffi.annSearch(handle, query, 3);
        expect(results.first.id, equals(2));

        ffi.annFree(handle);
      });

      test('L2 (Euclidean) space', () {
        final handle = ffi.annCreate(dimensions, AnnSpaceType.l2);
        ffi.annInitIndex(handle, maxElements: 10, M: 16, efConstruction: 50);

        for (int i = 0; i < 5; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        final query = _createNormalizedVector(dimensions, seed: 2);
        final results = ffi.annSearch(handle, query, 3);
        expect(results.first.id, equals(2));

        ffi.annFree(handle);
      });

      test('Cosine space', () {
        final handle = ffi.annCreate(dimensions, AnnSpaceType.cosine);
        ffi.annInitIndex(handle, maxElements: 10, M: 16, efConstruction: 50);

        for (int i = 0; i < 5; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        final query = _createNormalizedVector(dimensions, seed: 2);
        final results = ffi.annSearch(handle, query, 3);
        expect(results.first.id, equals(2));

        ffi.annFree(handle);
      });
    });

    group('Edge Cases', () {
      const int dimensions = 768;

      test('search on empty index returns empty results', () {
        final handle = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annInitIndex(handle, maxElements: 10, M: 16, efConstruction: 50);

        final query = _createNormalizedVector(dimensions, seed: 0);
        final results = ffi.annSearch(handle, query, 5);

        expect(results, isEmpty);

        ffi.annFree(handle);
      });

      test('search with k > count returns available items', () {
        final handle = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annInitIndex(handle, maxElements: 10, M: 16, efConstruction: 50);

        // Add only 3 items
        for (int i = 0; i < 3; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        // Request 10 results
        final query = _createNormalizedVector(dimensions, seed: 1);
        final results = ffi.annSearch(handle, query, 10);

        expect(results.length, equals(3));

        ffi.annFree(handle);
      });

      test('handles large index', () {
        final handle = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annInitIndex(handle, maxElements: 1000, M: 16, efConstruction: 100);

        // Add 500 vectors
        for (int i = 0; i < 500; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          ffi.annAddItem(handle, vec, i);
        }

        expect(ffi.annGetCount(handle), equals(500));

        // Search should still be fast
        final stopwatch = Stopwatch()..start();
        final query = _createNormalizedVector(dimensions, seed: 250);
        final results = ffi.annSearch(handle, query, 10);
        stopwatch.stop();

        expect(results.first.id, equals(250));
        expect(stopwatch.elapsedMilliseconds, lessThan(100),
            reason: 'Search should complete in under 100ms');

        ffi.annFree(handle);
      });
    });

    group('Recall Quality', () {
      test('achieves high recall on structured data', () {
        const int dimensions = 128;
        const int numVectors = 200;
        
        final handle = ffi.annCreate(dimensions, AnnSpaceType.innerProduct);
        ffi.annInitIndex(handle, maxElements: numVectors, M: 32, efConstruction: 200);

        // Create clustered vectors for predictable neighbors
        final vectors = <int, Float32List>{};
        for (int i = 0; i < numVectors; i++) {
          final vec = _createNormalizedVector(dimensions, seed: i);
          vectors[i] = vec;
          ffi.annAddItem(handle, vec, i);
        }

        // Set high efSearch for best recall
        ffi.annSetEf(handle, 100);

        // Test multiple queries
        int correctTopResults = 0;
        for (int queryId = 0; queryId < 20; queryId++) {
          final query = vectors[queryId]!;
          final results = ffi.annSearch(handle, query, 1);
          if (results.isNotEmpty && results.first.id == queryId) {
            correctTopResults++;
          }
        }

        // Should find exact match for all queries
        expect(correctTopResults, equals(20),
            reason: 'HNSW should find exact match when query is in index');

        ffi.annFree(handle);
      });
    });
  });
}

/// Creates a normalized vector with pseudo-random values based on seed
Float32List _createNormalizedVector(int dimensions, {required int seed}) {
  final vec = Float32List(dimensions);
  double norm = 0;

  for (int j = 0; j < dimensions; j++) {
    vec[j] = ((seed * 17 + j * 31) % 1000 - 500) / 500.0;
    norm += vec[j] * vec[j];
  }

  // L2 normalize
  norm = norm > 0 ? 1.0 / math.sqrt(norm) : 1.0;
  for (int j = 0; j < dimensions; j++) {
    vec[j] *= norm;
  }

  return vec;
}
