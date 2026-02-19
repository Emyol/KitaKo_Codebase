import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// Cross-modal embedding test: Image ↔ Text alignment.
///
/// Verifies that the SigLIP model correctly maps images and their
/// text descriptions into nearby embedding vectors, both in English
/// and Tagalog.
///
/// Run with:
///   flutter test integration_test/cross_modal_embedding_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Test images: solid colors with known descriptions
  // Using PPM format (simple, no compression, widely supported)
  final testImages = <String, _TestImage>{
    'red':    _TestImage(255, 0, 0,     'a red image',     'isang pulang larawan'),
    'green':  _TestImage(0, 255, 0,     'a green image',   'isang berdeng larawan'),
    'blue':   _TestImage(0, 0, 255,     'a blue image',    'isang asul na larawan'),
    'yellow': _TestImage(255, 255, 0,   'a yellow image',  'isang dilaw na larawan'),
    'white':  _TestImage(255, 255, 255, 'a white image',   'isang puting larawan'),
    'black':  _TestImage(0, 0, 0,       'a black image',   'isang itim na larawan'),
  };

  // Descriptive phrases for cross-modal matching
  final descriptivePhrases = <String>[
    'a solid red color',
    'a solid green color',
    'a solid blue color',
    'a solid yellow color',
    'a bright white surface',
    'a dark black surface',
  ];

  setUpAll(() async {
    print('');
    print('═══════════════════════════════════════════════════════════');
    print(' Cross-Modal Embedding Test: Image ↔ Text');
    print('═══════════════════════════════════════════════════════════');
    print('');
  });

  group('Cross-Modal Embeddings', () {
    late OnnxEmbeddingService service;

    testWidgets('Initialize model', (tester) async {
      service = OnnxEmbeddingService();

      final appDir = await getApplicationDocumentsDirectory();
      final searchDirs = [
        '${appDir.path}/onnx_models',
        '/data/local/tmp',
      ];

      print('Searching for models in:');
      for (final dir in searchDirs) {
        print('  - $dir');
      }

      String? visionPath;
      String? textPath;

      for (final dir in searchDirs) {
        final int8V = '$dir/kitako_image_encoder_int8.onnx';
        final int8T = '$dir/kitako_text_encoder_int8.onnx';
        if (await _fileExists(int8V) && await _fileExists(int8T)) {
          visionPath = int8V;
          textPath = int8T;
          print('Using Kitako INT8 from $dir');
          break;
        }

        final fp32V = '$dir/kitako_image_encoder_fp32.onnx';
        final fp32T = '$dir/kitako_text_encoder_fp32.onnx';
        if (await _fileExists(fp32V) && await _fileExists(fp32T)) {
          visionPath = fp32V;
          textPath = fp32T;
          print('Using Kitako FP32 from $dir');
          break;
        }
      }

      if (visionPath == null || textPath == null) {
        fail('No Kitako models found in any of: $searchDirs');
      }

      await service.initialize(
        visionModelPath: visionPath,
        textModelPath: textPath,
        tokenizerPath: 'assets/models/tokenizer/tokenizer.json',
        modelVersion: SiglipModelVersion.siglip2,
      );

      expect(service.isImageEncoderReady, true);
      expect(service.isTextEncoderReady, true);
      print('Model initialized (vision + text ready)\n');
    });

    testWidgets('Image embedding sanity check', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Image Embedding Sanity Check');
      print('───────────────────────────────────────────────────────────');
      print('');

      // Generate embeddings for all test images
      for (final entry in testImages.entries) {
        final img = entry.value;
        final embedding = service.embedImage(img.ppmBytes);

        expect(embedding.length, 768);

        double norm = 0;
        for (final v in embedding) {
          norm += v * v;
        }
        norm = math.sqrt(norm);

        print('${entry.key.padRight(8)} dim=${embedding.length}  '
            'L2 norm=${norm.toStringAsFixed(4)}  '
            'range=[${embedding.reduce(math.min).toStringAsFixed(3)}, '
            '${embedding.reduce(math.max).toStringAsFixed(3)}]');

        expect(norm, closeTo(1.0, 0.05), reason: 'Should be L2 normalized');
      }
      print('');
    });

    testWidgets('Image-image similarity (color discrimination)', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Image ↔ Image Similarity (should differ by color)');
      print('───────────────────────────────────────────────────────────');
      print('');

      final names = testImages.keys.toList();
      final embeddings = <String, Float32List>{};
      for (final name in names) {
        embeddings[name] = service.embedImage(testImages[name]!.ppmBytes);
      }

      // Print similarity matrix
      final header = ''.padRight(8) + names.map((n) => n.padRight(8)).join();
      print(header);
      print('${'─' * 8}${'─' * (8 * names.length)}');

      for (final rowName in names) {
        final row = StringBuffer(rowName.padRight(8));
        for (final colName in names) {
          final sim = _cosineSimilarity(embeddings[rowName]!, embeddings[colName]!);
          final marker = rowName == colName ? '*' : ' ';
          row.write('${sim.toStringAsFixed(3)}$marker'.padRight(8));
        }
        print(row.toString());
      }

      // Verify same image = 1.0
      for (final name in names) {
        final selfSim = _cosineSimilarity(embeddings[name]!, embeddings[name]!);
        expect(selfSim, closeTo(1.0, 0.001));
      }

      // Verify different colors have lower similarity than self
      final redBlue = _cosineSimilarity(embeddings['red']!, embeddings['blue']!);
      final redRed = _cosineSimilarity(embeddings['red']!, embeddings['red']!);
      print('');
      print('red↔red: ${redRed.toStringAsFixed(4)}');
      print('red↔blue: ${redBlue.toStringAsFixed(4)}');
      expect(redRed, greaterThan(redBlue));
      print('');
    });

    testWidgets('Image ↔ English text matching', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Image ↔ English Text Cross-Modal Similarity');
      print('───────────────────────────────────────────────────────────');
      print('');

      final imgEntries = testImages.entries.toList();
      final imgEmbeddings = <String, Float32List>{};
      for (final entry in imgEntries) {
        imgEmbeddings[entry.key] = service.embedImage(entry.value.ppmBytes);
      }

      final textEmbeddings = <String, Float32List>{};
      for (final entry in imgEntries) {
        textEmbeddings[entry.key] = service.embedText(entry.value.enText);
      }

      // Print cross-modal matrix: rows = images, cols = EN texts
      final header = ''.padRight(10) +
          imgEntries.map((e) => e.value.enText.substring(0, 7).padRight(10)).join();
      print('IMG\\TEXT   $header');
      print('${'─' * 10}${'─' * (10 * imgEntries.length)}');

      int correctMatches = 0;
      for (final imgEntry in imgEntries) {
        final imgEmbed = imgEmbeddings[imgEntry.key]!;
        final row = StringBuffer(imgEntry.key.padRight(10));

        double bestSim = double.negativeInfinity;
        String bestMatch = '';

        for (final txtEntry in imgEntries) {
          final txtEmbed = textEmbeddings[txtEntry.key]!;
          final sim = _cosineSimilarity(imgEmbed, txtEmbed);

          if (sim > bestSim) {
            bestSim = sim;
            bestMatch = txtEntry.key;
          }

          final marker = imgEntry.key == txtEntry.key ? '*' : ' ';
          row.write('${sim.toStringAsFixed(3)}$marker'.padRight(10));
        }
        print(row.toString());

        if (bestMatch == imgEntry.key) correctMatches++;
      }

      print('');
      print('* = correct pair (image matches its own description)');
      print('Correct top-1 matches: $correctMatches / ${imgEntries.length}');
      print('');
    });

    testWidgets('Image ↔ Tagalog text matching', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Image ↔ Tagalog Text Cross-Modal Similarity');
      print('───────────────────────────────────────────────────────────');
      print('');

      final imgEntries = testImages.entries.toList();
      final imgEmbeddings = <String, Float32List>{};
      for (final entry in imgEntries) {
        imgEmbeddings[entry.key] = service.embedImage(entry.value.ppmBytes);
      }

      final tlEmbeddings = <String, Float32List>{};
      for (final entry in imgEntries) {
        tlEmbeddings[entry.key] = service.embedText(entry.value.tlText);
      }

      // Print cross-modal matrix: rows = images, cols = TL texts
      print('IMG\\TEXT   ${imgEntries.map((e) => e.key.padRight(10)).join()}');
      print('${'─' * 10}${'─' * (10 * imgEntries.length)}');

      int correctMatches = 0;
      for (final imgEntry in imgEntries) {
        final imgEmbed = imgEmbeddings[imgEntry.key]!;
        final row = StringBuffer(imgEntry.key.padRight(10));

        double bestSim = double.negativeInfinity;
        String bestMatch = '';

        for (final txtEntry in imgEntries) {
          final txtEmbed = tlEmbeddings[txtEntry.key]!;
          final sim = _cosineSimilarity(imgEmbed, txtEmbed);

          if (sim > bestSim) {
            bestSim = sim;
            bestMatch = txtEntry.key;
          }

          final marker = imgEntry.key == txtEntry.key ? '*' : ' ';
          row.write('${sim.toStringAsFixed(3)}$marker'.padRight(10));
        }
        print(row.toString());

        if (bestMatch == imgEntry.key) correctMatches++;
      }

      print('');
      print('* = correct pair');
      print('Correct top-1 matches (Tagalog): $correctMatches / ${imgEntries.length}');
      print('');
    });

    testWidgets('Image ↔ descriptive phrase ranking', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' Image → Best Matching Phrase (English)');
      print('───────────────────────────────────────────────────────────');
      print('');

      final imgEntries = testImages.entries.toList();
      final phraseEmbeddings = <String, Float32List>{};
      for (final phrase in descriptivePhrases) {
        phraseEmbeddings[phrase] = service.embedText(phrase);
      }

      for (final imgEntry in imgEntries) {
        final imgEmbed = service.embedImage(imgEntry.value.ppmBytes);

        // Rank all phrases by similarity
        final scores = <MapEntry<String, double>>[];
        for (final phraseEntry in phraseEmbeddings.entries) {
          final sim = _cosineSimilarity(imgEmbed, phraseEntry.value);
          scores.add(MapEntry(phraseEntry.key, sim));
        }
        scores.sort((a, b) => b.value.compareTo(a.value));

        print('${imgEntry.key.toUpperCase()} image (${imgEntry.value.enText}):');
        for (var i = 0; i < scores.length; i++) {
          final rank = i == 0 ? '>>>' : '   ';
          print('  $rank ${scores[i].value.toStringAsFixed(4)}  "${scores[i].key}"');
        }
        print('');
      }
    });

    testWidgets('EN vs TL text → same image similarity', (tester) async {
      print('');
      print('───────────────────────────────────────────────────────────');
      print(' EN vs TL Descriptions → Same Image Similarity');
      print('───────────────────────────────────────────────────────────');
      print('');
      print('For each color: how similar is the image to its EN vs TL description?');
      print('');
      print('${'Color'.padRight(10)} ${'EN sim'.padRight(10)} ${'TL sim'.padRight(10)} ${'Gap'.padRight(10)}');
      print('${'─' * 10} ${'─' * 10} ${'─' * 10} ${'─' * 10}');

      for (final entry in testImages.entries) {
        final imgEmbed = service.embedImage(entry.value.ppmBytes);
        final enEmbed = service.embedText(entry.value.enText);
        final tlEmbed = service.embedText(entry.value.tlText);

        final enSim = _cosineSimilarity(imgEmbed, enEmbed);
        final tlSim = _cosineSimilarity(imgEmbed, tlEmbed);
        final gap = (enSim - tlSim).abs();

        print('${entry.key.padRight(10)} '
            '${enSim.toStringAsFixed(4).padRight(10)} '
            '${tlSim.toStringAsFixed(4).padRight(10)} '
            '${gap.toStringAsFixed(4).padRight(10)}');
      }
      print('');
      print('Small gap = model treats EN and TL descriptions equivalently');
      print('');
    });

    testWidgets('Cleanup', (tester) async {
      service.dispose();
      print('Service disposed');
    });
  });
}

/// Test image definition with solid color and bilingual descriptions.
class _TestImage {
  final int r, g, b;
  final String enText;
  final String tlText;
  late final Uint8List ppmBytes;

  _TestImage(this.r, this.g, this.b, this.enText, this.tlText) {
    ppmBytes = _createPpm(r, g, b);
  }

  /// Create a 224x224 solid color PPM image.
  static Uint8List _createPpm(int r, int g, int b) {
    const size = 224;
    final header = 'P6\n$size $size\n255\n';
    final headerBytes = header.codeUnits;
    final pixelCount = size * size;
    final rgbBytes = Uint8List(pixelCount * 3);

    for (var i = 0; i < pixelCount; i++) {
      rgbBytes[i * 3] = r;
      rgbBytes[i * 3 + 1] = g;
      rgbBytes[i * 3 + 2] = b;
    }

    final result = Uint8List(headerBytes.length + rgbBytes.length);
    result.setRange(0, headerBytes.length, headerBytes);
    result.setRange(headerBytes.length, result.length, rgbBytes);
    return result;
  }
}

Future<bool> _fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

double _cosineSimilarity(Float32List a, Float32List b) {
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = math.sqrt(normA) * math.sqrt(normB);
  return denom == 0 ? 0 : dot / denom;
}
