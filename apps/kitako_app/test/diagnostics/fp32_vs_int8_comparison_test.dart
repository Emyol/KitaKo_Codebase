/// FP32 vs INT8 Model Comparison Test
///
/// Compares the FP32 and INT8 quantized models to determine if
/// quantization is the cause of embedding quality issues.
///
/// Run with: flutter test test/diagnostics/fp32_vs_int8_comparison_test.dart --reporter expanded
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  // Model paths
  const imageModelInt8 = 'assets/model/image_encoder/kitako_image_encoder_int8.onnx';
  const textModelInt8 = 'assets/model/text_encoder/kitako_text_encoder_int8.onnx';
  const imageModelFp32 = 'assets/model/image_encoder/kitako_image_encoder_fp32.onnx';
  const textModelFp32 = 'assets/model/text_encoder/kitako_text_encoder_fp32.onnx';
  const tokenizerPath = 'assets/tokenizer/tokenizer.json';

  group('🔬 FP32 vs INT8: Text Encoder Comparison', () {
    late KitakoEmbeddingService serviceFp32;
    late KitakoEmbeddingService serviceInt8;
    bool fp32Ready = false;
    bool int8Ready = false;

    setUpAll(() async {
      // Check all files exist
      final files = [imageModelInt8, textModelInt8, imageModelFp32, textModelFp32, tokenizerPath];
      for (final f in files) {
        if (!await File(f).exists()) {
          print('⚠️ Missing file: $f');
          return;
        }
      }

      // Initialize FP32 service
      serviceFp32 = KitakoEmbeddingService();
      try {
        await serviceFp32.initializeFromFiles(
          imageModelPath: imageModelFp32,
          textModelPath: textModelFp32,
          tokenizerPath: tokenizerPath,
        );
        fp32Ready = true;
        print('✅ FP32 service initialized');
      } catch (e) {
        print('❌ FP32 init failed: $e');
      }

      // Initialize INT8 service
      serviceInt8 = KitakoEmbeddingService();
      try {
        await serviceInt8.initializeFromFiles(
          imageModelPath: imageModelInt8,
          textModelPath: textModelInt8,
          tokenizerPath: tokenizerPath,
        );
        int8Ready = true;
        print('✅ INT8 service initialized');
      } catch (e) {
        print('❌ INT8 init failed: $e');
      }
    });

    tearDownAll(() {
      serviceFp32.dispose();
      serviceInt8.dispose();
    });

    test('Compare text embedding discrimination', () async {
      if (!fp32Ready || !int8Ready) {
        markTestSkipped('Services not initialized');
        return;
      }

      print('\n' + '=' * 70);
      print('     TEXT ENCODER: FP32 vs INT8 DISCRIMINATION COMPARISON');
      print('=' * 70);

      final categories = {
        'animals': ['cat', 'dog', 'bird', 'fish'],
        'vehicles': ['car', 'truck', 'bus', 'bike'],
        'colors': ['red', 'blue', 'green', 'yellow'],
      };

      for (final model in ['FP32', 'INT8']) {
        final service = model == 'FP32' ? serviceFp32 : serviceInt8;
        
        print('\n📊 $model TEXT ENCODER:');
        print('-' * 40);

        final categoryEmbeddings = <String, List<Float32List>>{};
        
        for (final entry in categories.entries) {
          categoryEmbeddings[entry.key] = [];
          for (final word in entry.value) {
            final emb = await service.embedText(word);
            categoryEmbeddings[entry.key]!.add(emb);
          }
        }

        // Intra-class
        final intraClassSims = <double>[];
        for (final entry in categoryEmbeddings.entries) {
          final embeddings = entry.value;
          for (int i = 0; i < embeddings.length; i++) {
            for (int j = i + 1; j < embeddings.length; j++) {
              intraClassSims.add(service.cosineSimilarity(embeddings[i], embeddings[j]));
            }
          }
        }

        // Inter-class
        final interClassSims = <double>[];
        final categoryNames = categoryEmbeddings.keys.toList();
        for (int i = 0; i < categoryNames.length; i++) {
          for (int j = i + 1; j < categoryNames.length; j++) {
            for (final emb1 in categoryEmbeddings[categoryNames[i]]!) {
              for (final emb2 in categoryEmbeddings[categoryNames[j]]!) {
                interClassSims.add(service.cosineSimilarity(emb1, emb2));
              }
            }
          }
        }

        final avgIntra = intraClassSims.reduce((a, b) => a + b) / intraClassSims.length;
        final avgInter = interClassSims.reduce((a, b) => a + b) / interClassSims.length;
        final gap = avgIntra - avgInter;

        print('  Intra-class avg: ${avgIntra.toStringAsFixed(4)}');
        print('  Inter-class avg: ${avgInter.toStringAsFixed(4)}');
        print('  Separation gap:  ${gap.toStringAsFixed(4)} ${gap < 0.05 ? "❌ BAD" : gap < 0.15 ? "⚠️ WEAK" : "✅ GOOD"}');
      }
    });

    test('Compare opposite concepts', () async {
      if (!fp32Ready || !int8Ready) {
        markTestSkipped('Services not initialized');
        return;
      }

      print('\n' + '=' * 70);
      print('     OPPOSITE CONCEPTS: FP32 vs INT8');
      print('=' * 70);

      final opposites = [
        ['hot', 'cold'],
        ['big', 'small'],
        ['black', 'white'],
        ['happy', 'sad'],
        ['day', 'night'],
      ];

      for (final model in ['FP32', 'INT8']) {
        final service = model == 'FP32' ? serviceFp32 : serviceInt8;
        
        print('\n📊 $model:');
        final sims = <double>[];
        
        for (final pair in opposites) {
          final emb1 = await service.embedText(pair[0]);
          final emb2 = await service.embedText(pair[1]);
          final sim = service.cosineSimilarity(emb1, emb2);
          sims.add(sim);
          print('  ${pair[0].padRight(6)} vs ${pair[1].padRight(6)}: ${sim.toStringAsFixed(4)}');
        }

        final avg = sims.reduce((a, b) => a + b) / sims.length;
        print('  ${'Average'.padRight(15)}: ${avg.toStringAsFixed(4)} ${avg > 0.8 ? "❌ TOO HIGH" : avg > 0.6 ? "⚠️ HIGH" : "✅ OK"}');
      }
    });

    test('Direct embedding comparison (same input)', () async {
      if (!fp32Ready || !int8Ready) {
        markTestSkipped('Services not initialized');
        return;
      }

      print('\n' + '=' * 70);
      print('     DIRECT COMPARISON: FP32 vs INT8 (same inputs)');
      print('=' * 70);

      final testWords = ['cat', 'red car', 'beautiful sunset', 'a photo of a dog'];

      print('\nComparing FP32 and INT8 embeddings for same inputs:');
      for (final word in testWords) {
        final embFp32 = await serviceFp32.embedText(word);
        final embInt8 = await serviceInt8.embedText(word);

        // Cosine similarity between FP32 and INT8 for same input
        final similarity = serviceFp32.cosineSimilarity(embFp32, embInt8);
        
        // MSE between embeddings
        double mse = 0;
        for (int i = 0; i < embFp32.length; i++) {
          final diff = embFp32[i] - embInt8[i];
          mse += diff * diff;
        }
        mse /= embFp32.length;

        print('\n  "$word":');
        print('    FP32↔INT8 similarity: ${similarity.toStringAsFixed(4)}');
        print('    MSE: ${mse.toStringAsFixed(6)}');
        print('    ${similarity > 0.95 ? "✅ Quantization preserved well" : similarity > 0.8 ? "⚠️ Some degradation" : "❌ Significant degradation"}');
      }
    });
  });

  group('🔬 FP32 vs INT8: Image Encoder Comparison', () {
    late KitakoEmbeddingService serviceFp32;
    late KitakoEmbeddingService serviceInt8;
    bool fp32Ready = false;
    bool int8Ready = false;

    setUpAll(() async {
      final files = [imageModelInt8, textModelInt8, imageModelFp32, textModelFp32, tokenizerPath];
      for (final f in files) {
        if (!await File(f).exists()) return;
      }

      serviceFp32 = KitakoEmbeddingService();
      try {
        await serviceFp32.initializeFromFiles(
          imageModelPath: imageModelFp32,
          textModelPath: textModelFp32,
          tokenizerPath: tokenizerPath,
        );
        fp32Ready = true;
      } catch (e) {
        print('❌ FP32 init failed: $e');
      }

      serviceInt8 = KitakoEmbeddingService();
      try {
        await serviceInt8.initializeFromFiles(
          imageModelPath: imageModelInt8,
          textModelPath: textModelInt8,
          tokenizerPath: tokenizerPath,
        );
        int8Ready = true;
      } catch (e) {
        print('❌ INT8 init failed: $e');
      }
    });

    tearDownAll(() {
      serviceFp32.dispose();
      serviceInt8.dispose();
    });

    test('Compare image embeddings for same input', () async {
      if (!fp32Ready || !int8Ready) {
        markTestSkipped('Services not initialized');
        return;
      }

      print('\n' + '=' * 70);
      print('     IMAGE ENCODER: FP32 vs INT8');
      print('=' * 70);

      final testImages = {
        'gray': _createSolidColorImage(0.5, 0.5, 0.5),
        'red': _createSolidColorImage(1.0, 0.0, 0.0),
        'green': _createSolidColorImage(0.0, 1.0, 0.0),
        'blue': _createSolidColorImage(0.0, 0.0, 1.0),
        'black': _createSolidColorImage(0.0, 0.0, 0.0),
        'white': _createSolidColorImage(1.0, 1.0, 1.0),
      };

      print('\nComparing FP32 and INT8 image embeddings:');
      for (final entry in testImages.entries) {
        final embFp32 = await serviceFp32.embedPreprocessedImage(entry.value);
        final embInt8 = await serviceInt8.embedPreprocessedImage(entry.value);

        final similarity = serviceFp32.cosineSimilarity(embFp32, embInt8);

        print('  ${entry.key.padRight(6)}: FP32↔INT8 = ${similarity.toStringAsFixed(4)} '
            '${similarity > 0.95 ? "✅" : similarity > 0.8 ? "⚠️" : "❌"}');
      }
    });

    test('Compare image discrimination', () async {
      if (!fp32Ready || !int8Ready) {
        markTestSkipped('Services not initialized');
        return;
      }

      print('\n' + '=' * 70);
      print('     IMAGE DISCRIMINATION: FP32 vs INT8');
      print('=' * 70);

      final colors = ['red', 'green', 'blue', 'black', 'white'];
      final images = {
        'red': _createSolidColorImage(1.0, 0.0, 0.0),
        'green': _createSolidColorImage(0.0, 1.0, 0.0),
        'blue': _createSolidColorImage(0.0, 0.0, 1.0),
        'black': _createSolidColorImage(0.0, 0.0, 0.0),
        'white': _createSolidColorImage(1.0, 1.0, 1.0),
      };

      for (final model in ['FP32', 'INT8']) {
        final service = model == 'FP32' ? serviceFp32 : serviceInt8;
        
        print('\n📊 $model IMAGE ENCODER:');

        final embeddings = <String, Float32List>{};
        for (final color in colors) {
          embeddings[color] = await service.embedPreprocessedImage(images[color]!);
        }

        // Calculate average pairwise similarity
        final sims = <double>[];
        for (int i = 0; i < colors.length; i++) {
          for (int j = i + 1; j < colors.length; j++) {
            sims.add(service.cosineSimilarity(embeddings[colors[i]]!, embeddings[colors[j]]!));
          }
        }

        final avg = sims.reduce((a, b) => a + b) / sims.length;
        final minSim = sims.reduce(math.min);
        final maxSim = sims.reduce(math.max);

        print('  Avg pairwise similarity: ${avg.toStringAsFixed(4)}');
        print('  Range: ${minSim.toStringAsFixed(4)} - ${maxSim.toStringAsFixed(4)}');
        print('  ${avg < 0.7 ? "✅ Good discrimination" : avg < 0.85 ? "⚠️ Weak" : "❌ Poor discrimination"}');
      }
    });
  });

  group('🔬 FP32 vs INT8: Cross-Modal Alignment', () {
    late KitakoEmbeddingService serviceFp32;
    late KitakoEmbeddingService serviceInt8;
    bool fp32Ready = false;
    bool int8Ready = false;

    setUpAll(() async {
      final files = [imageModelInt8, textModelInt8, imageModelFp32, textModelFp32, tokenizerPath];
      for (final f in files) {
        if (!await File(f).exists()) return;
      }

      serviceFp32 = KitakoEmbeddingService();
      try {
        await serviceFp32.initializeFromFiles(
          imageModelPath: imageModelFp32,
          textModelPath: textModelFp32,
          tokenizerPath: tokenizerPath,
        );
        fp32Ready = true;
      } catch (e) {
        print('❌ FP32 init failed: $e');
      }

      serviceInt8 = KitakoEmbeddingService();
      try {
        await serviceInt8.initializeFromFiles(
          imageModelPath: imageModelInt8,
          textModelPath: textModelInt8,
          tokenizerPath: tokenizerPath,
        );
        int8Ready = true;
      } catch (e) {
        print('❌ INT8 init failed: $e');
      }
    });

    tearDownAll(() {
      serviceFp32.dispose();
      serviceInt8.dispose();
    });

    test('Cross-modal alignment comparison', () async {
      if (!fp32Ready || !int8Ready) {
        markTestSkipped('Services not initialized');
        return;
      }

      print('\n' + '=' * 70);
      print('     CROSS-MODAL ALIGNMENT: FP32 vs INT8');
      print('=' * 70);

      final colors = ['red', 'green', 'blue', 'black', 'white'];
      final colorRgb = {
        'red': [1.0, 0.0, 0.0],
        'green': [0.0, 1.0, 0.0],
        'blue': [0.0, 0.0, 1.0],
        'black': [0.0, 0.0, 0.0],
        'white': [1.0, 1.0, 1.0],
      };

      for (final model in ['FP32', 'INT8']) {
        final service = model == 'FP32' ? serviceFp32 : serviceInt8;
        
        print('\n📊 $model CROSS-MODAL:');

        // Get embeddings
        final textEmbs = <String, Float32List>{};
        final imageEmbs = <String, Float32List>{};
        
        for (final color in colors) {
          textEmbs[color] = await service.embedText(color);
          final rgb = colorRgb[color]!;
          imageEmbs[color] = await service.embedPreprocessedImage(
            _createSolidColorImage(rgb[0], rgb[1], rgb[2])
          );
        }

        // Build similarity matrix
        print('\n  Image\\Text |${colors.map((c) => c.padLeft(7)).join('')}');
        print('  ' + '-' * 45);

        final matchingSims = <double>[];
        final nonMatchingSims = <double>[];

        for (final imgColor in colors) {
          final row = <String>['  ${imgColor.padRight(10)}'];
          for (final txtColor in colors) {
            final sim = service.cosineSimilarity(imageEmbs[imgColor]!, textEmbs[txtColor]!);
            row.add(sim.toStringAsFixed(3).padLeft(7));
            
            if (imgColor == txtColor) {
              matchingSims.add(sim);
            } else {
              nonMatchingSims.add(sim);
            }
          }
          print(row.join(''));
        }

        final avgMatching = matchingSims.reduce((a, b) => a + b) / matchingSims.length;
        final avgNonMatching = nonMatchingSims.reduce((a, b) => a + b) / nonMatchingSims.length;
        final gap = avgMatching - avgNonMatching;

        print('\n  Matching (diagonal): ${avgMatching.toStringAsFixed(4)}');
        print('  Non-matching:        ${avgNonMatching.toStringAsFixed(4)}');
        print('  Alignment gap:       ${gap.toStringAsFixed(4)} ${gap < 0.02 ? "❌ NO ALIGNMENT" : gap < 0.1 ? "⚠️ WEAK" : "✅ GOOD"}');
      }
    });
  });

  group('🔬 FINAL VERDICT', () {
    test('Summary', () {
      print('\n' + '=' * 70);
      print('                    INTERPRETATION GUIDE');
      print('=' * 70);
      print('''

┌────────────────────────────────────────────────────────────────────┐
│ RESULT PATTERN                   │ DIAGNOSIS                       │
├────────────────────────────────────────────────────────────────────┤
│ FP32 good, INT8 bad              │ ❌ QUANTIZATION is the problem   │
│ (large gap difference)           │ → Re-quantize with calibration  │
├────────────────────────────────────────────────────────────────────┤
│ Both FP32 and INT8 bad           │ ❌ ORIGINAL MODEL is the problem │
│ (both show poor discrimination)  │ → Model training or export issue│
├────────────────────────────────────────────────────────────────────┤
│ Both show no cross-modal align   │ ❌ Models are MISMATCHED         │
│                                  │ → Check if from same checkpoint │
├────────────────────────────────────────────────────────────────────┤
│ FP32↔INT8 similarity < 0.9       │ ⚠️ Significant quant degradation │
│ for same inputs                  │ → Too aggressive quantization   │
└────────────────────────────────────────────────────────────────────┘

''');
    });
  });
}

/// Create a solid color test image in NCHW format [1, 3, 224, 224]
Float32List _createSolidColorImage(double r, double g, double b) {
  const size = 224;
  const channels = 3;
  
  final rNorm = (r - 0.5) / 0.5;
  final gNorm = (g - 0.5) / 0.5;
  final bNorm = (b - 0.5) / 0.5;
  
  final data = Float32List(1 * channels * size * size);
  
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      data[0 * size * size + y * size + x] = rNorm;
      data[1 * size * size + y * size + x] = gNorm;
      data[2 * size * size + y * size + x] = bNorm;
    }
  }
  
  return data;
}
