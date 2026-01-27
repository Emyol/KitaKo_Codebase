/// Simple tokenizer utilities for Taglish text.
///
/// Provides basic tokenization for normalized text processing.

/// Tokenizes text into words.
///
/// Splits on whitespace and filters out empty tokens.
List<String> tokenize(String text) {
  if (text.isEmpty) return [];
  return text
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
}

/// Joins tokens back into a string.
String detokenize(List<String> tokens) {
  return tokens.join(' ');
}

/// Checks if a token is punctuation-only.
bool isPunctuation(String token) {
  if (token.isEmpty) return false;
  const punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';
  return token.split('').every((c) => punctuation.contains(c));
}

/// Removes punctuation-only tokens from a list.
List<String> removePunctuation(List<String> tokens) {
  return tokens.where((t) => !isPunctuation(t)).toList();
}

/// Extracts only alphabetic tokens (words).
List<String> extractWords(List<String> tokens) {
  return tokens.where((t) => RegExp(r'^[a-zA-Z]+$').hasMatch(t)).toList();
}
