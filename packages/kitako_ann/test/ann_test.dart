import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/kitako_ann.dart';

void main() {
  group('AnnClientConfig', () {
    test('siglip768 has correct defaults', () {
      const config = AnnClientConfig.siglip768;
      expect(config.dimension, 768);
      expect(config.spaceType, AnnSpaceType.innerProduct);
      expect(config.defaultEfSearch, 100);
    });

    test('custom config works', () {
      const config = AnnClientConfig(
        dimension: 512,
        spaceType: AnnSpaceType.l2,
        defaultEfSearch: 200,
      );
      expect(config.dimension, 512);
      expect(config.spaceType, AnnSpaceType.l2);
      expect(config.defaultEfSearch, 200);
    });
  });

  group('AnnSearchResult', () {
    test('similarity is computed correctly', () {
      const result = AnnSearchResult(id: 1, distance: 0.2);
      expect(result.similarity, closeTo(0.8, 0.001));
    });

    test('zero distance means perfect similarity', () {
      const result = AnnSearchResult(id: 1, distance: 0.0);
      expect(result.similarity, 1.0);
    });

    test('toString works', () {
      const result = AnnSearchResult(id: 42, distance: 0.25);
      expect(result.toString(), contains('42'));
      expect(result.toString(), contains('0.25'));
    });
  });

  group('IndexMetadata', () {
    test('fromJson and toJson round-trip', () {
      final original = IndexMetadata(
        dimension: 768,
        spaceType: 0,
        itemCount: 1000,
        M: 16,
        efConstruction: 200,
        description: 'Test index',
      );

      final json = original.toJson();
      final restored = IndexMetadata.fromJson(json);

      expect(restored.dimension, original.dimension);
      expect(restored.spaceType, original.spaceType);
      expect(restored.itemCount, original.itemCount);
      expect(restored.M, original.M);
      expect(restored.efConstruction, original.efConstruction);
      expect(restored.description, original.description);
    });

    test('fromJson handles minimal data', () {
      final json = {
        'dimension': 512,
        'item_count': 500,
      };

      final metadata = IndexMetadata.fromJson(json);
      expect(metadata.dimension, 512);
      expect(metadata.itemCount, 500);
      expect(metadata.spaceType, 0); // default
      expect(metadata.M, 16); // default
    });
  });

  group('SearchResult', () {
    test('similarity is computed correctly', () {
      final result = SearchResult(id: 1, distance: 0.3);
      expect(result.similarity, closeTo(0.7, 0.001));
    });

    test('metadata can be attached', () {
      final result = SearchResult(
        id: 1,
        distance: 0.1,
        metadata: {'path': '/images/test.jpg', 'label': 'cat'},
      );
      expect(result.metadata?['path'], '/images/test.jpg');
      expect(result.metadata?['label'], 'cat');
    });
  });

  group('AnnSearchService', () {
    test('throws when not initialized', () {
      final service = AnnSearchService();
      final query = Float32List(768);

      expect(
        () => service.search(query),
        throwsStateError,
      );
    });

    test('isInitialized is false initially', () {
      final service = AnnSearchService();
      expect(service.isInitialized, false);
    });

    test('dispose can be called multiple times', () {
      final service = AnnSearchService();
      service.dispose();
      service.dispose(); // Should not throw
    });
  });
}

/// Helper to generate a random normalized vector
Float32List generateRandomVector(int dimension, {int? seed}) {
  final random = seed != null ? math.Random(seed) : math.Random();
  final data = Float32List(dimension);

  double norm = 0.0;
  for (int i = 0; i < dimension; i++) {
    data[i] = random.nextDouble() * 2 - 1;
    norm += data[i] * data[i];
  }

  norm = math.sqrt(norm);
  if (norm > 0) {
    for (int i = 0; i < dimension; i++) {
      data[i] /= norm;
    }
  }

  return data;
}

/// Helper to compute cosine similarity
double cosineSimilarity(Float32List a, Float32List b) {
  double dot = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  if (normA == 0 || normB == 0) return 0.0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
