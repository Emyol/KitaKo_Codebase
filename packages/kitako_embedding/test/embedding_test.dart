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

  group('SiglipTokenizer (GemmaTokenizer)', () {
    // Note: This test requires the tokenizer.json file
    // Expected values from Kaggle GemmaTokenizerFast test:
    // - "red" → [854, 1] (token + EOS)
    // - "blue" → [8796, 1]
    // - "a photo of a cat" → [235250, 2686, 576, 476, 4401, 1]
    // - pad_token_id: 0, eos_token_id: 1, bos_token_id: 2

    late SiglipTokenizer tokenizer;
    bool tokenizerLoaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        // Update this path to your actual tokenizer.json location
        await tokenizer.loadFromFile(
          'C:\\Users\\ricba\\Documents\\CS\\DEVWORK\\KitaKo_Codebase\\apps\\kitako_app\\assets\\tokenizer\\tokenizer.json',
        );
        tokenizerLoaded = true;
      } catch (e) {
        print('Tokenizer not loaded: $e');
      }
    });

    test('tokenizer loads successfully', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      expect(tokenizer.isLoaded, true);
      expect(tokenizer.vocabSize, greaterThan(200000)); // Gemma has 256k vocab
    });

    test('special token IDs match GemmaTokenizer', () {
      expect(SiglipTokenizer.padTokenId, 0);
      expect(SiglipTokenizer.eosTokenId, 1);
      expect(SiglipTokenizer.bosTokenId, 2);
      expect(SiglipTokenizer.unkTokenId, 3);
    });

    test('encode produces correct length with padding', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('red');
      expect(tokens.length, SiglipTokenizer.maxLength); // Should be 32
      expect(tokens, isA<List<int>>());
    });

    test('encodeRaw produces tokens without padding', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encodeRaw('red');
      // Should be just the token + EOS, no padding
      expect(tokens.length, lessThan(SiglipTokenizer.maxLength));
      expect(tokens.last, SiglipTokenizer.eosTokenId); // Ends with EOS
    });

    test('encode "red" matches expected tokens', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('red');
      // Expected from Kaggle: [854, 1, 0, 0, ...]
      // First token should be 854 (▁red)
      print('Encoded "red": ${tokens.take(8).toList()}');
      expect(tokens[0], 854); // ▁red token
      expect(tokens[1], SiglipTokenizer.eosTokenId); // EOS
      expect(tokens[2], SiglipTokenizer.padTokenId); // PAD
    });

    test('encode "blue" matches expected tokens', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('blue');
      // Expected from Kaggle: [8796, 1, 0, 0, ...]
      print('Encoded "blue": ${tokens.take(8).toList()}');
      expect(tokens[0], 8796); // ▁blue token
      expect(tokens[1], SiglipTokenizer.eosTokenId); // EOS
    });

    test('encode "a photo of a cat" matches expected tokens', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('a photo of a cat');
      // Expected from Kaggle: [235250, 2686, 576, 476, 4401, 1, 0, ...]
      print('Encoded "a photo of a cat": ${tokens.take(10).toList()}');
      expect(tokens[0], 235250); // ▁a
      expect(tokens[1], 2686);   // ▁photo
      expect(tokens[2], 576);    // ▁of
      expect(tokens[3], 476);    // ▁a
      expect(tokens[4], 4401);   // ▁cat
      expect(tokens[5], SiglipTokenizer.eosTokenId); // EOS
    });

    test('getAttentionMask returns correct mask', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('red');
      final mask = tokenizer.getAttentionMask(tokens);

      expect(mask.length, tokens.length);
      // First 2 tokens (token + EOS) should have mask 1
      expect(mask[0], 1);
      expect(mask[1], 1);
      // Rest should be 0 (padding)
      expect(mask[2], 0);

      // Count non-zero mask values
      final nonZeroCount = mask.where((m) => m == 1).length;
      expect(nonZeroCount, 2); // "red" + EOS = 2 tokens
    });

    test('decode reverses encode', () {
      if (!tokenizerLoaded) {
        print('Skipping: tokenizer not loaded');
        return;
      }
      final original = 'hello world';
      final tokens = tokenizer.encode(original);
      final decoded = tokenizer.decode(tokens);

      print('Original: "$original"');
      print('Decoded: "$decoded"');
      expect(decoded.toLowerCase(), original.toLowerCase());
    });
  });

  group('SiglipInference', () {
    test('embedText throws when model not loaded', () async {
      final inference = SiglipInference();

      expect(
        () async => await inference.embedText([1, 2, 3]),
        throwsA(isA<StateError>()),
      );
    });

    test('embedImage throws when model not loaded', () async {
      final inference = SiglipInference();
      final testImage = ImagePreprocessor.createTestImage();

      expect(
        () async => await inference.embedImage(testImage),
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
