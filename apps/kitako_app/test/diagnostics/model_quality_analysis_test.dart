/// Model Quality Analysis Test
///
/// Comprehensive analysis to determine if embedding issues are caused by:
/// 1. INT8 quantization degradation
/// 2. Original model training/architecture issues
/// 3. Incorrect preprocessing/inference pipeline
///
/// Run with: flutter test test/diagnostics/model_quality_analysis_test.dart --reporter expanded
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  // Model paths
  const imageModelPath =
      'assets/model/image_encoder/kitako_image_encoder_int8.onnx';
  const textModelPath =
      'assets/model/text_encoder/kitako_text_encoder_int8.onnx';
  const tokenizerPath = 'assets/tokenizer/tokenizer.json';

  group('📊 ANALYSIS 1: Embedding Distribution Statistics', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();
      if (await _filesExist([imageModelPath, textModelPath, tokenizerPath])) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('❌ Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() => service.dispose());

    test('Text embedding value distribution', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final testWords = ['cat', 'dog', 'car', 'tree', 'red', 'blue', 'happy', 'sad'];
      final allValues = <double>[];
      
      print('\n📊 Text Embedding Distribution Analysis');
      print('=' * 60);

      for (final word in testWords) {
        final emb = await service.embedText(word);
        final stats = _computeStats(emb);
        allValues.addAll(emb.map((e) => e.toDouble()));
        
        print('\n"$word":');
        print('  Mean: ${stats.mean.toStringAsFixed(6)}');
        print('  Std:  ${stats.std.toStringAsFixed(6)}');
        print('  Min:  ${stats.min.toStringAsFixed(6)}');
        print('  Max:  ${stats.max.toStringAsFixed(6)}');
        print('  Range: ${(stats.max - stats.min).toStringAsFixed(6)}');
      }

      final globalStats = _computeStatsFromDoubles(allValues);
      print('\n' + '=' * 60);
      print('GLOBAL STATISTICS (all text embeddings combined):');
      print('  Mean: ${globalStats.mean.toStringAsFixed(6)}');
      print('  Std:  ${globalStats.std.toStringAsFixed(6)}');
      print('  Min:  ${globalStats.min.toStringAsFixed(6)}');
      print('  Max:  ${globalStats.max.toStringAsFixed(6)}');
      
      // Expected for healthy CLIP/SigLIP: mean ≈ 0, std ≈ 0.03-0.05
      print('\n📋 DIAGNOSIS:');
      if (globalStats.std < 0.01) {
        print('  ⚠️ PROBLEM: Very low variance - embeddings may be collapsed');
      } else if (globalStats.std > 0.1) {
        print('  ⚠️ PROBLEM: High variance - possible numerical instability');
      } else {
        print('  ✅ Variance appears normal');
      }
      
      if (globalStats.mean.abs() > 0.1) {
        print('  ⚠️ PROBLEM: Non-zero mean bias detected');
      } else {
        print('  ✅ Mean is centered near zero');
      }
    });

    test('Image embedding value distribution', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Image Embedding Distribution Analysis');
      print('=' * 60);

      // Create different test images
      final testImages = {
        'gray (0.5)': _createSolidColorImage(0.5, 0.5, 0.5),
        'black (0.0)': _createSolidColorImage(0.0, 0.0, 0.0),
        'white (1.0)': _createSolidColorImage(1.0, 1.0, 1.0),
        'red': _createSolidColorImage(1.0, 0.0, 0.0),
        'green': _createSolidColorImage(0.0, 1.0, 0.0),
        'blue': _createSolidColorImage(0.0, 0.0, 1.0),
      };

      final allValues = <double>[];

      for (final entry in testImages.entries) {
        final emb = await service.embedPreprocessedImage(entry.value);
        final stats = _computeStats(emb);
        allValues.addAll(emb.map((e) => e.toDouble()));
        
        print('\n"${entry.key}":');
        print('  Mean: ${stats.mean.toStringAsFixed(6)}');
        print('  Std:  ${stats.std.toStringAsFixed(6)}');
        print('  Min:  ${stats.min.toStringAsFixed(6)}');
        print('  Max:  ${stats.max.toStringAsFixed(6)}');
      }

      final globalStats = _computeStatsFromDoubles(allValues);
      print('\n' + '=' * 60);
      print('GLOBAL IMAGE STATISTICS:');
      print('  Mean: ${globalStats.mean.toStringAsFixed(6)}');
      print('  Std:  ${globalStats.std.toStringAsFixed(6)}');
    });
  });

  group('📊 ANALYSIS 2: Semantic Discrimination Quality', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();
      if (await _filesExist([imageModelPath, textModelPath, tokenizerPath])) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('❌ Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() => service.dispose());

    test('Intra-class vs Inter-class similarity', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Semantic Discrimination Analysis');
      print('=' * 60);

      // Define semantic categories
      final categories = {
        'animals': ['cat', 'dog', 'bird', 'fish', 'horse'],
        'vehicles': ['car', 'truck', 'bus', 'motorcycle', 'bicycle'],
        'colors': ['red', 'blue', 'green', 'yellow', 'orange'],
        'emotions': ['happy', 'sad', 'angry', 'scared', 'excited'],
      };

      final categoryEmbeddings = <String, List<Float32List>>{};
      
      // Get embeddings for all words
      for (final entry in categories.entries) {
        categoryEmbeddings[entry.key] = [];
        for (final word in entry.value) {
          final emb = await service.embedText(word);
          categoryEmbeddings[entry.key]!.add(emb);
        }
      }

      // Calculate intra-class similarities
      print('\n🔵 INTRA-CLASS SIMILARITIES (same category):');
      final intraClassSims = <double>[];
      
      for (final entry in categoryEmbeddings.entries) {
        final embeddings = entry.value;
        final sims = <double>[];
        
        for (int i = 0; i < embeddings.length; i++) {
          for (int j = i + 1; j < embeddings.length; j++) {
            final sim = service.cosineSimilarity(embeddings[i], embeddings[j]);
            sims.add(sim);
            intraClassSims.add(sim);
          }
        }
        
        final avgSim = sims.reduce((a, b) => a + b) / sims.length;
        print('  ${entry.key}: avg=${avgSim.toStringAsFixed(4)} '
            '(range: ${sims.reduce(math.min).toStringAsFixed(4)}-${sims.reduce(math.max).toStringAsFixed(4)})');
      }

      // Calculate inter-class similarities
      print('\n🔴 INTER-CLASS SIMILARITIES (different categories):');
      final interClassSims = <double>[];
      final categoryNames = categoryEmbeddings.keys.toList();
      
      for (int i = 0; i < categoryNames.length; i++) {
        for (int j = i + 1; j < categoryNames.length; j++) {
          final cat1 = categoryNames[i];
          final cat2 = categoryNames[j];
          final sims = <double>[];
          
          for (final emb1 in categoryEmbeddings[cat1]!) {
            for (final emb2 in categoryEmbeddings[cat2]!) {
              final sim = service.cosineSimilarity(emb1, emb2);
              sims.add(sim);
              interClassSims.add(sim);
            }
          }
          
          final avgSim = sims.reduce((a, b) => a + b) / sims.length;
          print('  $cat1 vs $cat2: ${avgSim.toStringAsFixed(4)}');
        }
      }

      // Summary
      final avgIntra = intraClassSims.reduce((a, b) => a + b) / intraClassSims.length;
      final avgInter = interClassSims.reduce((a, b) => a + b) / interClassSims.length;
      final separation = avgIntra - avgInter;

      print('\n' + '=' * 60);
      print('DISCRIMINATION SUMMARY:');
      print('  Avg Intra-class similarity: ${avgIntra.toStringAsFixed(4)}');
      print('  Avg Inter-class similarity: ${avgInter.toStringAsFixed(4)}');
      print('  Separation gap: ${separation.toStringAsFixed(4)}');

      print('\n📋 DIAGNOSIS:');
      if (separation < 0.05) {
        print('  ❌ CRITICAL: Near-zero separation - embeddings are NOT discriminative');
        print('     This indicates a fundamental model problem (quantization OR training)');
      } else if (separation < 0.15) {
        print('  ⚠️ WARNING: Low separation - model has weak semantic discrimination');
        print('     Likely caused by aggressive INT8 quantization');
      } else {
        print('  ✅ Good separation - model discriminates semantic categories well');
      }

      // Expected values for healthy model
      print('\n📈 EXPECTED VALUES (healthy CLIP/SigLIP):');
      print('  Intra-class: 0.50-0.70');
      print('  Inter-class: 0.20-0.40');
      print('  Separation:  0.15-0.30');
      
      print('\n📈 YOUR VALUES:');
      print('  Intra-class: ${avgIntra.toStringAsFixed(4)} ${avgIntra > 0.85 ? "⚠️ TOO HIGH" : avgIntra < 0.4 ? "⚠️ TOO LOW" : "✅"}');
      print('  Inter-class: ${avgInter.toStringAsFixed(4)} ${avgInter > 0.75 ? "⚠️ TOO HIGH" : "✅"}');
    });

    test('Opposite concepts similarity', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Opposite Concepts Analysis');
      print('=' * 60);

      final opposites = [
        ['hot', 'cold'],
        ['big', 'small'],
        ['up', 'down'],
        ['left', 'right'],
        ['black', 'white'],
        ['day', 'night'],
        ['happy', 'sad'],
        ['fast', 'slow'],
      ];

      final similarities = <double>[];
      
      for (final pair in opposites) {
        final emb1 = await service.embedText(pair[0]);
        final emb2 = await service.embedText(pair[1]);
        final sim = service.cosineSimilarity(emb1, emb2);
        similarities.add(sim);
        
        print('  ${pair[0]} vs ${pair[1]}: ${sim.toStringAsFixed(4)}');
      }

      final avgSim = similarities.reduce((a, b) => a + b) / similarities.length;
      print('\n  Average opposite similarity: ${avgSim.toStringAsFixed(4)}');

      print('\n📋 DIAGNOSIS:');
      if (avgSim > 0.9) {
        print('  ❌ CRITICAL: Opposites are nearly identical (${avgSim.toStringAsFixed(2)})');
        print('     Model cannot distinguish antonyms - severe degradation');
      } else if (avgSim > 0.7) {
        print('  ⚠️ WARNING: Opposites too similar - weak discrimination');
      } else if (avgSim > 0.4) {
        print('  ✅ Reasonable - opposites have some distinction');
      } else {
        print('  ✅ Good - opposites are well separated');
      }

      print('\n📈 EXPECTED: Opposite similarity should be 0.3-0.6');
    });
  });

  group('📊 ANALYSIS 3: Cross-Modal Alignment', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();
      if (await _filesExist([imageModelPath, textModelPath, tokenizerPath])) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('❌ Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() => service.dispose());

    test('Solid color image vs color text alignment', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Cross-Modal Alignment: Colors');
      print('=' * 60);

      final colors = ['red', 'green', 'blue', 'black', 'white'];
      final colorRgb = {
        'red': [1.0, 0.0, 0.0],
        'green': [0.0, 1.0, 0.0],
        'blue': [0.0, 0.0, 1.0],
        'black': [0.0, 0.0, 0.0],
        'white': [1.0, 1.0, 1.0],
      };

      // Get text embeddings
      final textEmbeddings = <String, Float32List>{};
      for (final color in colors) {
        textEmbeddings[color] = await service.embedText('a photo of $color');
      }

      // Get image embeddings
      final imageEmbeddings = <String, Float32List>{};
      for (final color in colors) {
        final rgb = colorRgb[color]!;
        final image = _createSolidColorImage(rgb[0], rgb[1], rgb[2]);
        imageEmbeddings[color] = await service.embedPreprocessedImage(image);
      }

      // Build similarity matrix
      print('\nImage\\Text |${colors.map((c) => c.padLeft(8)).join('')}');
      print('-' * 50);

      final matchingSims = <double>[];
      final nonMatchingSims = <double>[];

      for (final imgColor in colors) {
        final row = <String>[imgColor.padRight(10)];
        for (final txtColor in colors) {
          final sim = service.cosineSimilarity(
              imageEmbeddings[imgColor]!, textEmbeddings[txtColor]!);
          row.add(sim.toStringAsFixed(3).padLeft(8));
          
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
      final alignmentGap = avgMatching - avgNonMatching;

      print('\n' + '=' * 60);
      print('ALIGNMENT SUMMARY:');
      print('  Avg matching (diagonal): ${avgMatching.toStringAsFixed(4)}');
      print('  Avg non-matching: ${avgNonMatching.toStringAsFixed(4)}');
      print('  Alignment gap: ${alignmentGap.toStringAsFixed(4)}');

      print('\n📋 DIAGNOSIS:');
      if (alignmentGap < 0.02) {
        print('  ❌ CRITICAL: No cross-modal alignment detected');
        print('     Image and text encoders are NOT in the same embedding space');
        print('     Possible causes:');
        print('       1. Models from different training runs');
        print('       2. Quantization destroyed alignment');
        print('       3. Missing/wrong projection layer');
      } else if (alignmentGap < 0.1) {
        print('  ⚠️ WARNING: Weak cross-modal alignment');
      } else {
        print('  ✅ Good cross-modal alignment');
      }

      print('\n📈 EXPECTED VALUES (healthy CLIP/SigLIP):');
      print('  Matching pairs: 0.20-0.35');
      print('  Non-matching: 0.05-0.15');
      print('  Alignment gap: 0.10-0.25');
    });

    test('Image embedding vs random text embedding', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Random Alignment Check');
      print('=' * 60);

      // Create a test image
      final testImage = _createSolidColorImage(0.5, 0.3, 0.7); // purple-ish
      final imageEmb = await service.embedPreprocessedImage(testImage);

      // Test against completely unrelated text
      final unrelatedTexts = [
        'democracy and freedom',
        'mathematical equations',
        'ancient philosophy',
        'quantum mechanics',
        'jazz music improvisation',
      ];

      final sims = <double>[];
      for (final text in unrelatedTexts) {
        final textEmb = await service.embedText(text);
        final sim = service.cosineSimilarity(imageEmb, textEmb);
        sims.add(sim);
        print('  Image vs "$text": ${sim.toStringAsFixed(4)}');
      }

      final avgSim = sims.reduce((a, b) => a + b) / sims.length;
      print('\n  Average: ${avgSim.toStringAsFixed(4)}');

      print('\n📋 DIAGNOSIS:');
      if (avgSim.abs() < 0.05) {
        print('  ✅ Good - unrelated image-text pairs have near-zero similarity');
      } else if (avgSim > 0.15) {
        print('  ⚠️ WARNING: Unrelated pairs have suspiciously high similarity');
        print('     This suggests embeddings have a shared bias component');
      }
    });
  });

  group('📊 ANALYSIS 4: Quantization Artifact Detection', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();
      if (await _filesExist([imageModelPath, textModelPath, tokenizerPath])) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('❌ Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() => service.dispose());

    test('Embedding value quantization analysis', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Quantization Artifact Analysis');
      print('=' * 60);

      final embedding = await service.embedText('a photo of a cat');
      
      // Count unique values (quantized models have fewer unique values)
      final uniqueValues = embedding.toSet();
      final uniqueRatio = uniqueValues.length / embedding.length;
      
      print('\nEmbedding dimension: ${embedding.length}');
      print('Unique values: ${uniqueValues.length}');
      print('Unique ratio: ${(uniqueRatio * 100).toStringAsFixed(2)}%');

      // Histogram of value distribution
      final histogram = <int, int>{};
      for (final v in embedding) {
        final bucket = (v * 100).round(); // 0.01 precision buckets
        histogram[bucket] = (histogram[bucket] ?? 0) + 1;
      }

      print('\nValue distribution (buckets with >10 values):');
      final sortedBuckets = histogram.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      for (final entry in sortedBuckets.take(15)) {
        if (entry.value > 10) {
          final bucketValue = entry.key / 100.0;
          final bar = '█' * (entry.value ~/ 5);
          print('  ${bucketValue.toStringAsFixed(2).padLeft(6)}: $bar (${entry.value})');
        }
      }

      print('\n📋 DIAGNOSIS:');
      if (uniqueRatio < 0.5) {
        print('  ⚠️ WARNING: Low unique value ratio (${(uniqueRatio * 100).toStringAsFixed(1)}%)');
        print('     INT8 quantization may have caused significant precision loss');
      } else {
        print('  ✅ Unique value ratio appears reasonable');
      }

      // Check for suspicious value clustering
      final zeroCount = embedding.where((v) => v.abs() < 0.001).length;
      final zeroRatio = zeroCount / embedding.length;
      print('\n  Near-zero values: $zeroCount (${(zeroRatio * 100).toStringAsFixed(1)}%)');
      
      if (zeroRatio > 0.3) {
        print('  ⚠️ WARNING: Many near-zero values - possible sparse/dead units');
      }
    });

    test('Sensitivity to small input changes', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Input Sensitivity Analysis');
      print('=' * 60);

      // Test if model is sensitive to small changes
      final baseText = 'cat';
      final variants = [
        'cat',
        'Cat',
        'CAT',
        'cats',
        'a cat',
        'the cat',
        'cat.',
      ];

      final baseEmb = await service.embedText(baseText);
      
      print('\nComparing "$baseText" to variants:');
      for (final variant in variants) {
        final varEmb = await service.embedText(variant);
        final sim = service.cosineSimilarity(baseEmb, varEmb);
        final marker = sim > 0.99 ? '⚠️ IDENTICAL' : sim > 0.95 ? '~same' : '✓ different';
        print('  "$variant": ${sim.toStringAsFixed(4)} $marker');
      }

      print('\n📋 DIAGNOSIS:');
      print('  If all variants show >0.99 similarity, the model may be');
      print('  over-smoothed by quantization (lost fine-grained distinctions)');
    });
  });

  group('📊 ANALYSIS 5: Model Architecture Verification', () {
    late SiglipInference inference;
    late SiglipTokenizer tokenizer;
    bool initialized = false;

    setUpAll(() async {
      if (await _filesExist([imageModelPath, textModelPath, tokenizerPath])) {
        try {
          inference = SiglipInference();
          await inference.loadImageModelFromFile(imageModelPath);
          await inference.loadTextModelFromFile(textModelPath);
          
          tokenizer = SiglipTokenizer();
          await tokenizer.loadFromFile(tokenizerPath);
          
          initialized = true;
        } catch (e) {
          print('❌ Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() => inference.dispose());

    test('Raw model output analysis (before normalization)', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      print('\n📊 Raw Model Output Analysis');
      print('=' * 60);

      // Get raw text embedding
      final tokens = tokenizer.encode('a photo of a cat');
      final rawTextEmb = await inference.embedText(tokens);
      final textStats = _computeStats(rawTextEmb);

      print('\nRaw TEXT embedding (before normalization):');
      print('  Mean: ${textStats.mean.toStringAsFixed(6)}');
      print('  Std:  ${textStats.std.toStringAsFixed(6)}');
      print('  Min:  ${textStats.min.toStringAsFixed(6)}');
      print('  Max:  ${textStats.max.toStringAsFixed(6)}');
      print('  L2 Norm: ${_l2Norm(rawTextEmb).toStringAsFixed(6)}');

      // Get raw image embedding
      final testImage = ImagePreprocessor.createTestImage();
      final rawImageEmb = await inference.embedImage(testImage);
      final imageStats = _computeStats(rawImageEmb);

      print('\nRaw IMAGE embedding (before normalization):');
      print('  Mean: ${imageStats.mean.toStringAsFixed(6)}');
      print('  Std:  ${imageStats.std.toStringAsFixed(6)}');
      print('  Min:  ${imageStats.min.toStringAsFixed(6)}');
      print('  Max:  ${imageStats.max.toStringAsFixed(6)}');
      print('  L2 Norm: ${_l2Norm(rawImageEmb).toStringAsFixed(6)}');

      print('\n📋 DIAGNOSIS:');
      final textNorm = _l2Norm(rawTextEmb);
      final imageNorm = _l2Norm(rawImageEmb);
      
      if ((textNorm - imageNorm).abs() > 5.0) {
        print('  ⚠️ WARNING: Large norm difference between modalities');
        print('     Text norm: ${textNorm.toStringAsFixed(2)}, Image norm: ${imageNorm.toStringAsFixed(2)}');
        print('     This could affect cross-modal similarity calculations');
      } else {
        print('  ✅ Embedding norms are in similar ranges');
      }

      if (textStats.max.abs() > 10 || imageStats.max.abs() > 10) {
        print('  ⚠️ NOTE: Large activation values detected');
        print('     INT8 quantization with large values can cause clipping');
      }
    });
  });

  group('📊 FINAL DIAGNOSIS', () {
    test('Summary and recommendations', () {
      print('\n' + '=' * 70);
      print('                    FINAL DIAGNOSIS GUIDE');
      print('=' * 70);

      print('''
      
Based on the test results above, here's how to interpret the findings:

┌─────────────────────────────────────────────────────────────────────┐
│ SYMPTOM                          │ LIKELY CAUSE                     │
├─────────────────────────────────────────────────────────────────────┤
│ All text similarities > 0.8      │ INT8 quantization collapsed      │
│                                  │ the embedding space              │
├─────────────────────────────────────────────────────────────────────┤
│ Cross-modal alignment ≈ 0        │ Models from different training   │
│                                  │ OR projection layer missing      │
├─────────────────────────────────────────────────────────────────────┤
│ Good text discrimination BUT     │ Image encoder quantization issue │
│ bad cross-modal alignment        │ (text encoder OK)                │
├─────────────────────────────────────────────────────────────────────┤
│ Everything looks reasonable      │ Model is working correctly       │
│ (intra > 0.5, inter < 0.4,      │                                  │
│  alignment gap > 0.1)           │                                  │
├─────────────────────────────────────────────────────────────────────┤
│ Very low variance in embeddings  │ Quantization caused collapse     │
│                                  │ OR model training issue          │
└─────────────────────────────────────────────────────────────────────┘

RECOMMENDED ACTIONS:

1. If discrimination is poor (intra-inter gap < 0.05):
   → Try FP16 or FP32 model versions to compare
   → Re-quantize with better calibration dataset

2. If cross-modal alignment is broken:
   → Verify both encoders are from same checkpoint
   → Check if there's a missing projection head
   → Test with original non-quantized models

3. If quantization artifacts detected:
   → Use dynamic quantization instead of static
   → Try INT8 with higher precision accumulation
   → Consider quantization-aware training

''');
    });
  });
}

// =============================================================================
// Helper Functions
// =============================================================================

Future<bool> _filesExist(List<String> paths) async {
  for (final path in paths) {
    if (!await File(path).exists()) {
      print('⚠️ File not found: $path');
      return false;
    }
  }
  return true;
}

class _Stats {
  final double mean;
  final double std;
  final double min;
  final double max;
  _Stats(this.mean, this.std, this.min, this.max);
}

_Stats _computeStats(Float32List values) {
  if (values.isEmpty) return _Stats(0, 0, 0, 0);
  
  double sum = 0;
  double minVal = values[0];
  double maxVal = values[0];
  
  for (final v in values) {
    sum += v;
    if (v < minVal) minVal = v;
    if (v > maxVal) maxVal = v;
  }
  
  final mean = sum / values.length;
  
  double variance = 0;
  for (final v in values) {
    variance += (v - mean) * (v - mean);
  }
  variance /= values.length;
  
  return _Stats(mean, math.sqrt(variance), minVal, maxVal);
}

_Stats _computeStatsFromDoubles(List<double> values) {
  if (values.isEmpty) return _Stats(0, 0, 0, 0);
  
  double sum = 0;
  double minVal = values[0];
  double maxVal = values[0];
  
  for (final v in values) {
    sum += v;
    if (v < minVal) minVal = v;
    if (v > maxVal) maxVal = v;
  }
  
  final mean = sum / values.length;
  
  double variance = 0;
  for (final v in values) {
    variance += (v - mean) * (v - mean);
  }
  variance /= values.length;
  
  return _Stats(mean, math.sqrt(variance), minVal, maxVal);
}

double _l2Norm(Float32List values) {
  double sum = 0;
  for (final v in values) {
    sum += v * v;
  }
  return math.sqrt(sum);
}

/// Create a solid color test image in NCHW format [1, 3, 224, 224]
/// RGB values should be 0.0-1.0, will be normalized to [-1, 1]
Float32List _createSolidColorImage(double r, double g, double b) {
  const size = 224;
  const channels = 3;
  
  // Normalize to [-1, 1] using mean=0.5, std=0.5
  final rNorm = (r - 0.5) / 0.5;
  final gNorm = (g - 0.5) / 0.5;
  final bNorm = (b - 0.5) / 0.5;
  
  final data = Float32List(1 * channels * size * size);
  
  // NCHW format: [batch, channel, height, width]
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      data[0 * size * size + y * size + x] = rNorm; // R channel
      data[1 * size * size + y * size + x] = gNorm; // G channel  
      data[2 * size * size + y * size + x] = bNorm; // B channel
    }
  }
  
  return data;
}
