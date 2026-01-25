import 'dart:convert';
import 'dart:io';

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

    // Load merges - format is array of [token1, token2] pairs
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
        // Fallback for space-separated format
        final parts = merge.split(' ');
        if (parts.length == 2) {
          _merges.add(parts);
          _mergeRanks[merge] = i;
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

  /// Internal tokenization using BPE.
  List<int> _tokenize(String text) {
    // Normalize text (basic)
    text = text.toLowerCase().trim();

    // For SentencePiece-style tokenizers, add word boundary marker
    text = '▁${text.replaceAll(' ', '▁')}';

    // Convert to initial character tokens
    List<String> tokens = text.split('').toList();

    // Apply BPE merges
    tokens = _applyBpe(tokens);

    // Convert to IDs
    return tokens.map((token) {
      return _vocab[token] ?? unkTokenId;
    }).toList();
  }

  /// Applies BPE merges to a list of tokens.
  List<String> _applyBpe(List<String> tokens) {
    while (tokens.length >= 2) {
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
