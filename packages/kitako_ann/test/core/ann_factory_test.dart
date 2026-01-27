import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/src/core/ann_algorithm.dart';
import 'package:kitako_ann/src/core/ann_config.dart';
import 'package:kitako_ann/src/core/ann_factory.dart';
import 'package:kitako_ann/src/hnsw/hnsw_index.dart';
import 'package:kitako_ann/src/ivfpq/ivfpq_index.dart';

void main() {
  group('AnnFactory', () {
    test('creates HnswAnnIndex from HnswConfig', () {
      final config = HnswConfig(
        dimension: 128,
        m: 16,
        efConstruction: 200,
        efSearch: 50,
        maxElements: 10000,
      );
      
      final index = AnnFactory.create(config);
      
      expect(index, isA<HnswAnnIndex>());
      expect(index.dimension, equals(128));
    });

    test('creates IvfPqAnnIndex from IvfPqConfig', () {
      final config = IvfPqConfig(
        dimension: 128,
        numClusters: 64,
        numSubquantizers: 8,
        numCentroidsPerSubquantizer: 256,
        numProbes: 4,
      );
      
      final index = AnnFactory.create(config);
      
      expect(index, isA<IvfPqAnnIndex>());
      expect(index.dimension, equals(128));
    });

    test('createForAlgorithm creates HNSW', () {
      final index = AnnFactory.createForAlgorithm(
        AnnAlgorithm.hnsw,
        dimension: 256,
      );
      
      expect(index, isA<HnswAnnIndex>());
      expect(index.dimension, equals(256));
    });

    test('createForAlgorithm creates IVF-PQ', () {
      final index = AnnFactory.createForAlgorithm(
        AnnAlgorithm.ivfpq,
        dimension: 256,
      );
      
      expect(index, isA<IvfPqAnnIndex>());
      expect(index.dimension, equals(256));
    });

    test('createForAlgorithm respects options', () {
      final index = AnnFactory.createForAlgorithm(
        AnnAlgorithm.hnsw,
        dimension: 128,
        options: {
          'm': 32,
          'efConstruction': 400,
          'maxElements': 50000,
        },
      );
      
      expect(index, isA<HnswAnnIndex>());
      expect(index.dimension, equals(128));
      expect(index.maxCapacity, equals(50000));
    });

    test('getRecommendedConfig returns valid HNSW config', () {
      final config = AnnFactory.getRecommendedConfig(
        AnnAlgorithm.hnsw,
        vectorCount: 100000,
        dimension: 768,
        priority: 'balanced',
      );
      
      expect(config, isA<HnswConfig>());
      expect(config.dimension, equals(768));
      
      final hnswConfig = config as HnswConfig;
      expect(hnswConfig.maxElements, equals(100000));
    });

    test('getRecommendedConfig returns valid IVF-PQ config', () {
      final config = AnnFactory.getRecommendedConfig(
        AnnAlgorithm.ivfpq,
        vectorCount: 100000,
        dimension: 768,
        priority: 'balanced',
      );
      
      expect(config, isA<IvfPqConfig>());
      expect(config.dimension, equals(768));
      
      final ivfConfig = config as IvfPqConfig;
      expect(ivfConfig.numClusters, greaterThan(0));
      expect(ivfConfig.numSubquantizers, greaterThan(0));
      expect(768 % ivfConfig.numSubquantizers, equals(0));
    });

    test('priority affects config for HNSW', () {
      final speedConfig = AnnFactory.getRecommendedConfig(
        AnnAlgorithm.hnsw,
        vectorCount: 10000,
        priority: 'speed',
      ) as HnswConfig;
      
      final qualityConfig = AnnFactory.getRecommendedConfig(
        AnnAlgorithm.hnsw,
        vectorCount: 10000,
        priority: 'quality',
      ) as HnswConfig;
      
      // Quality config should have higher m and efConstruction
      expect(qualityConfig.m, greaterThan(speedConfig.m));
      expect(qualityConfig.efConstruction, greaterThan(speedConfig.efConstruction));
    });

    test('priority affects config for IVF-PQ', () {
      final speedConfig = AnnFactory.getRecommendedConfig(
        AnnAlgorithm.ivfpq,
        vectorCount: 10000,
        priority: 'speed',
      ) as IvfPqConfig;
      
      final qualityConfig = AnnFactory.getRecommendedConfig(
        AnnAlgorithm.ivfpq,
        vectorCount: 10000,
        priority: 'quality',
      ) as IvfPqConfig;
      
      // Quality config should have higher nprobe
      expect(qualityConfig.numProbes, greaterThan(speedConfig.numProbes));
    });
  });

  group('AnnAlgorithmFactory extension', () {
    test('createIndex creates correct type', () {
      final hnswIndex = AnnAlgorithm.hnsw.createIndex(dimension: 128);
      expect(hnswIndex, isA<HnswAnnIndex>());
      
      final ivfpqIndex = AnnAlgorithm.ivfpq.createIndex(dimension: 128);
      expect(ivfpqIndex, isA<IvfPqAnnIndex>());
    });

    test('getRecommendedConfig returns valid config', () {
      final config = AnnAlgorithm.hnsw.getRecommendedConfig(
        vectorCount: 50000,
        dimension: 512,
      );
      
      expect(config, isA<HnswConfig>());
      expect(config.dimension, equals(512));
    });
  });

  group('Algorithm toggle scenario', () {
    test('can switch between algorithms using same interface', () {
      // This demonstrates the toggle capability
      final algorithms = [AnnAlgorithm.hnsw, AnnAlgorithm.ivfpq];
      
      for (final algorithm in algorithms) {
        final index = algorithm.createIndex(dimension: 32);
        
        // All algorithms support the same interface
        expect(index.dimension, equals(32));
        expect(index.size, equals(0));
        expect(index.isReady, isFalse);
        
        // Can dispose
        index.dispose();
      }
    });

    test('factory creates indexes that implement same interface', () {
      final configs = [
        HnswConfig.siglip768(),
        IvfPqConfig.siglip768(),
      ];
      
      for (final config in configs) {
        final index = AnnFactory.create(config);
        
        // Same interface regardless of implementation
        expect(index.dimension, equals(768));
      }
    });
  });
}
