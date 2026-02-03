import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// SigLIP text tokenizer using HuggingFace tokenizers format.
///
/// This is a BPE (Byte-Pair Encoding) tokenizer compatible with the
/// SigLIP text encoder model.
class SiglipTokenizer {
  late Map<String, int> _vocab;
  late Map<int, String> _reverseVocab;
  late List<List<String>> _merges;
  late Map<String, int> _mergeRanks;

  // Special tokens
  static const int padTokenId = 0;
  static const int eosTokenId = 1;
  static const int bosTokenId = 2;
  static const int unkTokenId = 3;

  static const String padToken = '<pad>';
  static const String eosToken = '<eos>';
  static const String bosToken = '<bos>';
  static const String unkToken = '<unk>';

  // Configuration
  static const int maxLength = 64;
  bool addEosToken = true;
  bool addBosToken = false;

  bool _isLoaded = false;

  /// Whether the tokenizer has been loaded
  bool get isLoaded => _isLoaded;

  /// Loads the tokenizer from a tokenizer.json file (HuggingFace format).
  /// 
  /// [tokenizerJsonPath] can be an asset path (starting with 'assets/') or a file path.
  Future<void> loadFromFile(String tokenizerJsonPath) async {
    String content;
    if (tokenizerJsonPath.startsWith('assets/')) {
      // Load from Flutter assets
      content = await rootBundle.loadString(tokenizerJsonPath);
    } else {
      // Load from file system
      final file = File(tokenizerJsonPath);
      content = await file.readAsString();
    }
    await loadFromJson(content);
  }

  /// Loads the tokenizer from JSON string.
  Future<void> loadFromJson(String jsonContent) async {
    final data = jsonDecode(jsonContent) as Map<String, dynamic>;

    // Load vocabulary from model section
    final model = data['model'] as Map<String, dynamic>;
    final vocabData = model['vocab'];

    _vocab = {};
    _reverseVocab = {};

    // Handle both dict format {'token': id} and list format [['token', score], ...]
    if (vocabData is Map<String, dynamic>) {
      // Dict format (old tokenizers)
      vocabData.forEach((token, id) {
        final tokenId = id as int;
        _vocab[token] = tokenId;
        _reverseVocab[tokenId] = token;
      });
    } else if (vocabData is List) {
      // List format (Xenova/SentencePiece) - index is the token ID
      for (int i = 0; i < vocabData.length; i++) {
        if (vocabData[i] is List && vocabData[i].length >= 1) {
          final token = vocabData[i][0] as String;
          _vocab[token] = i;
          _reverseVocab[i] = token;
        }
      }
    } else {
      throw StateError('Unsupported vocab format: ${vocabData.runtimeType}');
    }

    // Load added tokens (special tokens with potentially different IDs)
    final addedTokens = data['added_tokens'] as List<dynamic>?;
    if (addedTokens != null) {
      for (final token in addedTokens) {
        final content = token['content'] as String;
        final id = token['id'] as int;
        _vocab[content] = id;
        _reverseVocab[id] = content;
      }
    }

    // Load merges - format is array of [token1, token2] pairs (optional for SentencePiece)
    _merges = [];
    _mergeRanks = {};

    if (model.containsKey('merges')) {
      final mergesData = model['merges'] as List<dynamic>;
      for (int i = 0; i < mergesData.length; i++) {
        final merge = mergesData[i];
        if (merge is List && merge.length == 2) {
          final parts = [merge[0].toString(), merge[1].toString()];
          _merges.add(parts);
          _mergeRanks['${parts[0]} ${parts[1]}'] = i;
        } else if (merge is String) {
          // Fallback for space-separated format
          final parts = merge.split(' ');
          if (parts.length == 2) {
            _merges.add(parts);
            _mergeRanks[merge] = i;
          }
        }
      }
    }

    _isLoaded = true;
  }

  /// Tokenizes text into token IDs.
  ///
  /// Returns a list of token IDs, padded/truncated to [maxLength].
  List<int> encode(String text) {
    if (!_isLoaded) {
      throw StateError('Tokenizer not loaded. Call loadFromFile first.');
    }

    // Tokenize
    List<int> tokens = _tokenize(text);

    // Add EOS token if configured
    if (addEosToken && tokens.length < maxLength) {
      tokens.add(eosTokenId);
    }

    // Truncate if too long
    if (tokens.length > maxLength) {
      tokens = tokens.sublist(0, maxLength);
    }

    // Pad to maxLength
    while (tokens.length < maxLength) {
      tokens.add(padTokenId);
    }

    return tokens;
  }

  /// Tokenizes text without padding (raw tokens).
  List<int> encodeRaw(String text) {
    if (!_isLoaded) {
      throw StateError('Tokenizer not loaded. Call loadFromFile first.');
    }

    List<int> tokens = _tokenize(text);

    if (addEosToken) {
      tokens.add(eosTokenId);
    }

    return tokens;
  }

  /// Decodes token IDs back to text.
  String decode(List<int> tokenIds) {
    if (!_isLoaded) {
      throw StateError('Tokenizer not loaded. Call loadFromFile first.');
    }

    final tokens = <String>[];
    for (final id in tokenIds) {
      if (id == padTokenId || id == eosTokenId || id == bosTokenId) {
        continue; // Skip special tokens
      }
      final token = _reverseVocab[id];
      if (token != null && !token.startsWith('<')) {
        tokens.add(token);
      }
    }

    // Join and clean up (SentencePiece uses ▁ for word boundaries)
    return tokens.join('').replaceAll('▁', ' ').trim();
  }

  /// Internal tokenization using Unigram/SentencePiece algorithm.
  ///
  /// For SigLIP, we use a simplified approach that:
  /// 1. Splits text into words
  /// 2. Adds word boundary markers (▁)
  /// 3. Looks up complete words in vocab first
  /// 4. Falls back to character-level tokenization if needed
  List<int> _tokenize(String text) {
    // Normalize text (basic)
    text = text.toLowerCase().trim();

    // Split into words
    final words = text.split(' ');
    final result = <int>[];

    for (final word in words) {
      if (word.isEmpty) continue;

      // Add word boundary marker
      final tokenWithMarker = '▁$word';

      // Try to find the complete word in vocab first
      if (_vocab.containsKey(tokenWithMarker)) {
        result.add(_vocab[tokenWithMarker]!);
      } else {
        // Fall back to subword tokenization
        final subwordIds = _tokenizeSubword(tokenWithMarker);
        result.addAll(subwordIds);
      }
    }

    return result;
  }

  /// Tokenizes a subword using greedy longest-match approach.
  List<int> _tokenizeSubword(String text) {
    final result = <int>[];
    int pos = 0;

    while (pos < text.length) {
      // Try to find the longest matching token starting at pos
      int? bestLen;
      int? bestId;

      for (int len = text.length - pos; len > 0; len--) {
        final substr = text.substring(pos, pos + len);
        if (_vocab.containsKey(substr)) {
          bestLen = len;
          bestId = _vocab[substr]!;
          break;
        }
      }

      if (bestLen != null && bestId != null) {
        result.add(bestId);
        pos += bestLen;
      } else {
        // No match found, use unknown token for this character
        result.add(unkTokenId);
        pos++;
      }
    }

    return result;
  }


  /// Gets the vocabulary size.
  int get vocabSize => _vocab.length;

  /// Checks if a token exists in vocabulary.
  bool hasToken(String token) => _vocab.containsKey(token);

  /// Gets the ID for a token, or unk_token_id if not found.
  int getTokenId(String token) => _vocab[token] ?? unkTokenId;
}
