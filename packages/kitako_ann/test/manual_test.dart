// Run with: dart test manual_test.dart
// Or: flutter test manual_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_ann/kitako_ann.dart';

void main() {
  test('Manual ANN index test', () async {
    print('=== KitaKo ANN Manual Test ===\n');

    // 1. Create a client with SigLIP-768 config
    print('1. Creating ANN client (768 dimensions, Inner Product)...');
    final client = LocalAnnClient(config: AnnClientConfig.siglip768);
    print('   ✓ Client created\n');

    // 2. Build a small test index
    print('2. Building index with 100 random embeddings...');
    final embeddings = <int, Float32List>{};
    for (int i = 0; i < 100; i++) {
      // Create pseudo-random normalized vectors
      final vec = Float32List(768);
      double norm = 0;
      for (int j = 0; j < 768; j++) {
        vec[j] = ((i * 17 + j * 31) % 1000 - 500) / 500.0;
        norm += vec[j] * vec[j];
      }
      // L2 normalize
      norm = norm > 0 ? 1.0 / (norm * 0.5 + 0.5) : 1.0;
      for (int j = 0; j < 768; j++) {
        vec[j] *= norm;
      }
      embeddings[i] = vec;
    }

    await client.buildIndex(embeddings, M: 16, efConstruction: 100);
    print('   ✓ Index built with ${client.itemCount} items\n');

    // 3. Save the index
    final tempDir = Directory.systemTemp.createTempSync('kitako_ann_test_');
    final indexPath = '${tempDir.path}/test_index.bin';
    print('3. Saving index to: $indexPath');
    await client.saveIndex(indexPath);
    print('   ✓ Index saved (${File(indexPath).lengthSync()} bytes)\n');

    // 4. Load the index in a new client
    print('4. Loading index in new client...');
    final client2 = LocalAnnClient(config: AnnClientConfig.siglip768);
    await client2.loadIndex(indexPath);
    print('   ✓ Index loaded with ${client2.itemCount} items\n');

    // 5. Search with a query vector
    print('5. Searching for 5 nearest neighbors...');
    final queryVec = embeddings[42]!; // Use embedding #42 as query
    final results = await client2.search(queryVec, k: 5);

    print('   Query: vector #42');
    print('   Results:');
    for (final r in results) {
      print('     ID: ${r.id.toString().padLeft(3)}, '
          'Distance: ${r.distance.toStringAsFixed(4)}, '
          'Similarity: ${(1 - r.distance).toStringAsFixed(4)}');
    }

    // Verify the top result is the query itself (distance ≈ 0)
    expect(results.first.id, equals(42));
    expect(results.first.distance, lessThan(0.01));
    print('   ✓ Top result is query itself (expected)\n');

    // 6. Cleanup
    print('6. Cleaning up...');
    client.dispose();
    client2.dispose();
    tempDir.deleteSync(recursive: true);
    print('   ✓ Resources freed\n');

    print('=== All tests passed! ===');
  });
}
