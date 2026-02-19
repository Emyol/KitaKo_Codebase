import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// Diagnostic test: Does the "a photo of" prompt template fix search quality?
///
/// Compares bare queries ("dog", "pusa") vs templated queries ("a photo of dog",
/// "a photo of pusa") for:
/// 1. Text-text discrimination (do templated queries separate concepts better?)
/// 2. Cross-modal image↔text matching (do templated queries rank images better?)
/// 3. EN vs TL with template (does the template help both languages equally?)
///
/// Run with:
///   flutter test integration_test/prompt_template_diagnostic_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const promptPrefix = 'a photo of ';

  // Concept list: concept → [English, Tagalog]
  final concepts = <String, List<String>>{
    'cat': ['cat', 'pusa'],
    'dog': ['dog', 'aso'],
    'fish': ['fish', 'isda'],
    'bird': ['bird', 'ibon'],
    'tree': ['tree', 'puno'],
    'flower': ['flower', 'bulaklak'],
    'food': ['food', 'pagkain'],
    'house': ['house', 'bahay'],
    'red': ['red', 'pula'],
    'blue': ['blue', 'asul'],
  };

  // Synthetic test images with known colors
  final colorImages = <String, _TestImage>{
    'red': _TestImage(255, 0, 0),
    'green': _TestImage(0, 255, 0),
    'blue': _TestImage(0, 0, 255),
    'yellow': _TestImage(255, 255, 0),
    'white': _TestImage(255, 255, 255),
    'black': _TestImage(0, 0, 0),
  };

  // Color queries in EN and TL
  final colorQueries = <String, List<String>>{
    'red': ['red', 'pula'],
    'green': ['green', 'berde'],
    'blue': ['blue', 'asul'],
    'yellow': ['yellow', 'dilaw'],
    'white': ['white', 'puti'],
    'black': ['black', 'itim'],
  };

  setUpAll(() {
    print('');
    print('═══════════════════════════════════════════════════════════════');
    print(' PROMPT TEMPLATE DIAGNOSTIC');
    print(' Comparing bare queries vs "a photo of <query>" templates');
    print('═══════════════════════════════════════════════════════════════');
    print('');
  });

  group('Prompt Template Diagnostic', () {
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
      print('Model initialized (vision + text ready)\n');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 1: Text-text discrimination with vs without template
    // ─────────────────────────────────────────────────────────────────
    testWidgets('Test 1: Text discrimination — bare vs templated', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 1: Text-Text Discrimination');
      print(' Does the template make concepts more separable?');
      print('───────────────────────────────────────────────────────────');
      print('');

      final entries = concepts.entries.toList();

      // Embed all words bare and templated (EN only)
      final bareEmbeddings = <String, Float32List>{};
      final templatedEmbeddings = <String, Float32List>{};
      for (final entry in entries) {
        final word = entry.value[0]; // English word
        bareEmbeddings[entry.key] = service.embedText(word);
        templatedEmbeddings[entry.key] = service.embedText('$promptPrefix$word');
      }

      // Compute cross-pair similarities for BARE
      final bareCross = <double>[];
      for (int i = 0; i < entries.length; i++) {
        for (int j = i + 1; j < entries.length; j++) {
          final sim = _cosineSimilarity(
            bareEmbeddings[entries[i].key]!,
            bareEmbeddings[entries[j].key]!,
          );
          bareCross.add(sim);
        }
      }
      // Self-similarity is always 1.0, so for "same concept" use the
      // embedding of EN vs its own (trivially 1.0). Instead, measure the
      // spread: how far apart are different concepts?
      final bareAvgCross = bareCross.reduce((a, b) => a + b) / bareCross.length;
      final bareMinCross = bareCross.reduce(math.min);
      final bareMaxCross = bareCross.reduce(math.max);
      final bareSpread = bareMaxCross - bareMinCross;

      // Same for TEMPLATED
      final tmplCross = <double>[];
      for (int i = 0; i < entries.length; i++) {
        for (int j = i + 1; j < entries.length; j++) {
          final sim = _cosineSimilarity(
            templatedEmbeddings[entries[i].key]!,
            templatedEmbeddings[entries[j].key]!,
          );
          tmplCross.add(sim);
        }
      }
      final tmplAvgCross = tmplCross.reduce((a, b) => a + b) / tmplCross.length;
      final tmplMinCross = tmplCross.reduce(math.min);
      final tmplMaxCross = tmplCross.reduce(math.max);
      final tmplSpread = tmplMaxCross - tmplMinCross;

      print('                    BARE words      "a photo of ..." ');
      print('                    ──────────────   ──────────────');
      print('Avg cross-sim:      ${bareAvgCross.toStringAsFixed(4).padRight(16)}${tmplAvgCross.toStringAsFixed(4)}');
      print('Min cross-sim:      ${bareMinCross.toStringAsFixed(4).padRight(16)}${tmplMinCross.toStringAsFixed(4)}');
      print('Max cross-sim:      ${bareMaxCross.toStringAsFixed(4).padRight(16)}${tmplMaxCross.toStringAsFixed(4)}');
      print('Spread (max-min):   ${bareSpread.toStringAsFixed(4).padRight(16)}${tmplSpread.toStringAsFixed(4)}');
      print('');

      // Lower avg cross-sim = better separation between concepts
      // Wider spread = more structure in embedding space
      if (tmplAvgCross < bareAvgCross) {
        print('RESULT: Template LOWERS avg cross-similarity '
            '(${bareAvgCross.toStringAsFixed(4)} -> ${tmplAvgCross.toStringAsFixed(4)}) '
            '= BETTER separation');
      } else {
        print('RESULT: Template does NOT lower avg cross-similarity '
            '(${bareAvgCross.toStringAsFixed(4)} -> ${tmplAvgCross.toStringAsFixed(4)})');
      }
      if (tmplSpread > bareSpread) {
        print('RESULT: Template WIDENS spread '
            '(${bareSpread.toStringAsFixed(4)} -> ${tmplSpread.toStringAsFixed(4)}) '
            '= MORE structure');
      } else {
        print('RESULT: Template does NOT widen spread '
            '(${bareSpread.toStringAsFixed(4)} -> ${tmplSpread.toStringAsFixed(4)})');
      }
      print('');

      // Print pairwise comparison table for first 6 concepts
      final subset = entries.take(6).toList();
      print('Pairwise similarity (first 6 concepts):');
      print('${'Pair'.padRight(20)} ${'Bare'.padRight(10)} ${'Templated'.padRight(10)} ${'Delta'.padRight(10)}');
      print('${'─' * 20} ${'─' * 10} ${'─' * 10} ${'─' * 10}');

      for (int i = 0; i < subset.length; i++) {
        for (int j = i + 1; j < subset.length; j++) {
          final pair = '${subset[i].value[0]}-${subset[j].value[0]}';
          final bareSim = _cosineSimilarity(
            bareEmbeddings[subset[i].key]!,
            bareEmbeddings[subset[j].key]!,
          );
          final tmplSim = _cosineSimilarity(
            templatedEmbeddings[subset[i].key]!,
            templatedEmbeddings[subset[j].key]!,
          );
          final delta = tmplSim - bareSim;
          final sign = delta >= 0 ? '+' : '';
          print('${pair.padRight(20)} '
              '${bareSim.toStringAsFixed(4).padRight(10)} '
              '${tmplSim.toStringAsFixed(4).padRight(10)} '
              '$sign${delta.toStringAsFixed(4)}');
        }
      }
      print('');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 2: Cross-modal image↔text — bare vs templated (English)
    // ─────────────────────────────────────────────────────────────────
    testWidgets('Test 2: Cross-modal EN — bare vs templated', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 2: Image ↔ English Text (bare vs templated)');
      print(' Does "a photo of red" match a red image better than "red"?');
      print('───────────────────────────────────────────────────────────');
      print('');

      // Embed all images
      final imgEmbeddings = <String, Float32List>{};
      for (final entry in colorImages.entries) {
        imgEmbeddings[entry.key] = service.embedImage(entry.value.ppmBytes);
      }

      final colors = colorQueries.keys.toList();

      // For each color: compute image↔bare and image↔templated similarity
      print('${'Color'.padRight(10)} '
          '${'bare sim'.padRight(12)} '
          '${'tmpl sim'.padRight(12)} '
          '${'delta'.padRight(10)} '
          '${'bare rank'.padRight(12)} '
          '${'tmpl rank'.padRight(12)}');
      print('${'─' * 10} ${'─' * 12} ${'─' * 12} ${'─' * 10} ${'─' * 12} ${'─' * 12}');

      int bareCorrect = 0;
      int tmplCorrect = 0;

      for (final color in colors) {
        final imgEmbed = imgEmbeddings[color]!;
        final bareWord = colorQueries[color]![0]; // EN word
        final bareEmbed = service.embedText(bareWord);
        final tmplEmbed = service.embedText('$promptPrefix$bareWord');

        final bareSim = _cosineSimilarity(imgEmbed, bareEmbed);
        final tmplSim = _cosineSimilarity(imgEmbed, tmplEmbed);
        final delta = tmplSim - bareSim;

        // Rank: for this query, which image is top-1?
        final bareRank = _rankImage(color, bareEmbed, imgEmbeddings);
        final tmplRank = _rankImage(color, tmplEmbed, imgEmbeddings);

        if (bareRank == 1) bareCorrect++;
        if (tmplRank == 1) tmplCorrect++;

        final sign = delta >= 0 ? '+' : '';
        print('${color.padRight(10)} '
            '${bareSim.toStringAsFixed(4).padRight(12)} '
            '${tmplSim.toStringAsFixed(4).padRight(12)} '
            '$sign${delta.toStringAsFixed(4).padRight(10)} '
            '${_rankStr(bareRank).padRight(12)} '
            '${_rankStr(tmplRank).padRight(12)}');
      }

      print('');
      print('Correct top-1 (bare):      $bareCorrect / ${colors.length}');
      print('Correct top-1 (templated): $tmplCorrect / ${colors.length}');
      print('');

      if (tmplCorrect > bareCorrect) {
        print('RESULT: Template IMPROVES image ranking');
      } else if (tmplCorrect == bareCorrect) {
        print('RESULT: Template has NO EFFECT on image ranking');
      } else {
        print('RESULT: Template HURTS image ranking');
      }
      print('');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 3: Cross-modal image↔text — bare vs templated (Tagalog)
    // ─────────────────────────────────────────────────────────────────
    testWidgets('Test 3: Cross-modal TL — bare vs templated', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 3: Image ↔ Tagalog Text (bare vs templated)');
      print(' Does "a photo of pula" match a red image better than "pula"?');
      print('───────────────────────────────────────────────────────────');
      print('');

      final imgEmbeddings = <String, Float32List>{};
      for (final entry in colorImages.entries) {
        imgEmbeddings[entry.key] = service.embedImage(entry.value.ppmBytes);
      }

      final colors = colorQueries.keys.toList();

      print('${'Color'.padRight(10)} '
          '${'TL word'.padRight(12)} '
          '${'bare sim'.padRight(12)} '
          '${'tmpl sim'.padRight(12)} '
          '${'delta'.padRight(10)} '
          '${'bare rank'.padRight(12)} '
          '${'tmpl rank'.padRight(12)}');
      print('${'─' * 10} ${'─' * 12} ${'─' * 12} ${'─' * 12} ${'─' * 10} ${'─' * 12} ${'─' * 12}');

      int bareCorrect = 0;
      int tmplCorrect = 0;

      for (final color in colors) {
        final imgEmbed = imgEmbeddings[color]!;
        final tlWord = colorQueries[color]![1]; // TL word
        final bareEmbed = service.embedText(tlWord);
        final tmplEmbed = service.embedText('$promptPrefix$tlWord');

        final bareSim = _cosineSimilarity(imgEmbed, bareEmbed);
        final tmplSim = _cosineSimilarity(imgEmbed, tmplEmbed);
        final delta = tmplSim - bareSim;

        final bareRank = _rankImage(color, bareEmbed, imgEmbeddings);
        final tmplRank = _rankImage(color, tmplEmbed, imgEmbeddings);

        if (bareRank == 1) bareCorrect++;
        if (tmplRank == 1) tmplCorrect++;

        final sign = delta >= 0 ? '+' : '';
        print('${color.padRight(10)} '
            '${tlWord.padRight(12)} '
            '${bareSim.toStringAsFixed(4).padRight(12)} '
            '${tmplSim.toStringAsFixed(4).padRight(12)} '
            '$sign${delta.toStringAsFixed(4).padRight(10)} '
            '${_rankStr(bareRank).padRight(12)} '
            '${_rankStr(tmplRank).padRight(12)}');
      }

      print('');
      print('Correct top-1 (bare TL):      $bareCorrect / ${colors.length}');
      print('Correct top-1 (templated TL): $tmplCorrect / ${colors.length}');
      print('');

      if (tmplCorrect > bareCorrect) {
        print('RESULT: Template IMPROVES Tagalog image ranking');
      } else if (tmplCorrect == bareCorrect) {
        print('RESULT: Template has NO EFFECT on Tagalog image ranking');
      } else {
        print('RESULT: Template HURTS Tagalog image ranking');
      }
      print('');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 4: Full ranking table — image → query ranking
    // ─────────────────────────────────────────────────────────────────
    testWidgets('Test 4: Full ranking — which image does each query find?', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 4: Full Ranking Table');
      print(' For each query, which image is top-1?');
      print('───────────────────────────────────────────────────────────');
      print('');

      final imgEmbeddings = <String, Float32List>{};
      for (final entry in colorImages.entries) {
        imgEmbeddings[entry.key] = service.embedImage(entry.value.ppmBytes);
      }

      // Test various query formats
      final queryFormats = <String, String Function(String en, String tl)>{
        'bare EN': (en, tl) => en,
        'bare TL': (en, tl) => tl,
        'tmpl EN': (en, tl) => '$promptPrefix$en',
        'tmpl TL': (en, tl) => '$promptPrefix$tl',
        'desc EN': (en, tl) => 'a $en colored image',
        'desc TL': (en, tl) => 'isang $tl na larawan',
      };

      // Header
      print('${'Query format'.padRight(14)} '
          '${'Query'.padRight(28)} '
          '${'Expected'.padRight(10)} '
          '${'Got'.padRight(10)} '
          '${'Score'.padRight(10)} '
          '${'Correct'.padRight(8)}');
      print('${'─' * 14} ${'─' * 28} ${'─' * 10} ${'─' * 10} ${'─' * 10} ${'─' * 8}');

      final correctCounts = <String, int>{};
      for (final fmt in queryFormats.keys) {
        correctCounts[fmt] = 0;
      }

      for (final color in colorQueries.keys) {
        final enWord = colorQueries[color]![0];
        final tlWord = colorQueries[color]![1];

        for (final fmtEntry in queryFormats.entries) {
          final query = fmtEntry.value(enWord, tlWord);
          final queryEmbed = service.embedText(query);

          // Find top-1 image
          String bestImg = '';
          double bestSim = double.negativeInfinity;
          for (final imgEntry in imgEmbeddings.entries) {
            final sim = _cosineSimilarity(queryEmbed, imgEntry.value);
            if (sim > bestSim) {
              bestSim = sim;
              bestImg = imgEntry.key;
            }
          }

          final correct = bestImg == color;
          if (correct) correctCounts[fmtEntry.key] = correctCounts[fmtEntry.key]! + 1;

          print('${fmtEntry.key.padRight(14)} '
              '${query.padRight(28)} '
              '${color.padRight(10)} '
              '${bestImg.padRight(10)} '
              '${bestSim.toStringAsFixed(4).padRight(10)} '
              '${correct ? "YES" : "NO"}');
        }
        print('');
      }

      print('───────────────────────────────────────────────────────────');
      print(' SUMMARY: Correct top-1 by query format');
      print('───────────────────────────────────────────────────────────');
      for (final entry in correctCounts.entries) {
        print('  ${entry.key.padRight(14)}: ${entry.value} / ${colorQueries.length}');
      }
      print('');
    });

    // ─────────────────────────────────────────────────────────────────
    // TEST 5: EN-TL discrimination with template
    // ─────────────────────────────────────────────────────────────────
    testWidgets('Test 5: EN-TL discrimination — does template fix it?', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' TEST 5: EN-TL Cross-Lingual Discrimination');
      print(' Does templating fix the same-concept > cross-concept gap?');
      print('───────────────────────────────────────────────────────────');
      print('');

      final entries = concepts.entries.toList();

      // BARE: same-concept EN↔TL vs cross-concept EN↔TL
      final bareSame = <double>[];
      final bareCross = <double>[];
      for (int i = 0; i < entries.length; i++) {
        final enEmbed = service.embedText(entries[i].value[0]);
        final tlEmbed = service.embedText(entries[i].value[1]);
        bareSame.add(_cosineSimilarity(enEmbed, tlEmbed));

        final j = (i + 5) % entries.length;
        final crossTlEmbed = service.embedText(entries[j].value[1]);
        bareCross.add(_cosineSimilarity(enEmbed, crossTlEmbed));
      }

      // TEMPLATED: same-concept EN↔TL vs cross-concept EN↔TL
      final tmplSame = <double>[];
      final tmplCross = <double>[];
      for (int i = 0; i < entries.length; i++) {
        final enEmbed = service.embedText('$promptPrefix${entries[i].value[0]}');
        final tlEmbed = service.embedText('$promptPrefix${entries[i].value[1]}');
        tmplSame.add(_cosineSimilarity(enEmbed, tlEmbed));

        final j = (i + 5) % entries.length;
        final crossTlEmbed = service.embedText('$promptPrefix${entries[j].value[1]}');
        tmplCross.add(_cosineSimilarity(enEmbed, crossTlEmbed));
      }

      final bareAvgSame = bareSame.reduce((a, b) => a + b) / bareSame.length;
      final bareAvgCross = bareCross.reduce((a, b) => a + b) / bareCross.length;
      final bareGap = bareAvgSame - bareAvgCross;

      final tmplAvgSame = tmplSame.reduce((a, b) => a + b) / tmplSame.length;
      final tmplAvgCross = tmplCross.reduce((a, b) => a + b) / tmplCross.length;
      final tmplGap = tmplAvgSame - tmplAvgCross;

      print('                        BARE           TEMPLATED');
      print('                        ──────────     ──────────');
      print('Avg same-concept sim:   ${bareAvgSame.toStringAsFixed(4).padRight(15)}${tmplAvgSame.toStringAsFixed(4)}');
      print('Avg cross-concept sim:  ${bareAvgCross.toStringAsFixed(4).padRight(15)}${tmplAvgCross.toStringAsFixed(4)}');
      print('Discrimination gap:     ${bareGap.toStringAsFixed(4).padRight(15)}${tmplGap.toStringAsFixed(4)}');
      print('');

      if (tmplGap > bareGap) {
        print('RESULT: Template IMPROVES discrimination gap '
            '(${bareGap.toStringAsFixed(4)} -> ${tmplGap.toStringAsFixed(4)})');
      } else {
        print('RESULT: Template does NOT improve discrimination gap '
            '(${bareGap.toStringAsFixed(4)} -> ${tmplGap.toStringAsFixed(4)})');
      }

      if (tmplGap > 0) {
        print('RESULT: With template, same-concept > cross-concept (PASS)');
      } else {
        print('RESULT: With template, same-concept <= cross-concept (FAIL)');
      }
      print('');

      // Per-concept breakdown
      print('Per-concept detail:');
      print('${'Concept'.padRight(12)} '
          '${'Bare same'.padRight(12)} '
          '${'Bare cross'.padRight(12)} '
          '${'Tmpl same'.padRight(12)} '
          '${'Tmpl cross'.padRight(12)}');
      print('${'─' * 12} ${'─' * 12} ${'─' * 12} ${'─' * 12} ${'─' * 12}');

      for (int i = 0; i < entries.length; i++) {
        print('${entries[i].key.padRight(12)} '
            '${bareSame[i].toStringAsFixed(4).padRight(12)} '
            '${bareCross[i].toStringAsFixed(4).padRight(12)} '
            '${tmplSame[i].toStringAsFixed(4).padRight(12)} '
            '${tmplCross[i].toStringAsFixed(4).padRight(12)}');
      }
      print('');
    });

    testWidgets('Cleanup', (tester) async {
      service.dispose();
      print('Service disposed');
    });
  });
}

// ─────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────

/// Solid-color 224x224 PPM test image.
class _TestImage {
  final int r, g, b;
  late final Uint8List ppmBytes;

  _TestImage(this.r, this.g, this.b) {
    const size = 224;
    final header = 'P6\n$size $size\n255\n';
    final headerBytes = header.codeUnits;
    final pixelCount = size * size;
    final rgbBytes = Uint8List(pixelCount * 3);
    for (var i = 0; i < pixelCount; i++) {
      rgbBytes[i * 3] = r;
      rgbBytes[i * 3 + 1] = g;
      rgbBytes[i * 3 + 2] = b;
    }
    final result = Uint8List(headerBytes.length + rgbBytes.length);
    result.setRange(0, headerBytes.length, headerBytes);
    result.setRange(headerBytes.length, result.length, rgbBytes);
    ppmBytes = result;
  }
}

/// Find the rank of [targetColor] when sorting all images by similarity to [queryEmbed].
/// Returns 1 if the target image is the best match.
int _rankImage(String targetColor, Float32List queryEmbed, Map<String, Float32List> imgEmbeddings) {
  final scores = <MapEntry<String, double>>[];
  for (final entry in imgEmbeddings.entries) {
    scores.add(MapEntry(entry.key, _cosineSimilarity(queryEmbed, entry.value)));
  }
  scores.sort((a, b) => b.value.compareTo(a.value));
  for (int i = 0; i < scores.length; i++) {
    if (scores[i].key == targetColor) return i + 1;
  }
  return scores.length + 1;
}

String _rankStr(int rank) => rank == 1 ? '#1 (correct)' : '#$rank';

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
