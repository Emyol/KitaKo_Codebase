import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// Cross-lingual embedding test: English vs Tagalog/Filipino.
///
/// Verifies that the SigLIP text encoder maps semantically equivalent
/// words/phrases across languages into nearby embedding vectors.
///
/// Run with:
///   flutter test integration_test/cross_lingual_embedding_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // English-Tagalog word/phrase pairs (concept → [English, Tagalog])
  final wordPairs = <String, List<String>>{
    'cat':       ['cat',        'pusa'],
    'dog':       ['dog',        'aso'],
    'fish':      ['fish',       'isda'],
    'bird':      ['bird',       'ibon'],
    'tree':      ['tree',       'puno'],
    'flower':    ['flower',     'bulaklak'],
    'water':     ['water',      'tubig'],
    'fire':      ['fire',       'apoy'],
    'sun':       ['sun',        'araw'],
    'moon':      ['moon',       'buwan'],
    'house':     ['house',      'bahay'],
    'food':      ['food',       'pagkain'],
    'child':     ['child',      'bata'],
    'mother':    ['mother',     'nanay'],
    'father':    ['father',     'tatay'],
    'beautiful': ['beautiful',  'maganda'],
    'big':       ['big',        'malaki'],
    'small':     ['small',      'maliit'],
    'red':       ['red',        'pula'],
    'blue':      ['blue',       'asul'],
  };

  // Longer phrases
  final phrasePairs = <String, List<String>>{
    'cat on table':     ['a cat sitting on a table',       'isang pusa na nakaupo sa mesa'],
    'dog in park':      ['a dog running in the park',      'isang aso na tumatakbo sa parke'],
    'beautiful flower': ['a beautiful flower in a garden',  'isang magandang bulaklak sa hardin'],
    'child playing':    ['a child playing outside',         'isang batang naglalaro sa labas'],
    'food on plate':    ['food on a plate',                 'pagkain sa plato'],
  };

  setUpAll(() async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print(' Cross-Lingual Embedding Test: English vs Tagalog');
    print('═══════════════════════════════════════════════════════════');
    print('');
  });

  group('Cross-Lingual Embeddings', () {
    late OnnxEmbeddingService service;

    testWidgets('Initialize model', (tester) async {
      service = OnnxEmbeddingService();

      // Search all locations the app uses (same as ModelDownloadService)
      final appDir = await getApplicationDocumentsDirectory();
      final searchDirs = [
        '${appDir.path}/onnx_models',    // app cache
        '/data/local/tmp',                // ADB push location
      ];

      print('Searching for models in:');
      for (final dir in searchDirs) {
        print('  - $dir');
      }

      // Try INT8 first (what runs on mobile), fall back to FP32
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

      expect(service.isTextEncoderReady, true);
      print('Model initialized successfully\n');
    });

    testWidgets('Single-word English vs Tagalog similarity', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Single Words: English vs Tagalog Translation');
      print('───────────────────────────────────────────────────────────');
      print('');
      print('${'Concept'.padRight(12)} ${'English'.padRight(12)} ${'Tagalog'.padRight(12)} ${'Cosine Sim'.padRight(10)}');
      print('${'─' * 12} ${'─' * 12} ${'─' * 12} ${'─' * 10}');

      final similarities = <double>[];

      for (final entry in wordPairs.entries) {
        final concept = entry.key;
        final en = entry.value[0];
        final tl = entry.value[1];

        final enEmbed = service.embedText(en);
        final tlEmbed = service.embedText(tl);
        final sim = _cosineSimilarity(enEmbed, tlEmbed);
        similarities.add(sim);

        print('${concept.padRight(12)} ${en.padRight(12)} ${tl.padRight(12)} ${sim.toStringAsFixed(4)}');
      }

      final avgSim = similarities.reduce((a, b) => a + b) / similarities.length;
      final minSim = similarities.reduce(math.min);
      final maxSim = similarities.reduce(math.max);

      print('');
      print('Average similarity: ${avgSim.toStringAsFixed(4)}');
      print('Min:                ${minSim.toStringAsFixed(4)}');
      print('Max:                ${maxSim.toStringAsFixed(4)}');
      print('');
    });

    testWidgets('Phrase-level English vs Tagalog similarity', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Phrases: English vs Tagalog Translation');
      print('───────────────────────────────────────────────────────────');
      print('');

      final similarities = <double>[];

      for (final entry in phrasePairs.entries) {
        final concept = entry.key;
        final en = entry.value[0];
        final tl = entry.value[1];

        final enEmbed = service.embedText(en);
        final tlEmbed = service.embedText(tl);
        final sim = _cosineSimilarity(enEmbed, tlEmbed);
        similarities.add(sim);

        print('[$concept]');
        print('  EN: "$en"');
        print('  TL: "$tl"');
        print('  Cosine similarity: ${sim.toStringAsFixed(4)}');
        print('');
      }

      final avgSim = similarities.reduce((a, b) => a + b) / similarities.length;
      print('Average phrase similarity: ${avgSim.toStringAsFixed(4)}');
      print('');
    });

    testWidgets('Cross-concept discrimination (sanity check)', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Discrimination: Same-concept vs Different-concept');
      print('───────────────────────────────────────────────────────────');
      print('');
      print('Same-concept pairs (EN-TL translations) should score HIGHER');
      print('than cross-concept pairs (unrelated words).');
      print('');

      // Compute same-concept similarities (EN word vs its TL translation)
      final sameConcept = <double>[];
      final entries = wordPairs.entries.toList();
      for (final entry in entries) {
        final enEmbed = service.embedText(entry.value[0]);
        final tlEmbed = service.embedText(entry.value[1]);
        sameConcept.add(_cosineSimilarity(enEmbed, tlEmbed));
      }

      // Compute cross-concept similarities (EN word vs unrelated TL word)
      final crossConcept = <double>[];
      for (int i = 0; i < entries.length; i++) {
        // Compare each English word with a Tagalog word 5 positions away
        final j = (i + 5) % entries.length;
        final enEmbed = service.embedText(entries[i].value[0]);
        final tlEmbed = service.embedText(entries[j].value[1]);
        final sim = _cosineSimilarity(enEmbed, tlEmbed);
        crossConcept.add(sim);
      }

      final avgSame = sameConcept.reduce((a, b) => a + b) / sameConcept.length;
      final avgCross = crossConcept.reduce((a, b) => a + b) / crossConcept.length;
      final gap = avgSame - avgCross;

      print('Average same-concept similarity:  ${avgSame.toStringAsFixed(4)}');
      print('Average cross-concept similarity: ${avgCross.toStringAsFixed(4)}');
      print('Discrimination gap:               ${gap.toStringAsFixed(4)}');
      print('');

      if (gap > 0) {
        print('PASS: Same-concept pairs score higher than cross-concept');
      } else {
        print('FAIL: Model cannot distinguish same vs different concepts');
      }

      expect(avgSame, greaterThan(avgCross),
          reason: 'Translations should be more similar than unrelated words');
      print('');
    });

    testWidgets('Full similarity matrix (first 6 words)', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Similarity Matrix (EN vs TL, first 6 words)');
      print('───────────────────────────────────────────────────────────');
      print('');

      final subset = wordPairs.entries.take(6).toList();
      final enEmbeddings = <String, Float32List>{};
      final tlEmbeddings = <String, Float32List>{};

      for (final entry in subset) {
        enEmbeddings[entry.key] = service.embedText(entry.value[0]);
        tlEmbeddings[entry.key] = service.embedText(entry.value[1]);
      }

      // Header row: TL words
      final header = ''.padRight(10) +
          subset.map((e) => e.value[1].padRight(10)).join();
      print(header);
      print('${'─' * 10}${'─' * (10 * subset.length)}');

      // Each row: EN word vs all TL words
      for (final enEntry in subset) {
        final enEmbed = enEmbeddings[enEntry.key]!;
        final row = StringBuffer(enEntry.value[0].padRight(10));

        for (final tlEntry in subset) {
          final tlEmbed = tlEmbeddings[tlEntry.key]!;
          final sim = _cosineSimilarity(enEmbed, tlEmbed);
          // Highlight diagonal (same concept) with asterisk
          final marker = enEntry.key == tlEntry.key ? '*' : ' ';
          row.write('${sim.toStringAsFixed(3)}$marker'.padRight(10));
        }
        print(row.toString());
      }

      print('');
      print('* = same concept (should be highest in its row)');
      print('');

      // Verify diagonal dominance: each EN word should be most similar
      // to its own TL translation
      int diagonalWins = 0;
      for (final enEntry in subset) {
        final enEmbed = enEmbeddings[enEntry.key]!;
        double bestSim = double.negativeInfinity;
        String bestMatch = '';

        for (final tlEntry in subset) {
          final sim = _cosineSimilarity(enEmbed, tlEmbeddings[tlEntry.key]!);
          if (sim > bestSim) {
            bestSim = sim;
            bestMatch = tlEntry.key;
          }
        }

        if (bestMatch == enEntry.key) diagonalWins++;
      }

      print('Diagonal wins: $diagonalWins / ${subset.length}');
      print('(How many EN words matched their TL translation as top-1)');
      print('');
    });

    testWidgets('Cleanup', (tester) async {
      service.dispose();
      print('Service disposed');
    });
  });
}

/// Check if a file exists at the given path.
Future<bool> _fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

/// Cosine similarity between two Float32List vectors.
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
