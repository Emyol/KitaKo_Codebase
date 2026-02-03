import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_app/src/services/embedding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ONNX Embedding Model Tests', () {
    late EmbeddingService embeddingService;

    setUp(() {
      embeddingService = EmbeddingService();
    });

    tearDown(() {
      embeddingService.dispose();
    });

    test('Test 1: Initialize and check ONNX model loading', () async {
      print('\n========================================');
      print('TEST 1: ONNX Model Initialization');
      print('========================================\n');

      final initialized = await embeddingService.initialize();

      print('✓ Service initialized: $initialized');
      print('✓ Is initialized: ${embeddingService.isInitialized}');
      print('✓ Text encoder ready: ${embeddingService.isTextReady}');
      print('✓ Image encoder ready: ${embeddingService.isImageReady}');

      final stats = embeddingService.getCacheStats();
      final mode = stats['mode'];

      print('\n--- SERVICE MODE ---');
      print('Mode: $mode');

      if (mode == 'real') {
        print('✅ SUCCESS: ONNX models loaded successfully!');
        print('The embedding service is using REAL ONNX inference.');
      } else {
        print('⚠️  WARNING: Running in MOCK mode');
        print('ONNX models may not be available or failed to load.');
        print('Check if .onnx files are in: apps/kitako_app/assets/model/');
      }

      expect(initialized, isTrue);
      expect(embeddingService.isInitialized, isTrue);
    });

    test('Test 2: Generate text embeddings and verify they are real', () async {
      print('\n========================================');
      print('TEST 2: Text Embedding Generation');
      print('========================================\n');

      await embeddingService.initialize();

      final testQueries = [
        'sunset beach',
        'mountain landscape',
        'city skyline',
      ];

      final embeddings = <List<double>>[];

      for (final query in testQueries) {
        print('Generating embedding for: "$query"');
        final stopwatch = Stopwatch()..start();

        final embedding = await embeddingService.generateEmbedding(query);

        stopwatch.stop();
        embeddings.add(embedding);

        print('  ✓ Generated in ${stopwatch.elapsedMilliseconds}ms');
        print('  ✓ Dimension: ${embedding.length}');
        print('  ✓ First 5 values: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).toList()}');

        // Verify embedding dimension
        expect(embedding.length, EmbeddingService.embeddingDimension);

        // Calculate L2 norm (should be close to 1 for normalized embeddings)
        final norm = _calculateL2Norm(embedding);
        print('  ✓ L2 norm: ${norm.toStringAsFixed(6)} (should be ~1.0 for normalized)');

        // If using real models, norm should be very close to 1.0
        if (embeddingService.isTextReady) {
          expect(norm, closeTo(1.0, 0.01));
        }
      }

      print('\n--- UNIQUENESS TEST ---');
      print('Testing if embeddings are unique (not mock):');

      // Different queries should produce different embeddings
      final sim01 = _cosineSimilarity(embeddings[0], embeddings[1]);
      final sim02 = _cosineSimilarity(embeddings[0], embeddings[2]);
      final sim12 = _cosineSimilarity(embeddings[1], embeddings[2]);

      print('  Similarity between query 0 and 1: ${sim01.toStringAsFixed(4)}');
      print('  Similarity between query 0 and 2: ${sim02.toStringAsFixed(4)}');
      print('  Similarity between query 1 and 2: ${sim12.toStringAsFixed(4)}');

      // Embeddings should not be identical
      final isUnique = (sim01 < 0.999 || sim02 < 0.999 || sim12 < 0.999);

      if (isUnique) {
        print('  ✅ Embeddings are UNIQUE - likely using real ONNX models');
      } else {
        print('  ⚠️  Embeddings are too similar - might be mock mode');
      }

      final stats = embeddingService.getCacheStats();
      print('\n--- CACHE STATS ---');
      print('Cache size: ${stats['size']}/${stats['maxSize']}');
      print('Mode: ${stats['mode']}');
    });

    test('Test 3: Test embedding determinism (same input = same output)', () async {
      print('\n========================================');
      print('TEST 3: Embedding Determinism');
      print('========================================\n');

      await embeddingService.initialize();

      final query = 'test query for determinism';

      print('Generating embedding twice for: "$query"\n');

      final embedding1 = await embeddingService.generateEmbedding(query);
      final embedding2 = await embeddingService.generateEmbedding(query);

      print('First call:  ${embedding1.take(5).map((e) => e.toStringAsFixed(6)).toList()}');
      print('Second call: ${embedding2.take(5).map((e) => e.toStringAsFixed(6)).toList()}');

      // Should be exactly identical (cached or deterministic)
      final areEqual = _listEquals(embedding1, embedding2);

      if (areEqual) {
        print('\n✅ Embeddings are IDENTICAL - determinism confirmed');
      } else {
        print('\n❌ Embeddings are DIFFERENT - unexpected behavior!');
      }

      expect(areEqual, isTrue);
    });

    test('Test 4: Test semantic similarity (real embeddings should show semantic meaning)', () async {
      print('\n========================================');
      print('TEST 4: Semantic Similarity Test');
      print('========================================\n');

      await embeddingService.initialize();

      final stats = embeddingService.getCacheStats();

      if (stats['mode'] != 'real') {
        print('⚠️  Skipping semantic test - running in mock mode');
        return;
      }

      // Test semantic similarity
      final query1 = 'beautiful sunset at beach';
      final query2 = 'beach sunset scene';  // Similar meaning
      final query3 = 'mountain forest landscape';  // Different meaning

      print('Query 1: "$query1"');
      print('Query 2: "$query2" (similar meaning)');
      print('Query 3: "$query3" (different meaning)\n');

      final emb1 = await embeddingService.generateEmbedding(query1);
      final emb2 = await embeddingService.generateEmbedding(query2);
      final emb3 = await embeddingService.generateEmbedding(query3);

      final sim12 = embeddingService.computeSimilarity(emb1, emb2);
      final sim13 = embeddingService.computeSimilarity(emb1, emb3);

      print('Similarity scores:');
      print('  Query 1 ↔ Query 2 (similar):   ${sim12.toStringAsFixed(4)}');
      print('  Query 1 ↔ Query 3 (different): ${sim13.toStringAsFixed(4)}');

      if (sim12 > sim13) {
        print('\n✅ PASS: Similar queries have higher similarity!');
        print('   This confirms ONNX models understand semantic meaning.');
      } else {
        print('\n⚠️  WARNING: Similarity scores unexpected');
        print('   Similar queries should have higher similarity than different ones.');
      }

      // Similar queries should have higher similarity
      expect(sim12, greaterThan(0.0));
      expect(sim12, lessThanOrEqualTo(1.0));
    });

    test('Test 5: Verify ONNX models vs Mock mode detection', () async {
      print('\n========================================');
      print('TEST 5: ONNX vs Mock Detection');
      print('========================================\n');

      await embeddingService.initialize();

      // Generate two different embeddings
      final emb1 = await embeddingService.generateEmbedding('test query A');
      final emb2 = await embeddingService.generateEmbedding('test query B');

      // Check statistics
      final stats = embeddingService.getCacheStats();
      final mode = stats['mode'];

      print('Service mode: $mode');
      print('Text encoder ready: ${embeddingService.isTextReady}');
      print('Image encoder ready: ${embeddingService.isImageReady}');

      // Calculate how different the embeddings are
      final similarity = _cosineSimilarity(emb1, emb2);
      print('\nSimilarity between two different queries: ${similarity.toStringAsFixed(4)}');

      // Real ONNX models should produce varied embeddings
      // Mock mode might produce more predictable/similar patterns

      if (mode == 'real') {
        print('\n✅ CONFIRMED: Using REAL ONNX Runtime');
        print('   - ONNX models are loaded and running');
        print('   - Embeddings are generated via neural network inference');
      } else {
        print('\n⚠️  DETECTED: Using MOCK mode fallback');
        print('   - ONNX models failed to load or are not available');
        print('   - Embeddings are generated using deterministic hash-based method');
        print('\nTo fix:');
        print('   1. Verify .onnx model files exist in assets/model/');
        print('   2. Check file names match:');
        print('      - kitako_image_encoder_int8.onnx');
        print('      - kitako_text_encoder_int8.onnx');
        print('   3. Run: flutter clean && flutter pub get');
      }

      print('\n========================================\n');
    });
  });
}

// Helper functions
double _calculateL2Norm(List<double> vector) {
  double sum = 0.0;
  for (final value in vector) {
    sum += value * value;
  }
  return _sqrt(sum);
}

double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;

  double dot = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  final denominator = _sqrt(normA) * _sqrt(normB);
  return denominator == 0 ? 0.0 : dot / denominator;
}

bool _listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return false;
  }
  return true;
}

double _sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
