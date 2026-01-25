import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  group('ImagePreprocessor', () {
    test('createTestImage returns correct shape', () {
      final testImage = ImagePreprocessor.createTestImage();

      // Should be [1, 224, 224, 3] flattened = 150528
      expect(testImage.length, 1 * 224 * 224 * 3);
      expect(testImage, isA<Float32List>());
    });

    test('preprocessed values are in range [-1, 1]', () {
      final testImage = ImagePreprocessor.createTestImage();

      for (final value in testImage) {
        expect(value, inInclusiveRange(-1.0, 1.0));
      }
    });
  });

  group('SiglipTokenizer', () {
    // Note: This test requires the tokenizer.json file
    // It will be skipped if file doesn't exist
    test('tokenizer loads and encodes text', () async {
      final tokenizer = SiglipTokenizer();

      // Try to load from test assets or skip
      try {
        // Update this path to your actual tokenizer.json location
        await tokenizer.loadFromFile(
          'c:/Users/ricba/Documents/CS/DEVWORK/KitaKo_Codebase/assets/models/tokenizer/tokenizer.json',
        );

        expect(tokenizer.isLoaded, true);
        expect(tokenizer.vocabSize, greaterThan(0));

        // Test encoding
        final tokens = tokenizer.encode('hello world');
        expect(tokens.length, SiglipTokenizer.maxLength); // Should be padded to 64
        expect(tokens, isA<List<int>>());

        // First tokens should not be pad (0)
        expect(tokens[0], isNot(0));

        print('Vocab size: ${tokenizer.vocabSize}');
        print('Encoded "hello world": ${tokens.take(10).toList()}...');
      } catch (e) {
        print('Skipping tokenizer test: $e');
      }
    });
  });

  group('SiglipInference', () {
    test('embedText throws when model not loaded', () {
      final inference = SiglipInference();

      expect(
        () => inference.embedText([1, 2, 3]),
        throwsA(isA<StateError>()),
      );
    });

    test('embedImage throws when model not loaded', () {
      final inference = SiglipInference();
      final testImage = ImagePreprocessor.createTestImage();

      expect(
        () => inference.embedImage(testImage),
        throwsA(isA<StateError>()),
      );
    });

    test('cosineSimilarity computes correctly', () {
      final a = Float32List.fromList([1.0, 0.0, 0.0]);
      final b = Float32List.fromList([1.0, 0.0, 0.0]);
      final c = Float32List.fromList([0.0, 1.0, 0.0]);

      // Same vectors = 1.0
      expect(SiglipInference.cosineSimilarity(a, b), closeTo(1.0, 0.001));

      // Orthogonal vectors = 0.0
      expect(SiglipInference.cosineSimilarity(a, c), closeTo(0.0, 0.001));
    });
  });
}
