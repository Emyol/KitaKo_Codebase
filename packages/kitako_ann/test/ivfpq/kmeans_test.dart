import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/src/ivfpq/kmeans.dart';

void main() {
  group('KMeans', () {
    test('initializes with correct parameters', () {
      final kmeans = KMeans(numClusters: 4);
      expect(kmeans.numClusters, equals(4));
      expect(kmeans.isTrained, isFalse);
      expect(kmeans.centroids, isNull);
    });

    test('trains on simple clustered data', () {
      final random = Random(42);
      final data = <Float32List>[];
      
      // Generate 4 distinct clusters
      final clusterCenters = [
        [0.0, 0.0],
        [10.0, 0.0],
        [0.0, 10.0],
        [10.0, 10.0],
      ];
      
      for (final center in clusterCenters) {
        for (int i = 0; i < 25; i++) {
          data.add(Float32List.fromList([
            center[0] + random.nextDouble() * 2 - 1,
            center[1] + random.nextDouble() * 2 - 1,
          ]));
        }
      }

      final kmeans = KMeans(numClusters: 4, seed: 42);
      final inertia = kmeans.train(data);

      expect(kmeans.isTrained, isTrue);
      expect(kmeans.centroids, isNotNull);
      expect(kmeans.centroids!.length, equals(4));
      expect(inertia, lessThan(200)); // Reasonable inertia for well-separated clusters
    });

    test('predicts correct cluster for known points', () {
      final random = Random(42);
      final data = <Float32List>[];
      
      // Generate 2 well-separated clusters
      for (int i = 0; i < 50; i++) {
        data.add(Float32List.fromList([
          random.nextDouble() * 2, // cluster 1: x in [0, 2]
          random.nextDouble() * 2,
        ]));
        data.add(Float32List.fromList([
          10 + random.nextDouble() * 2, // cluster 2: x in [10, 12]
          random.nextDouble() * 2,
        ]));
      }

      final kmeans = KMeans(numClusters: 2, seed: 42);
      kmeans.train(data);

      // Test points clearly in each cluster
      final cluster1Point = Float32List.fromList([1.0, 1.0]);
      final cluster2Point = Float32List.fromList([11.0, 1.0]);

      final pred1 = kmeans.predict(cluster1Point);
      final pred2 = kmeans.predict(cluster2Point);

      expect(pred1, isNot(equals(pred2)));
    });

    test('predictTopK returns k nearest clusters', () {
      final data = <Float32List>[];
      final random = Random(42);
      
      // Generate 5 clusters at known positions
      final positions = [
        [0.0, 0.0],
        [5.0, 0.0],
        [10.0, 0.0],
        [15.0, 0.0],
        [20.0, 0.0],
      ];
      
      for (final pos in positions) {
        for (int i = 0; i < 20; i++) {
          data.add(Float32List.fromList([
            pos[0] + random.nextDouble() * 0.5 - 0.25,
            pos[1] + random.nextDouble() * 0.5 - 0.25,
          ]));
        }
      }

      final kmeans = KMeans(numClusters: 5, seed: 42);
      kmeans.train(data);

      // Query point near the middle cluster
      final query = Float32List.fromList([10.0, 0.0]);
      final topK = kmeans.predictTopK(query, 3);

      expect(topK.length, equals(3));
      // The nearest cluster should be in the results
    });

    test('serialization round-trip preserves model', () {
      final random = Random(42);
      final data = List.generate(
        100,
        (_) => Float32List.fromList([
          random.nextDouble() * 10,
          random.nextDouble() * 10,
        ]),
      );

      final kmeans = KMeans(numClusters: 4, seed: 42);
      kmeans.train(data);

      // Serialize and deserialize
      final bytes = kmeans.serialize();
      final restored = KMeans.deserialize(bytes);

      expect(restored.numClusters, equals(kmeans.numClusters));
      expect(restored.isTrained, isTrue);
      
      // Check centroids match
      for (int c = 0; c < kmeans.numClusters; c++) {
        for (int d = 0; d < 2; d++) {
          expect(
            restored.centroids![c][d],
            closeTo(kmeans.centroids![c][d], 1e-6),
          );
        }
      }

      // Predictions should match
      final testPoint = Float32List.fromList([5.0, 5.0]);
      expect(restored.predict(testPoint), equals(kmeans.predict(testPoint)));
    });

    test('throws on empty training data', () {
      final kmeans = KMeans(numClusters: 4);
      expect(
        () => kmeans.train([]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on insufficient training data', () {
      final kmeans = KMeans(numClusters: 10);
      final data = List.generate(
        5, // Less than numClusters
        (_) => Float32List.fromList([1.0, 2.0]),
      );
      expect(
        () => kmeans.train(data),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when predicting before training', () {
      final kmeans = KMeans(numClusters: 4);
      expect(
        () => kmeans.predict(Float32List.fromList([1.0, 2.0])),
        throwsA(isA<StateError>()),
      );
    });
  });
}
