import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/src/ivfpq/inverted_file.dart';
import 'package:kitako_ann/src/ivfpq/product_quantizer.dart';

void main() {
  group('InvertedFile', () {
    late ProductQuantizer pq;
    late List<Float32List> trainingData;
    
    setUpAll(() {
      final random = Random(42);
      trainingData = List.generate(
        1000,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );
      
      pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64,
      );
      pq.train(trainingData, maxIterations: 15, seed: 42);
    });

    test('initializes with correct parameters', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      
      expect(ivf.numClusters, equals(16));
      expect(ivf.dimension, equals(32));
      expect(ivf.size, equals(0));
      expect(ivf.isTrained, isFalse);
    });

    test('trains on data', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      expect(ivf.isTrained, isTrue);
    });

    test('adds vectors and updates size', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      expect(ivf.size, equals(0));
      
      final random = Random(42);
      for (int i = 0; i < 100; i++) {
        final vector = Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        );
        ivf.add(i, vector);
      }

      expect(ivf.size, equals(100));
    });

    test('addBatch adds multiple vectors', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      final random = Random(42);
      final vectors = List.generate(
        50,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );
      final ids = List.generate(50, (i) => i);

      ivf.addBatch(ids, vectors);

      expect(ivf.size, equals(50));
    });

    test('search returns k results', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      // Add vectors
      final random = Random(42);
      for (int i = 0; i < 500; i++) {
        final vector = Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        );
        ivf.add(i, vector);
      }

      // Search
      final query = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final results = ivf.search(query, k: 10, nprobe: 4);

      expect(results.length, equals(10));
      
      // Results should be sorted by distance
      for (int i = 1; i < results.length; i++) {
        expect(results[i].$2, greaterThanOrEqualTo(results[i - 1].$2));
      }
    });

    test('search with higher nprobe gives better results', () {
      final ivf = InvertedFile(numClusters: 32, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      // Add all training vectors
      for (int i = 0; i < trainingData.length; i++) {
        ivf.add(i, trainingData[i]);
      }

      // Use one of the training vectors as query
      final queryIdx = 100;
      final query = trainingData[queryIdx];

      // Search with low nprobe
      final lowProbeResults = ivf.search(query, k: 5, nprobe: 1);
      
      // Search with high nprobe
      final highProbeResults = ivf.search(query, k: 5, nprobe: 16);

      // The query vector itself should be in the results with high nprobe
      final highProbeIds = highProbeResults.map((r) => r.$1).toSet();
      expect(highProbeIds.contains(queryIdx), isTrue);
    });

    test('clusterSizes reflects distribution', () {
      final ivf = InvertedFile(numClusters: 8, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      // Add vectors
      final random = Random(42);
      for (int i = 0; i < 200; i++) {
        final vector = Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        );
        ivf.add(i, vector);
      }

      final sizes = ivf.clusterSizes;
      expect(sizes.length, equals(8));
      expect(sizes.reduce((a, b) => a + b), equals(200));
    });

    test('serialization round-trip preserves index', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      // Add some vectors
      final random = Random(42);
      for (int i = 0; i < 200; i++) {
        final vector = Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        );
        ivf.add(i, vector);
      }

      // Serialize and deserialize
      final bytes = ivf.serialize();
      final restored = InvertedFile.deserialize(bytes);

      expect(restored.numClusters, equals(ivf.numClusters));
      expect(restored.dimension, equals(ivf.dimension));
      expect(restored.size, equals(ivf.size));
      expect(restored.isTrained, isTrue);

      // Search should give same results
      final query = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final results1 = ivf.search(query, k: 5, nprobe: 4);
      final results2 = restored.search(query, k: 5, nprobe: 4);

      // IDs should match
      for (int i = 0; i < 5; i++) {
        expect(results2[i].$1, equals(results1[i].$1));
        expect(results2[i].$2, closeTo(results1[i].$2, 1e-4));
      }
    });

    test('throws when adding before training', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      
      expect(
        () => ivf.add(0, Float32List(32)),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when searching before training', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      
      expect(
        () => ivf.search(Float32List(32), k: 5, nprobe: 4),
        throwsA(isA<StateError>()),
      );
    });

    test('throws on dimension mismatch', () {
      final ivf = InvertedFile(numClusters: 16, dimension: 32);
      ivf.train(trainingData, pq: pq, maxIterations: 15, seed: 42);

      expect(
        () => ivf.add(0, Float32List(64)), // Wrong dimension
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
