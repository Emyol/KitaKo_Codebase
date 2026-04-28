import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// GemmaTokenizer for SigLIP-2 text encoding.
///
/// Implements the HuggingFace BPE tokenizer format used by SigLIP-2's
/// GemmaTokenizer (256K vocabulary, SentencePiece-style with byte fallback).
class GemmaTokenizer {
  late Map<String, int> _vocab;
  late Map<int, String> _reverseVocab;
  late List<(String, String)> _merges;
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
  bool _byteFallback = false;
  bool _fuseUnk = false;

  bool _isLoaded = false;

  /// Whether the tokenizer has been loaded
  bool get isLoaded => _isLoaded;

  /// Loads the tokenizer from a Flutter asset path.
  ///
  /// [assetPath] should be an asset path (e.g., 'assets/models/tokenizer/tokenizer.json').
  Future<void> loadFromAsset(String assetPath) => loadFromFile(assetPath);

  /// Loads the tokenizer from a tokenizer.json file (HuggingFace format).
  ///
  /// [tokenizerJsonPath] can be an asset path (starting with 'assets/') or a file path.
  Future<void> loadFromFile(String tokenizerJsonPath) async {
    String content;
    if (tokenizerJsonPath.startsWith('assets/')) {
      content = await rootBundle.loadString(tokenizerJsonPath);
    } else {
      final file = File(tokenizerJsonPath);
      content = await file.readAsString();
    }
    await loadFromJson(content);
  }

  /// Loads the tokenizer from JSON string.
  Future<void> loadFromJson(String jsonContent) async {
    final data = jsonDecode(jsonContent) as Map<String, dynamic>;

    final model = data['model'] as Map<String, dynamic>;
    final vocabData = model['vocab'];

    _vocab = {};
    _reverseVocab = {};

    // Handle both dict format {'token': id} and list format [['token', score], ...]
    if (vocabData is Map<String, dynamic>) {
      vocabData.forEach((token, id) {
        final tokenId = id as int;
        _vocab[token] = tokenId;
        _reverseVocab[tokenId] = token;
      });
    } else if (vocabData is List) {
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

    // Load BPE merges
    _merges = [];
    _mergeRanks = {};

    if (model.containsKey('merges')) {
      final mergesData = model['merges'] as List<dynamic>;
      for (int i = 0; i < mergesData.length; i++) {
        final merge = mergesData[i];
        String first, second;
        if (merge is List && merge.length == 2) {
          first = merge[0].toString();
          second = merge[1].toString();
        } else if (merge is String) {
          final parts = merge.split(' ');
          if (parts.length != 2) continue;
          first = parts[0];
          second = parts[1];
        } else {
          continue;
        }
        _merges.add((first, second));
        _mergeRanks['$first $second'] = i;
      }
    }

    // Read model flags
    _byteFallback = (model['byte_fallback'] as bool?) ?? false;
    _fuseUnk = (model['fuse_unk'] as bool?) ?? false;

    _isLoaded = true;
  }

  /// Tokenizes text into token IDs.
  ///
  /// Mirrors the HuggingFace AutoTokenizer pipeline used by SigLIP-2's
  /// SiglipProcessor + GemmaTokenizerFast (as called from external_test/query.py
  /// with `padding='max_length', max_length=64, truncation=True`).
  ///
  /// Pipeline:
  ///   1. Normalizer: replace ASCII space with `▁` (Metaspace marker).
  ///   2. BPE encode (byte_fallback + fuse_unk per tokenizer.json model flags).
  ///   3. Post-processor template: append `<eos>` (id=1) at the end.
  ///   4. Truncate from the front to fit `maxLength` (preserves the appended
  ///      EOS at the boundary, matching HF default truncation).
  ///   5. Right-pad with `<pad>` (id=0) up to `maxLength`
  ///      (HF `padding_side='right'`, `tokenizer.json` direction `Right`).
  ///
  /// Result layout: `[t0, t1, ..., tN, <eos>, <pad>, <pad>, ...]` (length 64).
  /// The text encoder receives an attention_mask forced to all-1s (see
  /// `siglip_inference.dart`) so the model can locate EOS dynamically.
  List<int> encode(String text) {
    if (!_isLoaded) {
      throw StateError('Tokenizer not loaded. Call loadFromFile first.');
    }

    List<int> tokens = _tokenize(text);

    // Truncate from the front so we leave room for the appended EOS.
    final maxContent = addEosToken ? maxLength - 1 : maxLength;
    if (tokens.length > maxContent) {
      tokens = tokens.sublist(0, maxContent);
    }

    // Post-processor: append EOS at the end.
    if (addEosToken) {
      tokens.add(eosTokenId);
    }

    // Right-pad with PAD tokens (HF padding_side='right').
    final padCount = maxLength - tokens.length;
    if (padCount > 0) {
      tokens.addAll(List<int>.filled(padCount, padTokenId));
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
        continue;
      }
      final token = _reverseVocab[id];
      if (token != null && !token.startsWith('<')) {
        tokens.add(token);
      }
    }

    return tokens.join('').replaceAll('▁', ' ').trim();
  }

  /// Pre-tokenization + BPE matching the HF tokenizer.json pipeline:
  ///
  /// - Normalizer (`Replace " " -> "▁"`): only replaces existing spaces.
  ///   Does **not** lowercase. Although `tokenizer_config.json` carries
  ///   `do_lower_case: true`, that flag applies to the slow Python tokenizer;
  ///   the fast tokenizer.json (which the HF AutoTokenizer actually uses for
  ///   SigLIP-2) has no Lowercase normalizer, so input case is preserved.
  ///   E.g. 'Hello' -> id 4521, 'hello' -> id 17534 — different tokens.
  ///
  /// - Pre-tokenizer (`Split " " MergedWithPrevious`): a no-op after the
  ///   normalizer since all spaces are already `▁`. We do NOT prepend an
  ///   extra leading `▁`; HF only adds `▁` where ASCII spaces existed.
  ///
  /// - BPE model with `byte_fallback=true`, `fuse_unk=true`.
  List<int> _tokenize(String text) {
    text = text.replaceAll(' ', '▁');
    return _bpeEncode(text);
  }

  /// BPE encoding: split into characters, then iteratively merge pairs.
  List<int> _bpeEncode(String text) {
    if (text.isEmpty) return [];

    // Split into individual characters (handling multi-byte correctly)
    List<String> symbols = text.split('');

    // Apply byte fallback for characters not in vocab
    if (_byteFallback) {
      symbols = _applyByteFallback(symbols);
    }

    // Iteratively apply BPE merges
    while (symbols.length > 1) {
      // Find the best (lowest rank) merge pair
      int? bestRank;
      int bestIndex = -1;

      for (int i = 0; i < symbols.length - 1; i++) {
        final key = '${symbols[i]} ${symbols[i + 1]}';
        final rank = _mergeRanks[key];
        if (rank != null && (bestRank == null || rank < bestRank)) {
          bestRank = rank;
          bestIndex = i;
        }
      }

      // No more merges possible
      if (bestIndex == -1) break;

      // Merge the best pair
      final merged = symbols[bestIndex] + symbols[bestIndex + 1];
      symbols = [
        ...symbols.sublist(0, bestIndex),
        merged,
        ...symbols.sublist(bestIndex + 2),
      ];
    }

    // Convert symbols to token IDs
    final result = <int>[];
    for (final symbol in symbols) {
      final id = _vocab[symbol];
      if (id != null) {
        result.add(id);
      } else if (_fuseUnk && result.isNotEmpty && result.last == unkTokenId) {
        // fuse_unk: consecutive unknowns become a single <unk>
        continue;
      } else {
        result.add(unkTokenId);
      }
    }

    return result;
  }

  /// Apply byte fallback: convert characters not in vocab to byte tokens.
  /// Byte tokens are formatted as <0xHH> where HH is the hex byte value.
  List<String> _applyByteFallback(List<String> symbols) {
    final result = <String>[];
    for (final symbol in symbols) {
      if (_vocab.containsKey(symbol)) {
        result.add(symbol);
      } else {
        // Convert to UTF-8 bytes and use byte fallback tokens
        final bytes = utf8.encode(symbol);
        for (final byte in bytes) {
          final byteToken = '<0x${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}>';
          result.add(byteToken);
        }
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
