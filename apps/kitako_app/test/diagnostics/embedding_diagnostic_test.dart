/// Quick Embedding Diagnostic Test
/// 
/// This is a standalone test to diagnose embedding problems.
/// Run with: dart test test/diagnostics/embedding_diagnostic_test.dart
/// 
/// Or for more verbose output:
/// flutter test test/diagnostics/embedding_diagnostic_test.dart --reporter expanded
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  // Paths to test files
  const imageModelPath =
      'assets/model/image_encoder/kitako_image_encoder_int8.onnx';
  const textModelPath =
      'assets/model/text_encoder/kitako_text_encoder_int8.onnx';
  const tokenizerPath =
      'assets/tokenizer/tokenizer.json';

  group('🔍 DIAGNOSTIC: Model Files', () {
    test('Check image encoder exists', () async {
      final file = File(imageModelPath);
      final exists = await file.exists();
      print('Image encoder path: $imageModelPath');
      print('Exists: $exists');
      if (exists) {
        final size = await file.length();
        print('Size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
      }
      expect(exists, true, reason: 'Image encoder model must exist');
    });

    test('Check text encoder exists', () async {
      final file = File(textModelPath);
      final exists = await file.exists();
      print('Text encoder path: $textModelPath');
      print('Exists: $exists');
      if (exists) {
        final size = await file.length();
        print('Size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
      }
      expect(exists, true, reason: 'Text encoder model must exist');
    });

    test('Check tokenizer exists', () async {
      final file = File(tokenizerPath);
      final exists = await file.exists();
      print('Tokenizer path: $tokenizerPath');
      print('Exists: $exists');
      if (exists) {
        final size = await file.length();
        print('Size: ${(size / 1024).toStringAsFixed(2)} KB');
      }
      expect(exists, true, reason: 'Tokenizer must exist');
    });
  });

  group('🔍 DIAGNOSTIC: Tokenizer', () {
    late SiglipTokenizer tokenizer;
    bool loaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        await tokenizer.loadFromFile(tokenizerPath);
        loaded = true;
      } catch (e) {
        print('❌ Failed to load tokenizer: $e');
      }
    });

    test('Load tokenizer', () {
      expect(loaded, true, reason: 'Tokenizer should load');
      if (loaded) {
        print('✅ Tokenizer loaded');
        print('   Vocab size: ${tokenizer.vocabSize}');
      }
    });

    test('Tokenize "red"', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }

      final tokens = tokenizer.encode('red');
      print('Input: "red"');
      print('Tokens: ${tokens.take(10).toList()}');
      print('Expected: [854, 1, 0, ...]');

      expect(tokens[0], 854, reason: '"red" should tokenize to 854');
    });

    test('Tokenize "a photo of a cat"', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }

      final tokens = tokenizer.encode('a photo of a cat');
      print('Input: "a photo of a cat"');
      print('Tokens: ${tokens.take(10).toList()}');
      print('Expected: [235250, 2686, 576, 476, 4401, 1, ...]');

      expect(tokens[0], 235250);
      expect(tokens[1], 2686);
      expect(tokens[4], 4401);
    });
  });

  group('🔍 DIAGNOSTIC: ONNX Text Encoder', () {
    late SiglipInference inference;
    late SiglipTokenizer tokenizer;
    bool ready = false;

    setUpAll(() async {
      inference = SiglipInference();
      tokenizer = SiglipTokenizer();

      try {
        await inference.loadTextModelFromFile(textModelPath);
        await tokenizer.loadFromFile(tokenizerPath);
        ready = true;
        print('✅ Text encoder and tokenizer ready');
      } catch (e) {
        print('❌ Failed to load: $e');
      }
    });

    tearDownAll(() {
      inference.dispose();
    });

    test('Load text model', () {
      expect(inference.isTextModelLoaded, true);
    });

    test('Generate embedding for "red"', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final tokens = tokenizer.encode('red');
      print('Tokens for "red": ${tokens.take(10).toList()}');

      final embedding = await inference.embedText(tokens);
      print('Embedding dimension: ${embedding.length}');
      print('First 10 values: ${embedding.sublist(0, 10)}');
      print('Last 10 values: ${embedding.sublist(758)}');

      // Calculate statistics
      final stats = _calcStats(embedding);
      print('Stats: mean=${stats.mean.toStringAsFixed(6)}, '
          'std=${stats.std.toStringAsFixed(6)}, '
          'min=${stats.min.toStringAsFixed(6)}, '
          'max=${stats.max.toStringAsFixed(6)}');

      expect(embedding.length, 768);
      expect(embedding.every((v) => v.isFinite), true, reason: 'All values should be finite');
    });

    test('Compare "red" vs "blue" embeddings', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final tokensRed = tokenizer.encode('red');
      final tokensBlue = tokenizer.encode('blue');

      final embRed = await inference.embedText(tokensRed);
      final embBlue = await inference.embedText(tokensBlue);

      final similarity = SiglipInference.cosineSimilarity(embRed, embBlue);
      print('Similarity "red" vs "blue": $similarity');

      // Red and blue should be somewhat different
      expect(similarity, lessThan(0.99), reason: 'Red and blue should have different embeddings');
    });

    test('Check for degenerate embeddings (all same value)', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final tokens = tokenizer.encode('a photo of a cat');
      final embedding = await inference.embedText(tokens);

      // Check variance - degenerate embedding would have 0 variance
      final stats = _calcStats(embedding);

      print('Embedding variance: ${stats.variance}');
      expect(stats.variance, greaterThan(0.0001),
          reason: 'Embedding should have variance (not degenerate)');
    });
  });

  group('🔍 DIAGNOSTIC: ONNX Image Encoder', () {
    late SiglipInference inference;
    bool ready = false;

    setUpAll(() async {
      inference = SiglipInference();

      try {
        await inference.loadImageModelFromFile(imageModelPath);
        ready = true;
        print('✅ Image encoder ready');
      } catch (e) {
        print('❌ Failed to load: $e');
      }
    });

    tearDownAll(() {
      inference.dispose();
    });

    test('Load image model', () {
      expect(inference.isImageModelLoaded, true);
    });

    test('Generate embedding for gray test image', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      print('Test image size: ${testImage.length}');
      print('Test image first 10: ${testImage.sublist(0, 10)}');

      final embedding = await inference.embedImage(testImage);
      print('Embedding dimension: ${embedding.length}');
      print('First 10 values: ${embedding.sublist(0, 10)}');

      final stats = _calcStats(embedding);
      print('Stats: mean=${stats.mean.toStringAsFixed(6)}, '
          'std=${stats.std.toStringAsFixed(6)}, '
          'min=${stats.min.toStringAsFixed(6)}, '
          'max=${stats.max.toStringAsFixed(6)}');

      expect(embedding.length, 768);
      expect(embedding.every((v) => v.isFinite), true);
    });

    test('Check image embedding variance', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final embedding = await inference.embedImage(testImage);
      final stats = _calcStats(embedding);

      print('Image embedding variance: ${stats.variance}');
      expect(stats.variance, greaterThan(0.0001),
          reason: 'Image embedding should have variance');
    });
  });

  group('🔍 DIAGNOSTIC: Cross-Modal Alignment', () {
    late KitakoEmbeddingService service;
    bool ready = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();

      try {
        await service.initializeFromFiles(
          imageModelPath: imageModelPath,
          textModelPath: textModelPath,
          tokenizerPath: tokenizerPath,
        );
        ready = true;
        print('✅ Full service ready');
      } catch (e) {
        print('❌ Failed to initialize: $e');
      }
    });

    tearDownAll(() {
      service.dispose();
    });

    test('Image-text similarity is in valid range', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final imageEmb = await service.embedPreprocessedImage(testImage);
      final textEmb = await service.embedText('gray');

      final similarity = service.cosineSimilarity(imageEmb, textEmb);
      print('Gray image vs "gray" text: $similarity');

      expect(similarity, inInclusiveRange(-1.0, 1.0));
    });

    test('Text embeddings are distinguishable', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final words = ['cat', 'dog', 'car', 'tree', 'ocean', 'mountain'];
      final embeddings = <Float32List>[];

      for (final word in words) {
        embeddings.add(await service.embedText(word));
      }

      print('\nSimilarity matrix:');
      print('        ${words.map((w) => w.padLeft(8)).join('')}');

      for (int i = 0; i < words.length; i++) {
        final row = StringBuffer('${words[i].padLeft(8)}');
        for (int j = 0; j < words.length; j++) {
          final sim = service.cosineSimilarity(embeddings[i], embeddings[j]);
          row.write(sim.toStringAsFixed(4).padLeft(8));
        }
        print(row);
      }

      // Diagonal should be 1.0 (self-similarity)
      for (int i = 0; i < words.length; i++) {
        final selfSim = service.cosineSimilarity(embeddings[i], embeddings[i]);
        expect(selfSim, closeTo(1.0, 0.001));
      }

      // Off-diagonal should be < 1.0
      for (int i = 0; i < words.length; i++) {
        for (int j = i + 1; j < words.length; j++) {
          final sim = service.cosineSimilarity(embeddings[i], embeddings[j]);
          expect(sim, lessThan(0.99),
              reason: '${words[i]} and ${words[j]} should have different embeddings');
        }
      }
    });

    test('Prompt formatting effect', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      // Compare raw word vs formatted prompt
      final rawEmb = await service.embedText('cat');
      
      // Manually create the formatted version
      final formattedTokenizer = SiglipTokenizer();
      await formattedTokenizer.loadFromFile(tokenizerPath);
      
      print('\nRaw "cat" embedding first 5: ${rawEmb.sublist(0, 5)}');

      // The service should have applied "a photo of" prefix
      // Check if embeddings are reasonable
      expect(rawEmb.length, 768);
      expect(rawEmb.every((v) => v.isFinite), true);
    });
  });

  group('🔍 DIAGNOSTIC: L2 Normalization', () {
    late KitakoEmbeddingService service;
    bool ready = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();

      try {
        await service.initializeFromFiles(
          imageModelPath: imageModelPath,
          textModelPath: textModelPath,
          tokenizerPath: tokenizerPath,
        );
        ready = true;
      } catch (e) {
        print('Failed to initialize: $e');
      }
    });

    tearDownAll(() {
      service.dispose();
    });

    test('Text embeddings are L2 normalized', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final words = ['hello', 'world', 'test', 'embedding'];

      for (final word in words) {
        final emb = await service.embedText(word);
        final norm = _l2Norm(emb);
        print('"$word" L2 norm: $norm');
        expect(norm, closeTo(1.0, 0.01), reason: '"$word" should be L2 normalized');
      }
    });

    test('Image embeddings are L2 normalized', () async {
      if (!ready) {
        markTestSkipped('Not ready');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final emb = await service.embedPreprocessedImage(testImage);
      final norm = _l2Norm(emb);

      print('Image embedding L2 norm: $norm');
      expect(norm, closeTo(1.0, 0.01));
    });
  });
}

/// Calculate L2 norm
double _l2Norm(Float32List v) {
  double sum = 0;
  for (final x in v) {
    sum += x * x;
  }
  return _sqrt(sum);
}

/// Calculate statistics
({double mean, double std, double variance, double min, double max}) _calcStats(
    Float32List v) {
  double sum = 0;
  double min = double.infinity;
  double max = double.negativeInfinity;

  for (final x in v) {
    sum += x;
    if (x < min) min = x;
    if (x > max) max = x;
  }

  final mean = sum / v.length;

  double variance = 0;
  for (final x in v) {
    variance += (x - mean) * (x - mean);
  }
  variance /= v.length;

  return (
    mean: mean,
    std: _sqrt(variance),
    variance: variance,
    min: min,
    max: max,
  );
}

double _sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
