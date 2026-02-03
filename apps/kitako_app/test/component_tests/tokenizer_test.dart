/// Tokenizer Component Tests
///
/// Tests for SiglipTokenizer (GemmaTokenizer) in isolation.
/// Run with: flutter test test/component_tests/tokenizer_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  group('SiglipTokenizer - Basic Functionality', () {
    late SiglipTokenizer tokenizer;
    bool loaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        // Absolute path to tokenizer.json
        await tokenizer.loadFromFile(
          'assets/tokenizer/tokenizer.json',
        );
        loaded = true;
        print('✅ Tokenizer loaded successfully');
        print('   Vocab size: ${tokenizer.vocabSize}');
      } catch (e) {
        print('❌ Failed to load tokenizer: $e');
      }
    });

    test('loads tokenizer.json successfully', () {
      expect(loaded, true, reason: 'Tokenizer should load from file');
      expect(tokenizer.isLoaded, true);
    });

    test('has correct vocabulary size (Gemma 256k vocab)', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      // Gemma tokenizer has ~256k vocabulary
      expect(tokenizer.vocabSize, greaterThan(250000));
      expect(tokenizer.vocabSize, lessThan(270000));
    });

    test('special token IDs are correct', () {
      expect(SiglipTokenizer.padTokenId, 0);
      expect(SiglipTokenizer.eosTokenId, 1);
      expect(SiglipTokenizer.bosTokenId, 2);
      expect(SiglipTokenizer.unkTokenId, 3);
    });

    test('maxLength is 32', () {
      expect(SiglipTokenizer.maxLength, 32);
    });
  });

  group('SiglipTokenizer - Encoding Tests', () {
    late SiglipTokenizer tokenizer;
    bool loaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        await tokenizer.loadFromFile(
          'assets/tokenizer/tokenizer.json',
        );
        loaded = true;
      } catch (e) {
        print('Tokenizer not loaded: $e');
      }
    });

    test('encode returns correct length (maxLength=32)', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('test');
      expect(tokens.length, 32, reason: 'Should be padded to maxLength');
    });

    test('encode "red" matches expected: [854, 1, 0, ...]', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('red');
      print('Encoded "red": ${tokens.take(8).toList()}');

      expect(tokens[0], 854, reason: '"red" should tokenize to 854');
      expect(tokens[1], 1, reason: 'Should end with EOS token');
      expect(tokens[2], 0, reason: 'Rest should be padding');
    });

    test('encode "blue" matches expected: [8796, 1, 0, ...]', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('blue');
      print('Encoded "blue": ${tokens.take(8).toList()}');

      expect(tokens[0], 8796, reason: '"blue" should tokenize to 8796');
      expect(tokens[1], 1, reason: 'Should end with EOS token');
    });

    test('encode "a photo of a cat" matches expected tokens', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('a photo of a cat');
      print('Encoded "a photo of a cat": ${tokens.take(10).toList()}');

      // Expected: [235250, 2686, 576, 476, 4401, 1, 0, ...]
      expect(tokens[0], 235250, reason: '"a" should tokenize to 235250');
      expect(tokens[1], 2686, reason: '"photo" should tokenize to 2686');
      expect(tokens[2], 576, reason: '"of" should tokenize to 576');
      expect(tokens[3], 476, reason: '"a" should tokenize to 476');
      expect(tokens[4], 4401, reason: '"cat" should tokenize to 4401');
      expect(tokens[5], 1, reason: 'Should end with EOS token');
    });

    test('encodeRaw returns tokens without padding', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final rawTokens = tokenizer.encodeRaw('red');
      final paddedTokens = tokenizer.encode('red');

      print('Raw tokens for "red": $rawTokens');
      print('Padded tokens for "red": ${paddedTokens.take(8).toList()}');

      expect(rawTokens.length, lessThan(32));
      expect(rawTokens.last, 1, reason: 'Should end with EOS');
      expect(rawTokens[0], 854);
    });

    test('handles empty string', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('');
      expect(tokens.length, 32);
      expect(tokens[0], 1, reason: 'Empty string should start with EOS');
    });

    test('handles very long text (truncation)', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final longText = 'word ' * 100;
      final tokens = tokenizer.encode(longText);

      expect(tokens.length, 32, reason: 'Should be truncated to maxLength');
      // When truncating, tokenizer puts EOS (1) at the end
      expect(tokens.last, SiglipTokenizer.eosTokenId, reason: 'Truncated text ends with EOS');
    });

    test('handles special characters and punctuation', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('Hello, World! How are you?');
      print('Tokens for "Hello, World! How are you?": ${tokens.take(15).toList()}');

      expect(tokens.length, 32);
      expect(tokens.where((t) => t != 0).length, greaterThan(3));
    });

    test('handles Filipino/Taglish text', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('Magandang umaga');
      print('Tokens for "Magandang umaga": ${tokens.take(10).toList()}');

      expect(tokens.length, 32);
      // Should tokenize (may use byte fallback for uncommon chars)
      expect(tokens[0], isNot(3), reason: 'Should not be UNK token');
    });
  });

  group('SiglipTokenizer - Attention Mask', () {
    late SiglipTokenizer tokenizer;
    bool loaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        await tokenizer.loadFromFile(
          'assets/tokenizer/tokenizer.json',
        );
        loaded = true;
      } catch (e) {
        print('Tokenizer not loaded: $e');
      }
    });

    test('attention mask has correct shape', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('red');
      final mask = tokenizer.getAttentionMask(tokens);

      expect(mask.length, tokens.length);
      expect(mask.length, 32);
    });

    test('attention mask marks real tokens with 1', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('red');
      final mask = tokenizer.getAttentionMask(tokens);

      // "red" = [854, 1, 0, 0, ...]
      // mask  = [1,   1, 0, 0, ...]
      expect(mask[0], 1, reason: 'Real token should have mask 1');
      expect(mask[1], 1, reason: 'EOS token should have mask 1');
      expect(mask[2], 0, reason: 'Padding should have mask 0');
    });

    test('attention mask has correct count for "a photo of a cat"', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('a photo of a cat');
      final mask = tokenizer.getAttentionMask(tokens);

      // 5 words + EOS = 6 tokens
      final activeTokens = mask.where((m) => m == 1).length;
      expect(activeTokens, 6, reason: '5 words + EOS = 6 active tokens');
    });
  });

  group('SiglipTokenizer - Decode Tests', () {
    late SiglipTokenizer tokenizer;
    bool loaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        await tokenizer.loadFromFile(
          'assets/tokenizer/tokenizer.json',
        );
        loaded = true;
      } catch (e) {
        print('Tokenizer not loaded: $e');
      }
    });

    test('decode reverses encode for simple text', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      const original = 'hello world';
      final tokens = tokenizer.encode(original);
      final decoded = tokenizer.decode(tokens);

      print('Original: "$original"');
      print('Decoded:  "$decoded"');
      expect(decoded.toLowerCase().trim(), original);
    });

    test('decode handles single word', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      const original = 'cat';
      final tokens = tokenizer.encode(original);
      final decoded = tokenizer.decode(tokens);

      print('Original: "$original"');
      print('Decoded:  "$decoded"');
      expect(decoded.toLowerCase().trim(), original);
    });

    test('decode handles SigLIP prompt format', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      const prompt = 'a photo of a dog';
      final tokens = tokenizer.encode(prompt);
      final decoded = tokenizer.decode(tokens);

      print('Prompt:  "$prompt"');
      print('Decoded: "$decoded"');
      expect(decoded.toLowerCase().trim(), prompt);
    });
  });

  group('SiglipTokenizer - Edge Cases', () {
    late SiglipTokenizer tokenizer;
    bool loaded = false;

    setUpAll(() async {
      tokenizer = SiglipTokenizer();
      try {
        await tokenizer.loadFromFile(
          'assets/tokenizer/tokenizer.json',
        );
        loaded = true;
      } catch (e) {
        print('Tokenizer not loaded: $e');
      }
    });

    test('handles numbers', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('123 456');
      print('Tokens for "123 456": ${tokens.take(10).toList()}');

      expect(tokens.length, 32);
      expect(tokens[0], isNot(3), reason: 'Numbers should not be UNK');
    });

    test('handles emoji (byte fallback)', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('cat 🐱');
      print('Tokens for "cat 🐱": ${tokens.take(15).toList()}');

      expect(tokens.length, 32);
      // Emoji might use byte fallback tokens
    });

    test('handles multiple spaces', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      final tokens = tokenizer.encode('hello    world');
      print('Tokens for "hello    world": ${tokens.take(15).toList()}');

      expect(tokens.length, 32);
    });

    test('hasToken checks vocabulary correctly', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      // Common tokens should exist
      expect(tokenizer.hasToken('a'), true);
      expect(tokenizer.hasToken('the'), true);
      // Random string should not exist
      expect(tokenizer.hasToken('qwertyuiop123'), false);
    });

    test('getTokenId returns correct IDs', () {
      if (!loaded) {
        markTestSkipped('Tokenizer not loaded');
        return;
      }
      // Unknown token should return unk_token_id (3)
      expect(tokenizer.getTokenId('xyznonexistent'), 3);
    });
  });
}
