/// SigLIP2 Model Verification Test
///
/// Tests specific to SigLIP2 architecture to identify export/conversion issues.
/// SigLIP2 differs from SigLIP in several ways:
///   - Uses Gemma tokenizer (256k vocab)
///   - Different attention mechanisms
///   - Different pooling strategy (may use mean pooling instead of CLS)
///
/// Run with: flutter test test/diagnostics/siglip2_verification_test.dart --reporter expanded
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  const imageModelPath = 'assets/model/image_encoder/kitako_image_encoder_fp32.onnx';
  const textModelPath = 'assets/model/text_encoder/kitako_text_encoder_fp32.onnx';
  const tokenizerPath = 'assets/tokenizer/tokenizer.json';

  group('🔬 SigLIP2: Tokenizer Verification', () {
    late SiglipTokenizer tokenizer;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      if (await File(tokenizerPath).exists()) {
        await tokenizer.loadFromFile(tokenizerPath);
      }
    });

    test('Verify Gemma tokenizer special tokens', () {
      if (!tokenizer.isLoaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }

      print('\n' + '=' * 60);
      print('     SigLIP2 TOKENIZER VERIFICATION');
      print('=' * 60);

      // Gemma tokenizer special tokens
      print('\nExpected Gemma special tokens:');
      print('  PAD: 0, EOS: 1, BOS: 2, UNK: 3');
      print('\nYour tokenizer config:');
      print('  padTokenId: ${SiglipTokenizer.padTokenId}');
      print('  eosTokenId: ${SiglipTokenizer.eosTokenId}');
      print('  bosTokenId: ${SiglipTokenizer.bosTokenId}');
      print('  unkTokenId: ${SiglipTokenizer.unkTokenId}');
      print('  addEosToken: ${tokenizer.addEosToken}');
      print('  addBosToken: ${tokenizer.addBosToken}');

      expect(SiglipTokenizer.padTokenId, 0);
      expect(SiglipTokenizer.eosTokenId, 1);
    });

    test('Verify tokenization output format', () {
      if (!tokenizer.isLoaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }

      print('\n📊 Tokenization samples:');
      
      final samples = [
        'cat',
        'a photo of a cat',
        'hello world',
        '',  // Empty string
      ];

      for (final text in samples) {
        final tokens = tokenizer.encode(text);
        print('\n  "$text":');
        print('    Tokens: $tokens');
        print('    Length: ${tokens.length}');
        
        // Check for EOS token
        final hasEos = tokens.contains(SiglipTokenizer.eosTokenId);
        print('    Has EOS (1): $hasEos');
        
        // Check padding pattern
        final paddingStart = tokens.indexOf(0);
        if (paddingStart > 0) {
          print('    Padding starts at: $paddingStart');
        }
      }

      // Verify max length
      final longTokens = tokenizer.encode('a very long sentence that should be truncated at some point');
      expect(longTokens.length, 64, reason: 'Should be padded/truncated to 64');
      print('\n✅ Token length is correctly 64');
    });

    test('Compare with expected SigLIP2 token patterns', () {
      if (!tokenizer.isLoaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }

      print('\n📊 SigLIP2 Token ID Verification:');
      print('   (Comparing against known Gemma tokenizer patterns)');

      // Known token mappings for Gemma tokenizer
      // These are approximate - exact values depend on tokenizer version
      final knownPatterns = {
        'cat': [4401],        // "cat" as single token
        'dog': [5929],        // "dog" as single token  
        'photo': [2686],      // "photo" 
        'a': [235250],        // "a" with space prefix
      };

      for (final entry in knownPatterns.entries) {
        final tokens = tokenizer.encode(entry.key);
        // Find the main token (not padding or EOS)
        final mainTokens = tokens.where((t) => t != 0 && t != 1).toList();
        print('  "${entry.key}": $mainTokens');
        print('    Expected to contain: ${entry.value}');
        
        // Check if expected token is in the output
        final found = entry.value.any((expected) => mainTokens.contains(expected));
        print('    Match: ${found ? "✅" : "⚠️ Different (may be OK if tokenizer version differs)"}');
      }
    });
  });

  group('🔬 SigLIP2: Attention Mask Verification', () {
    late SiglipInference inference;
    late SiglipTokenizer tokenizer;
    bool initialized = false;

    setUpAll(() async {
      if (await File(textModelPath).exists() && await File(tokenizerPath).exists()) {
        inference = SiglipInference();
        await inference.loadTextModelFromFile(textModelPath);
        
        tokenizer = SiglipTokenizer();
        await tokenizer.loadFromFile(tokenizerPath);
        
        initialized = true;
      }
    });

    tearDownAll(() {
      if (initialized) inference.dispose();
    });

    test('Attention mask affects output correctly', () async {
      if (!initialized) {
        markTestSkipped('Not initialized');
        return;
      }

      print('\n' + '=' * 60);
      print('     ATTENTION MASK VERIFICATION');
      print('=' * 60);

      // The attention mask should make the model focus only on real tokens
      // If attention mask is ignored, padding would affect the embedding
      
      final shortText = 'cat';  // Will have lots of padding
      final tokens = tokenizer.encode(shortText);
      
      print('\nTokens for "$shortText": $tokens');
      print('Real tokens (before padding): ${tokens.where((t) => t != 0).toList()}');
      
      // Count real tokens vs padding
      final realCount = tokens.where((t) => t != 0).length;
      final padCount = tokens.where((t) => t == 0).length;
      print('\nReal tokens: $realCount, Padding: $padCount');
      
      // Get embedding
      final emb = await inference.embedText(tokens);
      print('Embedding L2 norm: ${_l2Norm(emb).toStringAsFixed(4)}');
      
      // A properly working attention mask should mean:
      // 1. The embedding depends only on real tokens
      // 2. Different amounts of padding shouldn't drastically change the embedding
      
      print('\n📋 Note: If attention_mask is NOT being used correctly,');
      print('   embeddings would be dominated by padding patterns');
    });
  });

  group('🔬 SigLIP2: Mean Pooling vs CLS Token', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();
      if (await File(imageModelPath).exists() &&
          await File(textModelPath).exists() &&
          await File(tokenizerPath).exists()) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('❌ Init failed: $e');
        }
      }
    });

    tearDownAll(() => service.dispose());

    test('Check if pooling method affects embeddings', () async {
      if (!initialized) {
        markTestSkipped('Not initialized');
        return;
      }

      print('\n' + '=' * 60);
      print('     POOLING METHOD ANALYSIS');
      print('=' * 60);

      print('\n⚠️ SigLIP2 may use different pooling than SigLIP:');
      print('   - SigLIP: CLS token pooling');
      print('   - SigLIP2: May use mean pooling or attention pooling');
      print('\n   If your export used wrong pooling, embeddings will be degraded.');

      // Test embedding variance - mean pooling tends to produce
      // embeddings with different statistical properties than CLS
      final testTexts = ['cat', 'dog', 'car', 'tree', 'sky', 'water'];
      
      final embeddings = <Float32List>[];
      for (final text in testTexts) {
        embeddings.add(await service.embedText(text));
      }

      // Compute statistics across all embeddings
      final allMeans = <double>[];
      final allStds = <double>[];
      
      for (final emb in embeddings) {
        final stats = _computeStats(emb);
        allMeans.add(stats.mean);
        allStds.add(stats.std);
      }

      final avgMean = allMeans.reduce((a, b) => a + b) / allMeans.length;
      final avgStd = allStds.reduce((a, b) => a + b) / allStds.length;

      print('\n📊 Embedding statistics:');
      print('   Avg embedding mean: ${avgMean.toStringAsFixed(6)}');
      print('   Avg embedding std:  ${avgStd.toStringAsFixed(6)}');
      
      print('\n📋 Expected for healthy SigLIP2:');
      print('   Mean: close to 0 (±0.01)');
      print('   Std:  ~0.03-0.05 for normalized embeddings');
      
      if (avgStd < 0.02) {
        print('\n⚠️ WARNING: Very low std may indicate collapsed pooling');
      }
    });
  });

  group('🔬 SigLIP2: Cross-Modal Space Alignment', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();
      if (await File(imageModelPath).exists() &&
          await File(textModelPath).exists() &&
          await File(tokenizerPath).exists()) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('❌ Init failed: $e');
        }
      }
    });

    tearDownAll(() => service.dispose());

    test('SigLIP2 specific alignment check', () async {
      if (!initialized) {
        markTestSkipped('Not initialized');
        return;
      }

      print('\n' + '=' * 60);
      print('     SigLIP2 CROSS-MODAL ALIGNMENT CHECK');
      print('=' * 60);

      print('\n⚠️ IMPORTANT: SigLIP2 was trained with sigmoid loss, not softmax.');
      print('   This means similarity scores behave differently:');
      print('   - No competition between text candidates');
      print('   - Scores are independent per image-text pair');
      print('   - Raw cosine similarity may be lower than SigLIP1');

      // Test with colored images
      final colors = {
        'red': [1.0, 0.0, 0.0],
        'green': [0.0, 1.0, 0.0],
        'blue': [0.0, 0.0, 1.0],
      };

      print('\n📊 Image-Text alignment for solid colors:');
      
      for (final imgColor in colors.keys) {
        final rgb = colors[imgColor]!;
        final imageData = _createSolidColorImage(rgb[0], rgb[1], rgb[2]);
        final imageEmb = await service.embedPreprocessedImage(imageData);
        
        print('\n  $imgColor image vs texts:');
        for (final txtColor in colors.keys) {
          final textEmb = await service.embedText(txtColor);
          final sim = service.cosineSimilarity(imageEmb, textEmb);
          final marker = imgColor == txtColor ? '← SHOULD BE HIGHEST' : '';
          print('    vs "$txtColor": ${sim.toStringAsFixed(4)} $marker');
        }
      }

      print('\n📋 Diagnosis:');
      print('   If matching pairs are NOT highest → cross-modal alignment is broken');
      print('   If ALL similarities are similar → embeddings are in different spaces');
    });

    test('Compare raw embedding spaces', () async {
      if (!initialized) {
        markTestSkipped('Not initialized');
        return;
      }

      print('\n' + '=' * 60);
      print('     RAW EMBEDDING SPACE COMPARISON');
      print('=' * 60);

      // Get a text and image embedding
      final textEmb = await service.embedText('red');
      final imageEmb = await service.embedPreprocessedImage(
        _createSolidColorImage(1.0, 0.0, 0.0)
      );

      // Compare their statistical properties
      final textStats = _computeStats(textEmb);
      final imageStats = _computeStats(imageEmb);

      print('\n📊 Text embedding "red":');
      print('   Mean: ${textStats.mean.toStringAsFixed(6)}');
      print('   Std:  ${textStats.std.toStringAsFixed(6)}');
      print('   Min:  ${textStats.min.toStringAsFixed(6)}');
      print('   Max:  ${textStats.max.toStringAsFixed(6)}');

      print('\n📊 Red image embedding:');
      print('   Mean: ${imageStats.mean.toStringAsFixed(6)}');
      print('   Std:  ${imageStats.std.toStringAsFixed(6)}');
      print('   Min:  ${imageStats.min.toStringAsFixed(6)}');
      print('   Max:  ${imageStats.max.toStringAsFixed(6)}');

      // If embeddings are in different spaces, their statistical properties
      // will be very different
      final meanDiff = (textStats.mean - imageStats.mean).abs();
      final stdDiff = (textStats.std - imageStats.std).abs();

      print('\n📋 Space alignment indicators:');
      print('   Mean difference: ${meanDiff.toStringAsFixed(6)} ${meanDiff > 0.1 ? "⚠️ DIFFERENT SPACES?" : "✅"}');
      print('   Std difference:  ${stdDiff.toStringAsFixed(6)} ${stdDiff > 0.02 ? "⚠️ DIFFERENT SCALES?" : "✅"}');

      // Check if embeddings look like they're from the same distribution
      if (meanDiff > 0.1 || stdDiff > 0.02) {
        print('\n❌ Embeddings may be from different embedding spaces!');
        print('   This suggests the encoders were NOT trained together or');
        print('   there is a missing projection/normalization layer.');
      }
    });
  });

  group('🔬 SigLIP2: Detailed Diagnosis', () {
    test('Summary and SigLIP2-specific recommendations', () {
      print('\n' + '=' * 70);
      print('              SigLIP2 CONVERSION TROUBLESHOOTING GUIDE');
      print('=' * 70);

      print('''

┌────────────────────────────────────────────────────────────────────────┐
│                     SigLIP2 vs SigLIP1 DIFFERENCES                     │
├────────────────────────────────────────────────────────────────────────┤
│ Feature          │ SigLIP1            │ SigLIP2                        │
├────────────────────────────────────────────────────────────────────────┤
│ Tokenizer        │ SentencePiece      │ Gemma (256k vocab)             │
│ Text pooling     │ CLS token          │ Mean pooling or attention      │
│ Loss function    │ Softmax NCE        │ Sigmoid (pairwise)             │
│ Image encoder    │ ViT standard       │ ViT with modifications         │
│ Projection       │ Linear             │ May have MLP head              │
└────────────────────────────────────────────────────────────────────────┘

COMMON SigLIP2 EXPORT ISSUES:

1. ❌ WRONG POOLING METHOD
   SigLIP2 often uses MEAN pooling over all tokens, not CLS token.
   
   Fix: Check your export code:
   
   # ❌ WRONG for SigLIP2:
   pooled = text_outputs.last_hidden_state[:, 0, :]  # CLS token
   
   # ✅ CORRECT for SigLIP2 (check model config):
   pooled = text_outputs.last_hidden_state.mean(dim=1)  # Mean pooling
   # OR use the model's built-in method:
   pooled = model.get_text_features(input_ids, attention_mask)

2. ❌ MISSING ATTENTION MASK IN MEAN POOLING
   If using mean pooling, you MUST mask out padding:
   
   # ✅ CORRECT mean pooling with mask:
   hidden_states = text_outputs.last_hidden_state
   attention_mask_expanded = attention_mask.unsqueeze(-1).expand(hidden_states.size())
   sum_embeddings = (hidden_states * attention_mask_expanded).sum(dim=1)
   sum_mask = attention_mask_expanded.sum(dim=1).clamp(min=1e-9)
   pooled = sum_embeddings / sum_mask

3. ❌ MISSING HEAD/PROJECTION LAYER
   SigLIP2 has projection layers that MUST be included:
   
   # Check if your model has these:
   print(model.text_projection)   # Should NOT be None
   print(model.visual_projection) # Should NOT be None

4. ❌ DIFFERENT NORMALIZATION
   SigLIP2 may normalize differently:
   
   # After projection, normalize:
   embeddings = embeddings / embeddings.norm(dim=-1, keepdim=True)

5. ❌ TOKENIZER MISMATCH
   Gemma tokenizer has specific requirements:
   - Vocab size: 256000
   - Special tokens: PAD=0, EOS=1, BOS=2, UNK=3
   - May or may not need BOS token (check model config)
   
''');
    });
  });
}

// =============================================================================
// Helper Functions
// =============================================================================

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

double _l2Norm(Float32List values) {
  double sum = 0;
  for (final v in values) {
    sum += v * v;
  }
  return math.sqrt(sum);
}

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
