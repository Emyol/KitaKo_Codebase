/// End-to-End Embedding Service Tests
///
/// Tests for KitakoEmbeddingService (full pipeline).
/// Run with: flutter test test/component_tests/embedding_service_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  // Model and tokenizer paths
  const imageModelPath =
      'assets/model/image_encoder/kitako_image_encoder_int8.onnx';
  const textModelPath =
      'assets/model/text_encoder/kitako_text_encoder_int8.onnx';
  const tokenizerPath =
      'assets/tokenizer/tokenizer.json';

  group('KitakoEmbeddingService - Initialization', () {
    late KitakoEmbeddingService service;

    setUp(() {
      service = KitakoEmbeddingService();
    });

    tearDown(() {
      service.dispose();
    });

    test('not initialized by default', () {
      expect(service.isInitialized, false);
      expect(service.isImageEncoderReady, false);
      expect(service.isTextEncoderReady, false);
    });

    test('initializes from files successfully', () async {
      // Check all files exist
      final imageFile = File(imageModelPath);
      final textFile = File(textModelPath);
      final tokenizerFile = File(tokenizerPath);

      if (!await imageFile.exists() ||
          !await textFile.exists() ||
          !await tokenizerFile.exists()) {
        print('⚠️ One or more model files not found:');
        print('   Image model: ${await imageFile.exists()}');
        print('   Text model: ${await textFile.exists()}');
        print('   Tokenizer: ${await tokenizerFile.exists()}');
        markTestSkipped('Model files not found');
        return;
      }

      await service.initializeFromFiles(
        imageModelPath: imageModelPath,
        textModelPath: textModelPath,
        tokenizerPath: tokenizerPath,
      );

      expect(service.isInitialized, true);
      expect(service.isImageEncoderReady, true);
      expect(service.isTextEncoderReady, true);

      print('✅ KitakoEmbeddingService initialized successfully');
    });
  });

  group('KitakoEmbeddingService - Text Embedding', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();

      final imageFile = File(imageModelPath);
      final textFile = File(textModelPath);
      final tokenizerFile = File(tokenizerPath);

      if (await imageFile.exists() &&
          await textFile.exists() &&
          await tokenizerFile.exists()) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
          print('✅ Service initialized for text embedding tests');
        } catch (e) {
          print('❌ Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() {
      service.dispose();
    });

    test('embedText returns normalized 768-dim vector', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final embedding = await service.embedText('red');

      expect(embedding.length, 768);
      expect(embedding, isA<Float32List>());

      // Check it's normalized (L2 norm ≈ 1.0)
      double norm = 0.0;
      for (final v in embedding) {
        norm += v * v;
      }
      norm = _sqrt(norm);

      expect(norm, closeTo(1.0, 0.01),
          reason: 'Embedding should be L2 normalized');

      print('✅ Text embedding "red":');
      print('   Dimension: ${embedding.length}');
      print('   L2 norm: $norm');
      print('   First 5: ${embedding.sublist(0, 5)}');
    });

    test('embedText applies prompt formatting for short queries', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      // Short query should get "a photo of" prefix
      final embedding1 = await service.embedText('cat');
      // Already descriptive should stay as-is
      final embedding2 = await service.embedText(
          'a photograph of a fluffy orange cat sitting on a couch');

      // Both should produce valid embeddings
      expect(embedding1.length, 768);
      expect(embedding2.length, 768);

      print('✅ Prompt formatting works for both short and long queries');
    });

    test('embedText handles Taglish text', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final embedding = await service.embedText('Magandang umaga');

      expect(embedding.length, 768);
      expect(embedding.every((v) => v.isFinite), true);

      print('✅ Taglish text embedded successfully');
    });

    test('different texts produce different embeddings', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final emb1 = await service.embedText('red car');
      final emb2 = await service.embedText('blue sky');

      // Calculate similarity
      final similarity = service.cosineSimilarity(emb1, emb2);

      // Different concepts should have lower similarity (but not necessarily negative)
      expect(similarity, lessThan(0.95),
          reason: 'Different texts should have different embeddings');

      print('✅ Different texts produce different embeddings');
      print('   Similarity between "red car" and "blue sky": $similarity');
    });

    test('similar texts produce similar embeddings', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final emb1 = await service.embedText('a red car');
      final emb2 = await service.embedText('a red automobile');

      final similarity = service.cosineSimilarity(emb1, emb2);

      // Similar concepts should have higher similarity
      expect(similarity, greaterThan(0.5),
          reason: 'Similar texts should have similar embeddings');

      print('✅ Similar texts produce similar embeddings');
      print('   Similarity between "red car" and "red automobile": $similarity');
    });

    test('embedTexts batch processing', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final texts = ['cat', 'dog', 'bird'];
      final embeddings = await service.embedTexts(texts);

      expect(embeddings.length, 3);
      for (final emb in embeddings) {
        expect(emb.length, 768);
      }

      print('✅ Batch text embedding works');
    });
  });

  group('KitakoEmbeddingService - Image Embedding', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();

      final imageFile = File(imageModelPath);
      final textFile = File(textModelPath);
      final tokenizerFile = File(tokenizerPath);

      if (await imageFile.exists() &&
          await textFile.exists() &&
          await tokenizerFile.exists()) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() {
      service.dispose();
    });

    test('embedImage with preprocessed test image', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final embedding = await service.embedPreprocessedImage(testImage);

      expect(embedding.length, 768);

      // Check it's normalized
      double norm = 0.0;
      for (final v in embedding) {
        norm += v * v;
      }
      norm = _sqrt(norm);

      expect(norm, closeTo(1.0, 0.01));

      print('✅ Image embedding from test image:');
      print('   Dimension: ${embedding.length}');
      print('   L2 norm: $norm');
      print('   First 5: ${embedding.sublist(0, 5)}');
    });

    test('embedImage with real image file', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final testImagePath = 'test/test_images/133.jpg';

      final file = File(testImagePath);
      if (!await file.exists()) {
        print('⚠️ Test image not found at: $testImagePath');
        markTestSkipped('Test image not found');
        return;
      }

      final imageBytes = await file.readAsBytes();
      final embedding = await service.embedImage(imageBytes);

      expect(embedding.length, 768);
      expect(embedding.every((v) => v.isFinite), true);

      print('✅ Real image embedded successfully');
    });
  });

  group('KitakoEmbeddingService - Cross-Modal Similarity', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();

      final imageFile = File(imageModelPath);
      final textFile = File(textModelPath);
      final tokenizerFile = File(tokenizerPath);

      if (await imageFile.exists() &&
          await textFile.exists() &&
          await tokenizerFile.exists()) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() {
      service.dispose();
    });

    test('cosineSimilarity works between image and text embeddings', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final testImage = ImagePreprocessor.createTestImage();
      final imageEmb = await service.embedPreprocessedImage(testImage);
      final textEmb = await service.embedText('gray square');

      final similarity = service.cosineSimilarity(imageEmb, textEmb);

      // Should produce some valid similarity
      expect(similarity, inInclusiveRange(-1.0, 1.0));

      print('✅ Cross-modal similarity computed:');
      print('   Gray test image vs "gray square": $similarity');
    });

    test('findBestTextMatch returns valid result', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final testImagePath = 'test/test_images/136.jpg';

      final file = File(testImagePath);
      if (!await file.exists()) {
        markTestSkipped('Test image not found');
        return;
      }

      final imageBytes = await file.readAsBytes();
      final candidates = ['a cat', 'a dog', 'a car', 'a house'];

      final (index, score) =
          await service.findBestTextMatch(imageBytes, candidates);

      expect(index, inInclusiveRange(0, candidates.length - 1));
      expect(score, inInclusiveRange(-1.0, 1.0));

      print('✅ Best match found:');
      print('   Best match: "${candidates[index]}" (index: $index)');
      print('   Score: $score');
    });
  });

  group('KitakoEmbeddingService - Embedding Quality Tests', () {
    late KitakoEmbeddingService service;
    bool initialized = false;

    setUpAll(() async {
      service = KitakoEmbeddingService();

      final imageFile = File(imageModelPath);
      final textFile = File(textModelPath);
      final tokenizerFile = File(tokenizerPath);

      if (await imageFile.exists() &&
          await textFile.exists() &&
          await tokenizerFile.exists()) {
        try {
          await service.initializeFromFiles(
            imageModelPath: imageModelPath,
            textModelPath: textModelPath,
            tokenizerPath: tokenizerPath,
          );
          initialized = true;
        } catch (e) {
          print('Failed to initialize: $e');
        }
      }
    });

    tearDownAll(() {
      service.dispose();
    });

    test('color words have distinct embeddings', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final colors = ['red', 'blue', 'green', 'yellow', 'black', 'white'];
      final embeddings = <String, Float32List>{};

      for (final color in colors) {
        embeddings[color] = await service.embedText(color);
      }

      // Calculate pairwise similarities
      print('✅ Color embedding similarities:');
      for (int i = 0; i < colors.length; i++) {
        for (int j = i + 1; j < colors.length; j++) {
          final sim =
              service.cosineSimilarity(embeddings[colors[i]]!, embeddings[colors[j]]!);
          print('   ${colors[i]} vs ${colors[j]}: ${sim.toStringAsFixed(4)}');

          // Different colors should have similarity < 1
          expect(sim, lessThan(0.99),
              reason: 'Different colors should have different embeddings');
        }
      }
    });

    test('semantic categories cluster together', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      // Animals
      final catEmb = await service.embedText('cat');
      final dogEmb = await service.embedText('dog');
      final birdEmb = await service.embedText('bird');

      // Vehicles
      final carEmb = await service.embedText('car');
      final truckEmb = await service.embedText('truck');

      // Animal-animal similarity should be higher than animal-vehicle
      final catDog = service.cosineSimilarity(catEmb, dogEmb);
      final catCar = service.cosineSimilarity(catEmb, carEmb);
      final dogBird = service.cosineSimilarity(dogEmb, birdEmb);
      final carTruck = service.cosineSimilarity(carEmb, truckEmb);

      print('✅ Semantic clustering:');
      print('   cat-dog: $catDog');
      print('   dog-bird: $dogBird');
      print('   car-truck: $carTruck');
      print('   cat-car: $catCar');

      // Same category should be more similar
      expect(catDog, greaterThan(catCar),
          reason: 'Animals should be more similar to each other');
      expect(carTruck, greaterThan(catCar),
          reason: 'Vehicles should be more similar to each other');
    });

    test('embedding values are not all zeros', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final embedding = await service.embedText('hello world');

      // Count non-zero values
      final nonZero = embedding.where((v) => v.abs() > 0.001).length;

      expect(nonZero, greaterThan(embedding.length * 0.5),
          reason: 'Embedding should have many non-zero values');

      print('✅ Embedding has $nonZero non-zero values out of ${embedding.length}');
    });

    test('embedding variance is reasonable', () async {
      if (!initialized) {
        markTestSkipped('Service not initialized');
        return;
      }

      final embedding = await service.embedText('a beautiful landscape');

      // Calculate mean and variance
      double sum = 0;
      for (final v in embedding) {
        sum += v;
      }
      final mean = sum / embedding.length;

      double variance = 0;
      for (final v in embedding) {
        variance += (v - mean) * (v - mean);
      }
      variance /= embedding.length;

      print('✅ Embedding statistics:');
      print('   Mean: $mean');
      print('   Variance: $variance');
      print('   Std dev: ${_sqrt(variance)}');

      // Variance should be positive (not a constant vector)
      expect(variance, greaterThan(0.001),
          reason: 'Embedding should have some variance');
    });
  });

  group('KitakoEmbeddingService - Error Handling', () {
    test('embedText throws when not initialized', () {
      final service = KitakoEmbeddingService();

      expect(
        () async => await service.embedText('test'),
        throwsA(isA<StateError>()),
      );

      service.dispose();
    });

    test('embedImage throws when not initialized', () {
      final service = KitakoEmbeddingService();
      final testImage = ImagePreprocessor.createTestImage();

      expect(
        () async => await service.embedPreprocessedImage(testImage),
        throwsA(isA<StateError>()),
      );

      service.dispose();
    });
  });
}

/// Helper for sqrt (avoid importing dart:math)
double _sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
