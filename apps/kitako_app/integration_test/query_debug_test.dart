import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// Quick diagnostic: Why does "car" return false results?
///
/// Tests text embedding discrimination for specific queries
/// to understand which queries the model handles well vs poorly.
///
/// Run with:
///   flutter test integration_test/query_debug_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Queries to test — mix of working and broken
  final queries = [
    'car', 'dog', 'cat', 'tree', 'flower', 'house', 'food', 'bird',
    'person', 'phone', 'book', 'water', 'sky', 'road', 'building',
    'motorcycle', 'bicycle', 'truck', 'bus', 'vehicle',
    'a photo of car', 'a photo of dog', 'a car', 'red car',
  ];

  setUpAll(() {
    print('');
    print('═══════════════════════════════════════════════════════════════');
    print(' QUERY DEBUG DIAGNOSTIC');
    print(' Why does "car" return false results?');
    print('═══════════════════════════════════════════════════════════════');
    print('');
  });

  group('Query Debug', () {
    late OnnxEmbeddingService service;

    testWidgets('Initialize model', (tester) async {
      service = OnnxEmbeddingService();

      final appDir = await getApplicationDocumentsDirectory();
      final searchDirs = [
        '${appDir.path}/onnx_models',
        '/data/local/tmp',
      ];

      String? visionPath;
      String? textPath;

      for (final dir in searchDirs) {
        final int8V = '$dir/kitako_image_encoder_int8.onnx';
        final int8T = '$dir/kitako_text_encoder_int8.onnx';
        if (await _fileExists(int8V) && await _fileExists(int8T)) {
          visionPath = int8V;
          textPath = int8T;
          print('Using Kitako INT8 from $dir');
          break;
        }
        final fp32V = '$dir/kitako_image_encoder_fp32.onnx';
        final fp32T = '$dir/kitako_text_encoder_fp32.onnx';
        if (await _fileExists(fp32V) && await _fileExists(fp32T)) {
          visionPath = fp32V;
          textPath = fp32T;
          print('Using Kitako FP32 from $dir');
          break;
        }
      }

      if (visionPath == null || textPath == null) {
        fail('No Kitako models found in any of: $searchDirs');
      }

      await service.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: 'assets/models/tokenizer/tokenizer.json',
        modelVersion: SiglipModelVersion.siglip2,
      );

      expect(service.isImageEncoderReady, true);
      expect(service.isTextEncoderReady, true);
      print('Model initialized\n');
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 1: Text embedding similarity matrix for all queries
    // ─────────────────────────────────────────────────────────────
    testWidgets('Test 1: How similar is "car" to other queries?', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 1: Pairwise similarity — "car" vs everything');
      print('───────────────────────────────────────────────────────────');
      print('');

      // Embed all queries
      final embeddings = <String, Float32List>{};
      for (final q in queries) {
        embeddings[q] = service.embedText(q);
      }

      // Show similarity of "car" to every other query
      final carEmbed = embeddings['car']!;
      final sims = <MapEntry<String, double>>[];
      for (final entry in embeddings.entries) {
        if (entry.key == 'car') continue;
        sims.add(MapEntry(entry.key, _cosineSimilarity(carEmbed, entry.value)));
      }
      sims.sort((a, b) => b.value.compareTo(a.value));

      print('"car" similarity to other queries (sorted by similarity):');
      print('${'Query'.padRight(24)} ${'Similarity'.padRight(12)}');
      print('${'─' * 24} ${'─' * 12}');
      for (final entry in sims) {
        print('${entry.key.padRight(24)} ${entry.value.toStringAsFixed(4)}');
      }
      print('');

      // Also show: how clustered are vehicle-related vs non-vehicle queries?
      final vehicleQueries = ['car', 'motorcycle', 'bicycle', 'truck', 'bus', 'vehicle'];
      final nonVehicleQueries = ['dog', 'cat', 'tree', 'flower', 'food', 'bird', 'water', 'sky'];

      double vehicleAvg = 0;
      int vehicleCount = 0;
      for (int i = 0; i < vehicleQueries.length; i++) {
        for (int j = i + 1; j < vehicleQueries.length; j++) {
          final ei = embeddings[vehicleQueries[i]];
          final ej = embeddings[vehicleQueries[j]];
          if (ei != null && ej != null) {
            vehicleAvg += _cosineSimilarity(ei, ej);
            vehicleCount++;
          }
        }
      }
      if (vehicleCount > 0) vehicleAvg /= vehicleCount;

      double nonVehicleAvg = 0;
      int nonVehicleCount = 0;
      for (int i = 0; i < nonVehicleQueries.length; i++) {
        for (int j = i + 1; j < nonVehicleQueries.length; j++) {
          final ei = embeddings[nonVehicleQueries[i]];
          final ej = embeddings[nonVehicleQueries[j]];
          if (ei != null && ej != null) {
            nonVehicleAvg += _cosineSimilarity(ei, ej);
            nonVehicleCount++;
          }
        }
      }
      if (nonVehicleCount > 0) nonVehicleAvg /= nonVehicleCount;

      print('Cluster analysis:');
      print('  Vehicle queries avg intra-similarity: ${vehicleAvg.toStringAsFixed(4)}');
      print('  Non-vehicle queries avg intra-similarity: ${nonVehicleAvg.toStringAsFixed(4)}');
      print('');
      if (vehicleAvg > 0.90) {
        print('  WARNING: Vehicle queries are very similar to each other (${vehicleAvg.toStringAsFixed(4)}).');
        print('  The model may not discriminate "car" well from other vehicles.');
      }
      print('');
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 2: Does "a photo of car" help vs bare "car"?
    // ─────────────────────────────────────────────────────────────
    testWidgets('Test 2: Bare "car" vs "a photo of car"', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 2: Does the prompt template help "car"?');
      print('───────────────────────────────────────────────────────────');
      print('');

      final variants = [
        'car',
        'a car',
        'a photo of car',
        'a photo of a car',
        'automobile',
        'red car',
        'car on road',
        'parked car',
      ];

      final embeddings = <String, Float32List>{};
      for (final v in variants) {
        embeddings[v] = service.embedText(v);
      }

      // Compare all variants to each other
      print('${'Query A'.padRight(22)} ${'Query B'.padRight(22)} ${'Similarity'.padRight(12)}');
      print('${'─' * 22} ${'─' * 22} ${'─' * 12}');
      for (int i = 0; i < variants.length; i++) {
        for (int j = i + 1; j < variants.length; j++) {
          final sim = _cosineSimilarity(embeddings[variants[i]]!, embeddings[variants[j]]!);
          print('${variants[i].padRight(22)} ${variants[j].padRight(22)} ${sim.toStringAsFixed(4)}');
        }
      }

      // Also compare to non-car concepts
      print('');
      print('Distance from car variants to non-car concepts:');
      final nonCar = ['dog', 'tree', 'food', 'person', 'sky'];
      final nonCarEmbeds = <String, Float32List>{};
      for (final nc in nonCar) {
        nonCarEmbeds[nc] = service.embedText(nc);
      }

      print('${'Car variant'.padRight(22)} ${'Avg sim to non-car'.padRight(20)} ${'Max sim (which?)'.padRight(24)}');
      print('${'─' * 22} ${'─' * 20} ${'─' * 24}');
      for (final v in variants) {
        double avgSim = 0;
        double maxSim = double.negativeInfinity;
        String maxConcept = '';
        for (final nc in nonCar) {
          final sim = _cosineSimilarity(embeddings[v]!, nonCarEmbeds[nc]!);
          avgSim += sim;
          if (sim > maxSim) {
            maxSim = sim;
            maxConcept = nc;
          }
        }
        avgSim /= nonCar.length;
        print('${v.padRight(22)} ${avgSim.toStringAsFixed(4).padRight(20)} ${maxSim.toStringAsFixed(4)} ($maxConcept)');
      }
      print('');
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 3: Embedding norm analysis — is "car" an outlier?
    // ─────────────────────────────────────────────────────────────
    testWidgets('Test 3: Embedding norm analysis', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 3: Embedding Norms');
      print(' Are some queries producing degenerate embeddings?');
      print('───────────────────────────────────────────────────────────');
      print('');

      print('${'Query'.padRight(24)} ${'L2 Norm'.padRight(12)} ${'Min val'.padRight(12)} ${'Max val'.padRight(12)} ${'Mean val'.padRight(12)}');
      print('${'─' * 24} ${'─' * 12} ${'─' * 12} ${'─' * 12} ${'─' * 12}');

      for (final q in queries) {
        final embed = service.embedText(q);
        double norm = 0, minVal = double.infinity, maxVal = double.negativeInfinity, sum = 0;
        for (int i = 0; i < embed.length; i++) {
          norm += embed[i] * embed[i];
          if (embed[i] < minVal) minVal = embed[i];
          if (embed[i] > maxVal) maxVal = embed[i];
          sum += embed[i];
        }
        norm = math.sqrt(norm);
        final mean = sum / embed.length;

        print('${q.padRight(24)} ${norm.toStringAsFixed(4).padRight(12)} ${minVal.toStringAsFixed(4).padRight(12)} ${maxVal.toStringAsFixed(4).padRight(12)} ${mean.toStringAsFixed(6)}');
      }
      print('');
    });

    testWidgets('Cleanup', (tester) async {
      service.dispose();
      print('Service disposed');
    });
  });
}

Future<bool> _fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

double _cosineSimilarity(Float32List a, Float32List b) {
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = math.sqrt(normA) * math.sqrt(normB);
  return denom == 0 ? 0 : dot / denom;
}
