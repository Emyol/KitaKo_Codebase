import 'dart:convert';
import 'dart:io';

void main() async {
  // Load tokenizer
  final tokenizerFile = File('../apps/kitako_app/assets/tokenizer/tokenizer.json');
  final content = await tokenizerFile.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;

  // Load vocab
  final model = data['model'] as Map<String, dynamic>;
  final vocabData = model['vocab'] as List;

  final vocab = <String, int>{};
  for (int i = 0; i < vocabData.length; i++) {
    if (vocabData[i] is List && vocabData[i].length >= 1) {
      final token = vocabData[i][0] as String;
      vocab[token] = i;
    }
  }

  print('Vocab size: ${vocab.length}');
  print('');

  // Check specific tokens
  final testWords = ['dog', 'cat', '▁dog', '▁cat', 'a', 'photo', 'of'];
  print('Looking for specific tokens:');
  for (final word in testWords) {
    if (vocab.containsKey(word)) {
      print('  "$word" -> ${vocab[word]}');
    } else {
      print('  "$word" -> NOT FOUND');
    }
  }

  print('');
  print('Sample tokens from vocab:');
  int count = 0;
  for (final entry in vocab.entries) {
    if (count < 50) {
      print('  ${entry.value}: "${entry.key}"');
      count++;
    } else {
      break;
    }
  }
}