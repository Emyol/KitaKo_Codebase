import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/src/ivfpq/product_quantizer.dart';

void main() {
  group('ProductQuantizer', () {
    test('initializes with correct parameters', () {
      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 256,
      );
      
      expect(pq.dimension, equals(32));
      expect(pq.numSubquantizers, equals(4));
      expect(pq.numCentroids, equals(256));
      expect(pq.subvectorDimension, equals(8));
      expect(pq.isTrained, isFalse);
    });

    test('throws if dimension not divisible by numSubquantizers', () {
      expect(
        () => ProductQuantizer(
          dimension: 33,
          numSubquantizers: 4,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws if numCentroids exceeds 256', () {
      expect(
        () => ProductQuantizer(
          dimension: 32,
          numSubquantizers: 4,
          numCentroids: 300,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('trains on random data', () {
      final random = Random(42);
      final data = List.generate(
        500,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64, // Fewer centroids for faster test
      );

      pq.train(data, maxIterations: 10, seed: 42);

      expect(pq.isTrained, isTrue);
    });

    test('encodes vector to correct size', () {
      final random = Random(42);
      final data = List.generate(
        500,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64,
      );
      pq.train(data, maxIterations: 10, seed: 42);

      final vector = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final codes = pq.encode(vector);

      expect(codes.length, equals(4)); // numSubquantizers
      expect(codes.every((c) => c < 64), isTrue); // All codes < numCentroids
    });

    test('decode produces vector of correct dimension', () {
      final random = Random(42);
      final data = List.generate(
        500,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64,
      );
      pq.train(data, maxIterations: 10, seed: 42);

      final vector = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final codes = pq.encode(vector);
      final decoded = pq.decode(codes);

      expect(decoded.length, equals(32));
    });

    test('encode/decode introduces bounded error', () {
      final random = Random(42);
      final data = List.generate(
        1000,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 8,
        numCentroids: 256,
      );
      pq.train(data, maxIterations: 25, seed: 42);

      // Test reconstruction error
      double totalError = 0;
      for (int i = 0; i < 100; i++) {
        final vector = data[i];
        final codes = pq.encode(vector);
        final decoded = pq.decode(codes);
        
        double error = 0;
        for (int d = 0; d < 32; d++) {
          final diff = vector[d] - decoded[d];
          error += diff * diff;
        }
        totalError += error;
      }
      
      final avgError = totalError / 100;
      // Reconstruction error should be reasonable
      expect(avgError, lessThan(1.0));
    });

    test('distance table has correct dimensions', () {
      final random = Random(42);
      final data = List.generate(
        500,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64,
      );
      pq.train(data, maxIterations: 10, seed: 42);

      final query = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final table = pq.computeDistanceTable(query);

      expect(table.length, equals(4)); // numSubquantizers
      expect(table.every((row) => row.length == 64), isTrue); // numCentroids
    });

    test('asymmetric distance approximates true distance', () {
      final random = Random(42);
      final data = List.generate(
        1000,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 8,
        numCentroids: 256,
      );
      pq.train(data, maxIterations: 25, seed: 42);

      final query = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final distTable = pq.computeDistanceTable(query);

      // Compare asymmetric distance to true distance for several vectors
      for (int i = 0; i < 50; i++) {
        final vector = data[i];
        final codes = pq.encode(vector);
        
        // Asymmetric distance (using table)
        final asymDist = pq.computeAsymmetricDistance(distTable, codes);
        
        // True distance to decoded vector
        final decoded = pq.decode(codes);
        double trueDist = 0;
        for (int d = 0; d < 32; d++) {
          final diff = query[d] - decoded[d];
          trueDist += diff * diff;
        }

        // Asymmetric distance should be close to true distance to decoded
        expect(asymDist, closeTo(trueDist, 1e-4));
      }
    });

    test('serialization round-trip preserves model', () {
      final random = Random(42);
      final data = List.generate(
        500,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64,
      );
      pq.train(data, maxIterations: 10, seed: 42);

      final bytes = pq.serialize();
      final restored = ProductQuantizer.deserialize(bytes);

      expect(restored.dimension, equals(pq.dimension));
      expect(restored.numSubquantizers, equals(pq.numSubquantizers));
      expect(restored.numCentroids, equals(pq.numCentroids));
      expect(restored.isTrained, isTrue);

      // Encoding should produce same results
      final testVector = Float32List.fromList(
        List.generate(32, (_) => random.nextDouble()),
      );
      final codes1 = pq.encode(testVector);
      final codes2 = restored.encode(testVector);

      expect(codes2, equals(codes1));
    });

    test('batch encoding works correctly', () {
      final random = Random(42);
      final data = List.generate(
        500,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final pq = ProductQuantizer(
        dimension: 32,
        numSubquantizers: 4,
        numCentroids: 64,
      );
      pq.train(data, maxIterations: 10, seed: 42);

      final vectors = List.generate(
        10,
        (_) => Float32List.fromList(
          List.generate(32, (_) => random.nextDouble()),
        ),
      );

      final batchCodes = pq.encodeBatch(vectors);
      
      expect(batchCodes.length, equals(10));
      for (int i = 0; i < 10; i++) {
        expect(batchCodes[i], equals(pq.encode(vectors[i])));
      }
    });
  });
}
