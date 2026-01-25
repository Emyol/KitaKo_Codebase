import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// A test widget to verify SigLIP embedding inference works.
///
/// Add this to your app temporarily to test the models.
class EmbeddingTestWidget extends StatefulWidget {
  const EmbeddingTestWidget({super.key});

  @override
  State<EmbeddingTestWidget> createState() => _EmbeddingTestWidgetState();
}

class _EmbeddingTestWidgetState extends State<EmbeddingTestWidget> {
  final KitakoEmbeddingService _service = KitakoEmbeddingService();
  final List<String> _logs = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
    debugPrint(message);
  }

  Future<String> _copyAssetToFile(String assetPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = assetPath.split('/').last;
    final file = File('${dir.path}/$fileName');

    if (!await file.exists()) {
      _log('Copying $fileName to documents...');
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }

    return file.path;
  }

  Future<void> _runTest() async {
    setState(() {
      _isLoading = true;
      _logs.clear();
    });

    try {
      _log('Starting embedding test...');

      // Step 1: Copy models from assets to files (tflite_flutter needs file paths for some ops)
      _log('Step 1: Preparing model files...');

      final tokenizerPath = await _copyAssetToFile('assets/tokenizer/tokenizer.json');
      _log('Tokenizer path: $tokenizerPath');

      // Step 2: Initialize the service
      _log('Step 2: Loading models...');
      final stopwatch = Stopwatch()..start();

      // For tflite_flutter, we use asset paths directly for the models
      // but file path for tokenizer (since it's JSON parsing)
      await _service.initialize(
        imageModelPath: 'assets/model/image_encoder/kitako_image_encoder_int8.tflite',
        textModelPath: 'assets/model/text_encoder/kitako_text_encoder_dynamic.tflite',
        tokenizerPath: tokenizerPath,
      );

      _log('Models loaded in ${stopwatch.elapsedMilliseconds}ms');
      _log('Image encoder ready: ${_service.isImageEncoderReady}');
      _log('Text encoder ready: ${_service.isTextEncoderReady}');

      // Step 3: Test text embedding
      _log('Step 3: Testing text embedding...');
      stopwatch.reset();

      final testTexts = [
        'a photo of a cat',
        'a photo of a dog',
        'beautiful sunset over the ocean',
      ];

      for (final text in testTexts) {
        final embedding = _service.embedText(text);
        _log('Text: "$text"');
        _log('  → Embedding shape: ${embedding.length}');
        _log('  → First 5 values: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).toList()}');
      }

      _log('Text embeddings computed in ${stopwatch.elapsedMilliseconds}ms');

      // Step 4: Test image embedding with a dummy image
      _log('Step 4: Testing image embedding with test image...');
      stopwatch.reset();

      final testImage = ImagePreprocessor.createTestImage();
      _log('Test image shape: ${testImage.length} (should be 150528)');

      final imageEmbedding = _service.embedPreprocessedImage(testImage);
      _log('Image embedding shape: ${imageEmbedding.length}');
      _log('First 5 values: ${imageEmbedding.take(5).map((e) => e.toStringAsFixed(4)).toList()}');
      _log('Image embedding computed in ${stopwatch.elapsedMilliseconds}ms');

      // Step 5: Test similarity
      _log('Step 5: Testing similarity computation...');

      final catEmbedding = _service.embedText('a photo of a cat');
      final dogEmbedding = _service.embedText('a photo of a dog');

      final catDogSim = _service.cosineSimilarity(catEmbedding, dogEmbedding);
      _log('Similarity(cat, dog): ${catDogSim.toStringAsFixed(4)}');

      final imageCatSim = _service.cosineSimilarity(imageEmbedding, catEmbedding);
      _log('Similarity(test_image, cat_text): ${imageCatSim.toStringAsFixed(4)}');

      _log('✅ All tests passed!');
    } catch (e, stack) {
      _log('❌ Error: $e');
      _log('Stack: $stack');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Embedding Test'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _runTest,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Run Embedding Test'),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color color = Colors.white70;
                  if (log.contains('✅')) color = Colors.greenAccent;
                  if (log.contains('❌')) color = Colors.redAccent;
                  if (log.contains('Step')) color = Colors.cyanAccent;

                  return Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: color,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
