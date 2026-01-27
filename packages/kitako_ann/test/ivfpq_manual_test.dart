/// Manual test for IVFPQ (Inverted File with Product Quantization)
///
/// Run with: flutter test test/ivfpq_manual_test.dart
///
/// This test demonstrates the pure Dart IVFPQ implementation which:
/// - Requires training on representative data
/// - Uses vector compression for memory efficiency
/// - Provides approximate (not exact) nearest neighbor search

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/src/core/ann_config.dart';
import 'package:kitako_ann/src/ivfpq/ivfpq_index.dart';

void main() {
  test('Manual IVFPQ index test', () async {
    print('=== KitaKo IVFPQ Manual Test ===\n');

    // Use smaller dimensions for faster testing
    const dimension = 128;
    const numVectors = 1000;
    const numTrainingVectors = 500;

    // 1. Create IVFPQ config
    print('1. Creating IVFPQ configuration...');
    final config = IvfPqConfig(
      dimension: dimension,
      numClusters: 16,               // Number of inverted lists
      numSubquantizers: 16,          // 128/16 = 8 dims per subquantizer
      numCentroidsPerSubquantizer: 256, // 8-bit codes
      numProbes: 4,                  // Search 4 clusters
      trainingIterations: 10,        // K-means iterations
    );
    print('   Dimension: ${config.dimension}');
    print('   Clusters: ${config.numClusters}');
    print('   Subquantizers: ${config.numSubquantizers}');
    print('   Centroids per subquantizer: ${config.numCentroidsPerSubquantizer}');
    print('   Bytes per code: ${config.bytesPerCode}');
    print('   ✓ Config created\n');

    // 2. Generate test data
    print('2. Generating test data...');
    final random = math.Random(42);
    
    // Create clustered data for better testing
    final allVectors = <Float32List>[];
    final vectorIds = <int>[];
    
    for (int i = 0; i < numVectors; i++) {
      final vec = _createClusteredVector(dimension, i, numVectors ~/ 10, random);
      allVectors.add(vec);
      vectorIds.add(i);
    }
    
    final trainingVectors = allVectors.sublist(0, numTrainingVectors);
    print('   Generated $numVectors vectors ($numTrainingVectors for training)');
    print('   ✓ Data ready\n');

    // 3. Create and train index
    print('3. Creating and training IVFPQ index...');
    final index = IvfPqAnnIndex(config: config);
    
    final trainStart = DateTime.now();
    await index.train(trainingVectors, seed: 42);
    final trainTime = DateTime.now().difference(trainStart);
    
    print('   Training time: ${trainTime.inMilliseconds}ms');
    print('   Is trained: ${index.isTrained}');
    print('   ✓ Index trained\n');

    // 4. Add vectors to index
    print('4. Adding $numVectors vectors to index...');
    final addStart = DateTime.now();
    
    for (int i = 0; i < numVectors; i++) {
      await index.addVector(allVectors[i], vectorIds[i]);
    }
    
    final addTime = DateTime.now().difference(addStart);
    print('   Add time: ${addTime.inMilliseconds}ms');
    print('   Index size: ${index.size}');
    print('   ✓ Vectors added\n');

    // 5. Save index
    final tempDir = Directory.systemTemp.createTempSync('kitako_ivfpq_test_');
    final indexPath = '${tempDir.path}/ivfpq_index.bin';
    
    print('5. Saving index to: $indexPath');
    await index.save(indexPath);
    final fileSize = File(indexPath).lengthSync();
    print('   File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
    
    // Calculate compression ratio
    final uncompressedSize = numVectors * dimension * 4; // float32
    final compressionRatio = uncompressedSize / fileSize;
    print('   Compression ratio: ${compressionRatio.toStringAsFixed(1)}x');
    print('   ✓ Index saved\n');

    // 6. Load index in new instance
    print('6. Loading index in new instance...');
    final index2 = IvfPqAnnIndex(config: config);
    await index2.load(indexPath);
    print('   Loaded size: ${index2.size}');
    print('   Is ready: ${index2.isReady}');
    print('   ✓ Index loaded\n');

    // 7. Test search
    print('7. Testing search...');
    
    // Search for a vector that's in the index
    final queryIdx = 250;
    final query = allVectors[queryIdx];
    
    final searchStart = DateTime.now();
    final results = await index2.search(query, 10);
    final searchTime = DateTime.now().difference(searchStart);
    
    print('   Query: vector #$queryIdx');
    print('   Search time: ${searchTime.inMicroseconds}μs');
    print('   Results (top 10):');
    
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      final marker = r.id == queryIdx ? ' ← QUERY' : '';
      print('     ${i + 1}. ID: ${r.id.toString().padLeft(3)}, '
          'Distance: ${r.distance.toStringAsFixed(4)}$marker');
    }

    // Check recall (is query in top results?)
    final foundAtPosition = results.indexWhere((r) => r.id == queryIdx);
    if (foundAtPosition >= 0) {
      print('   ✓ Query found at position ${foundAtPosition + 1}');
    } else {
      print('   ⚠ Query not in top 10 (approximate search)');
    }
    print('');

    // 8. Benchmark multiple searches
    print('8. Benchmarking search performance...');
    const numQueries = 100;
    final benchStart = DateTime.now();
    
    for (int i = 0; i < numQueries; i++) {
      final q = allVectors[i * (numVectors ~/ numQueries)];
      await index2.search(q, 10);
    }
    
    final benchTime = DateTime.now().difference(benchStart);
    final avgSearchTime = benchTime.inMicroseconds / numQueries;
    print('   $numQueries queries in ${benchTime.inMilliseconds}ms');
    print('   Average: ${avgSearchTime.toStringAsFixed(0)}μs per query');
    print('   QPS: ${(1000000 / avgSearchTime).toStringAsFixed(0)} queries/sec');
    print('   ✓ Benchmark complete\n');

    // 9. Test recall quality
    print('9. Testing recall quality...');
    int correctInTop1 = 0;
    int correctInTop10 = 0;
    const testQueries = 50;
    
    for (int i = 0; i < testQueries; i++) {
      final qIdx = (i * numVectors ~/ testQueries);
      final q = allVectors[qIdx];
      final res = await index2.search(q, 10);
      
      if (res.isNotEmpty && res.first.id == qIdx) {
        correctInTop1++;
      }
      if (res.any((r) => r.id == qIdx)) {
        correctInTop10++;
      }
    }
    
    final recall1 = (correctInTop1 / testQueries * 100).toStringAsFixed(1);
    final recall10 = (correctInTop10 / testQueries * 100).toStringAsFixed(1);
    print('   Recall@1: $recall1% ($correctInTop1/$testQueries)');
    print('   Recall@10: $recall10% ($correctInTop10/$testQueries)');
    print('   ✓ Recall test complete\n');

    // 10. Cleanup
    print('10. Cleaning up...');
    tempDir.deleteSync(recursive: true);
    print('   ✓ Resources freed\n');

    print('=== IVFPQ Manual Test Complete ===\n');
    print('Summary:');
    print('  • Training: ${trainTime.inMilliseconds}ms');
    print('  • Index size: ${index.size} vectors');
    print('  • File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
    print('  • Compression: ${compressionRatio.toStringAsFixed(1)}x');
    print('  • Search: ${avgSearchTime.toStringAsFixed(0)}μs avg');
    print('  • Recall@1: $recall1%');
    print('  • Recall@10: $recall10%');

    // Basic assertions
    expect(index.size, equals(numVectors));
    expect(index2.size, equals(numVectors));
    expect(results, isNotEmpty);
  });
}

/// Creates a clustered vector for testing
/// Vectors in the same cluster will be more similar
Float32List _createClusteredVector(int dimension, int index, int numClusters, math.Random random) {
  final vec = Float32List(dimension);
  final cluster = index % numClusters;
  
  // Base values from cluster
  for (int j = 0; j < dimension; j++) {
    // Cluster-specific offset + random noise
    vec[j] = (cluster * 0.5) + (random.nextDouble() - 0.5) * 0.3;
  }
  
  // L2 normalize
  double norm = 0;
  for (int j = 0; j < dimension; j++) {
    norm += vec[j] * vec[j];
  }
  norm = norm > 0 ? 1.0 / math.sqrt(norm) : 1.0;
  for (int j = 0; j < dimension; j++) {
    vec[j] *= norm;
  }
  
  return vec;
}
