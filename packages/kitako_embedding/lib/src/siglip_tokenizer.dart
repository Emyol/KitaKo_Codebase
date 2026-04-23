import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// GemmaTokenizer - BPE tokenizer compatible with HuggingFace GemmaTokenizerFast.
///
/// This tokenizer is used for the SigLIP2 text encoder which uses a Gemma-style
/// tokenizer with 256k vocabulary and byte fallback support.
class SiglipTokenizer {
  late Map<String, int> _vocab;
  late Map<int, String> _reverseVocab;
  late List<List<String>> _merges;
  late Map<String, int> _mergeRanks;

  // Special tokens (GemmaTokenizer defaults)
  static const int padTokenId = 0;
  static const int eosTokenId = 1;
  static const int bosTokenId = 2;
  static const int unkTokenId = 3;

  static const String padToken = '<pad>';
  static const String eosToken = '<eos>';
  static const String bosToken = '<bos>';
  static const String unkToken = '<unk>';

  // Configuration matching ONNX model expectations
  static const int maxLength = 64;
  bool addEosToken = true;
  bool addBosToken = false;

  // Byte fallback support
  bool _byteFallback = true;
  late Map<int, String> _byteToToken;

  bool _isLoaded = false;

  /// Whether the tokenizer has been loaded
  bool get isLoaded => _isLoaded;

  /// Loads the tokenizer from a Flutter asset (HuggingFace format).
  ///
  /// [assetPath] should be the asset path like 'assets/tokenizer/tokenizer.json'
  Future<void> loadFromAsset(String assetPath) async {
    final content = await rootBundle.loadString(assetPath);
    await loadFromJson(content);
  }

  /// Loads the tokenizer from a tokenizer.json file (HuggingFace format).
  Future<void> loadFromFile(String tokenizerJsonPath) async {
    final file = File(tokenizerJsonPath);
    final content = await file.readAsString();
    await loadFromJson(content);
  }

  /// Loads the tokenizer from JSON string.
  Future<void> loadFromJson(String jsonContent) async {
    final data = jsonDecode(jsonContent) as Map<String, dynamic>;

    // Load vocabulary from model section
    final model = data['model'] as Map<String, dynamic>;
    final vocabData = model['vocab'] as Map<String, dynamic>;

    _vocab = {};
    _reverseVocab = {};
    vocabData.forEach((token, id) {
      final tokenId = id as int;
      _vocab[token] = tokenId;
      _reverseVocab[tokenId] = token;
    });

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

    // Check for byte_fallback setting
    _byteFallback = model['byte_fallback'] as bool? ?? true;

    // Build byte-to-token mapping for byte fallback
    _byteToToken = {};
    if (_byteFallback) {
      // GemmaTokenizer uses <0xXX> format for byte tokens
      for (int b = 0; b < 256; b++) {
        final byteToken = '<0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}>';
        if (_vocab.containsKey(byteToken)) {
          _byteToToken[b] = byteToken;
        }
      }
    }

    // Load merges - format can be array of [token1, token2] pairs or space-separated strings
    final mergesData = model['merges'] as List<dynamic>;
    _merges = [];
    _mergeRanks = {};
    for (int i = 0; i < mergesData.length; i++) {
      final merge = mergesData[i];
      if (merge is List && merge.length == 2) {
        final parts = [merge[0].toString(), merge[1].toString()];
        _merges.add(parts);
        _mergeRanks['${parts[0]} ${parts[1]}'] = i;
      } else if (merge is String) {
        // Space-separated format
        final parts = merge.split(' ');
        if (parts.length >= 2) {
          // Handle cases where tokens themselves contain spaces
          final first = parts[0];
          final rest = parts.sublist(1).join(' ');
          _merges.add([first, rest]);
          _mergeRanks['$first $rest'] = i;
        }
      }
    }

    _isLoaded = true;
  }

  /// Tokenizes text into token IDs.
  ///
  /// Returns a list of token IDs, padded/truncated to [maxLength].
  /// Matches HuggingFace GemmaTokenizerFast behavior.
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

    // Truncate if too long (leave room for EOS if needed)
    if (tokens.length > maxLength) {
      tokens = tokens.sublist(0, maxLength);
      // Ensure EOS is at the end if addEosToken is true
      if (addEosToken) {
        tokens[maxLength - 1] = eosTokenId;
      }
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

  /// Generates attention mask for the given tokens.
  /// 1 for real tokens, 0 for padding.
  List<int> getAttentionMask(List<int> tokens) {
    return tokens.map((t) => t == padTokenId ? 0 : 1).toList();
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

    // Join and clean up (GemmaTokenizer uses ▁ for word boundaries)
    return tokens.join('').replaceAll('▁', ' ').trim();
  }

  /// Internal tokenization using BPE with GemmaTokenizer-style preprocessing.
  List<int> _tokenize(String text) {
    // GemmaTokenizer normalizer: replace space with ▁ (U+2581)
    // IMPORTANT: Do NOT add ▁ at the beginning - only replace internal spaces
    // This matches HuggingFace GemmaTokenizerFast behavior:
    // - "red" → "red" (no ▁, first word)
    // - "a photo" → "a▁photo" (▁ only where space was)
    String normalized = text.replaceAll(' ', '▁');

    // Convert to initial tokens (characters or byte fallback)
    List<String> tokens = _initializeTokens(normalized);

    // Apply BPE merges
    tokens = _applyBpe(tokens);

    // Convert to IDs
    return tokens.map((token) {
      return _vocab[token] ?? unkTokenId;
    }).toList();
  }

  /// Initialize tokens from text, using byte fallback for unknown characters.
  List<String> _initializeTokens(String text) {
    final tokens = <String>[];

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      // Check if the character exists in vocab
      if (_vocab.containsKey(char)) {
        tokens.add(char);
      } else if (_byteFallback) {
        // Use byte fallback - encode character as UTF-8 bytes
        final bytes = utf8.encode(char);
        for (final byte in bytes) {
          final byteToken = _byteToToken[byte];
          if (byteToken != null) {
            tokens.add(byteToken);
          } else {
            // Fallback to unknown token if byte token not found
            tokens.add(unkToken);
          }
        }
      } else {
        // No byte fallback, use unknown token
        tokens.add(unkToken);
      }
    }

    return tokens;
  }

  /// Applies BPE merges to a list of tokens.
  List<String> _applyBpe(List<String> tokens) {
    if (tokens.length < 2) return tokens;

    while (true) {
      // Find the best merge (lowest rank)
      int? bestIdx;
      int? bestRank;

      for (int i = 0; i < tokens.length - 1; i++) {
        final pair = '${tokens[i]} ${tokens[i + 1]}';
        final rank = _mergeRanks[pair];
        if (rank != null && (bestRank == null || rank < bestRank)) {
          bestRank = rank;
          bestIdx = i;
        }
      }

      // No more merges possible
      if (bestIdx == null) break;

      // Apply the merge
      final merged = tokens[bestIdx] + tokens[bestIdx + 1];
      tokens = [
        ...tokens.sublist(0, bestIdx),
        merged,
        ...tokens.sublist(bestIdx + 2),
      ];
    }

    return tokens;
  }

  /// Gets the vocabulary size.
  int get vocabSize => _vocab.length;

  /// Checks if a token exists in vocabulary.
  bool hasToken(String token) => _vocab.containsKey(token);

  /// Gets the ID for a token, or unk_token_id if not found.
  int getTokenId(String token) => _vocab[token] ?? unkTokenId;
}
