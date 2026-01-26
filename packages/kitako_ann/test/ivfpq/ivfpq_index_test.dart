import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/src/core/ann_config.dart';
import 'package:kitako_ann/src/ivfpq/ivfpq_index.dart';

void main() {
  group('IvfPqAnnIndex', () {
    late List<Float32List> trainingData;
    late Directory tempDir;

    setUpAll(() {
      final random = Random(42);
      trainingData = List.generate(
        1000,
        (_) => Float32List.fromList(
          List.generate(64, (_) => random.nextDouble()),
        ),
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ivfpq_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates with correct configuration', () {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 4,
      );
      final index = IvfPqAnnIndex(config: config);

      expect(index.dimension, equals(64));
      expect(index.size, equals(0));
      expect(index.isReady, isFalse);
      expect(index.isTrained, isFalse);
    });

    test('trains on data', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 4,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      expect(index.isTrained, isTrue);
      expect(index.isReady, isTrue);
    });

    test('throws when adding before training', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
      );
      final index = IvfPqAnnIndex(config: config);

      expect(
        () => index.addVector(Float32List(64), 0),
        throwsA(isA<Exception>()),
      );
    });

    test('adds vectors after training', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 4,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      // Add some vectors
      final random = Random(42);
      for (int i = 0; i < 100; i++) {
        final vector = Float32List.fromList(
          List.generate(64, (_) => random.nextDouble()),
        );
        await index.addVector(vector, i);
      }

      expect(index.size, equals(100));
    });

    test('addVectors adds batch', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      final random = Random(42);
      final vectors = List.generate(
        50,
        (_) => Float32List.fromList(
          List.generate(64, (_) => random.nextDouble()),
        ),
      );
      final ids = List.generate(50, (i) => i * 10); // Non-sequential IDs

      await index.addVectors(vectors, ids);

      expect(index.size, equals(50));
    });

    test('search returns correct format', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 8,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      // Add training data with IDs
      for (int i = 0; i < trainingData.length; i++) {
        await index.addVector(trainingData[i], i * 100);
      }

      // Search
      final query = trainingData[0];
      final results = await index.search(query, 10);

      expect(results.length, equals(10));
      
      // Results should be sorted by distance
      for (int i = 1; i < results.length; i++) {
        expect(results[i].distance, greaterThanOrEqualTo(results[i - 1].distance));
      }

      // First result should be the query itself (ID = 0)
      expect(results[0].id, equals(0));
    });

    test('search respects k parameter', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 8,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      for (int i = 0; i < trainingData.length; i++) {
        await index.addVector(trainingData[i], i);
      }

      final query = Float32List.fromList(
        List.generate(64, (_) => Random(42).nextDouble()),
      );

      final results5 = await index.search(query, 5);
      final results20 = await index.search(query, 20);

      expect(results5.length, equals(5));
      expect(results20.length, equals(20));

      // First 5 results should be the same
      for (int i = 0; i < 5; i++) {
        expect(results5[i].id, equals(results20[i].id));
      }
    });

    test('save and load preserves index', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 8,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      // Add vectors
      for (int i = 0; i < 500; i++) {
        await index.addVector(trainingData[i], i * 2);
      }

      // Save
      final indexPath = '${tempDir.path}/test_index.ivfpq';
      await index.save(indexPath);

      // Create new index and load
      final loadedIndex = IvfPqAnnIndex(config: config);
      await loadedIndex.load(indexPath);

      expect(loadedIndex.isReady, isTrue);
      expect(loadedIndex.size, equals(500));

      // Search should give same results
      final query = trainingData[10];
      final results1 = await index.search(query, 5);
      final results2 = await loadedIndex.search(query, 5);

      for (int i = 0; i < 5; i++) {
        expect(results2[i].id, equals(results1[i].id));
        expect(results2[i].distance, closeTo(results1[i].distance, 1e-4));
      }
    });

    test('getStatistics returns meaningful data', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 64,
        numProbes: 4,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      // Before training
      var stats = index.getStatistics();
      expect(stats['status'], equals('not_loaded'));

      // After training and adding data
      await index.train(trainingData, seed: 42);
      for (int i = 0; i < 500; i++) {
        await index.addVector(trainingData[i], i);
      }

      stats = index.getStatistics();
      expect(stats['total_vectors'], equals(500));
      expect(stats['num_clusters'], equals(16));
      expect(stats['num_subquantizers'], equals(8));
      expect(stats['num_probes'], equals(4));
      expect(stats['compression_ratio'], greaterThan(1));
    });

    test('dispose clears state', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);
      for (int i = 0; i < 100; i++) {
        await index.addVector(trainingData[i], i);
      }

      expect(index.isReady, isTrue);
      expect(index.size, equals(100));

      index.dispose();

      expect(index.isReady, isFalse);
      expect(index.isTrained, isFalse);
      expect(index.size, equals(0));
    });

    test('handles dimension mismatch', () async {
      final config = IvfPqConfig(
        dimension: 64,
        numClusters: 16,
        numSubquantizers: 8,
        trainingIterations: 10,
      );
      final index = IvfPqAnnIndex(config: config);

      await index.train(trainingData, seed: 42);

      expect(
        () => index.addVector(Float32List(32), 0), // Wrong dimension
        throwsA(isA<Exception>()),
      );

      expect(
        () => index.search(Float32List(128), 5), // Wrong dimension
        throwsA(isA<Exception>()),
      );
    });

    test('siglip768 config works correctly', () async {
      // Skip this test in CI as it requires significant memory
      final config = IvfPqConfig.siglip768();
      
      expect(config.dimension, equals(768));
      expect(config.numSubquantizers, equals(96)); // 768 / 96 = 8 dimensions per subvector
      
      // Just verify the config is valid, don't actually train
      final index = IvfPqAnnIndex(config: config);
      expect(index.dimension, equals(768));
    });
  });
}
