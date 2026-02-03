import 'dart:convert';
import 'dart:io';

void main() async {
  final tokenizerFile = File('../apps/kitako_app/assets/tokenizer/tokenizer.json');
  final content = await tokenizerFile.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;

  print('=== Tokenizer Configuration ===\n');

  // Check normalizer
  if (data.containsKey('normalizer')) {
    print('Normalizer: ${jsonEncode(data['normalizer'])}');
  } else {
    print('Normalizer: NOT FOUND');
  }
  print('');

  // Check pre_tokenizer
  if (data.containsKey('pre_tokenizer')) {
    print('Pre-tokenizer: ${jsonEncode(data['pre_tokenizer'])}');
  } else {
    print('Pre-tokenizer: NOT FOUND');
  }
  print('');

  // Check decoder
  if (data.containsKey('decoder')) {
    print('Decoder: ${jsonEncode(data['decoder'])}');
  } else {
    print('Decoder: NOT FOUND');
  }
  print('');

  // Check model type
  final model = data['model'] as Map<String, dynamic>;
  print('Model type: ${model['type']}');
  print('');

  // Check if there are merges
  if (model.containsKey('merges')) {
    final merges = model['merges'] as List;
    print('Number of merges: ${merges.length}');
    print('First 10 merges:');
    for (int i = 0; i < 10 && i < merges.length; i++) {
      print('  $i: ${merges[i]}');
    }
  } else {
    print('Merges: NOT FOUND (might be Unigram/SentencePiece model)');
  }
}