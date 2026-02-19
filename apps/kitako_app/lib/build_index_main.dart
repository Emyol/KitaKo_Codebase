/// KitaKo IVF-PQ Index Builder
///
/// Standalone Flutter entry-point that builds a serialised IVF-PQ index from
/// a directory of images and saves it to disk. The saved index can be loaded
/// by [ANNSearchService] for fast approximate search without re-training.
///
/// Usage (Windows desktop):
/// ```bash
/// flutter run -d windows -t lib/build_index_main.dart
/// ```
///
/// Edit the CONFIGURATION section below before running.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:kitako_ann/kitako_ann.dart' as ann;
import 'package:kitako_embedding/kitako_embedding.dart';

Future<void> main(List<String> args) async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║        KitaKo IVF-PQ Index Builder (Flutter)            ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');

  // ══════════════════════════════════════════════════════════════════════
  // === CONFIGURATION — edit these paths before running ===
  // ══════════════════════════════════════════════════════════════════════
  //
  // 1. Put your images (JPG / PNG / WEBP) inside imagesDir.
  // 2. Point modelsDir at the folder containing the ONNX model files
  //    (default: repo root models/kitako/).
  // 3. Run: flutter run -d windows -t lib/build_index_main.dart
  //
  final imagesDir = r'C:\path\to\your\images';
  final modelsDir = r'models\kitako'; // relative to repo root
  final outputDir = r'apps\kitako_app\assets\index';

  final imageModelPath = '$modelsDir\\kitako_image_encoder_int8.onnx';
  final textModelPath = '$modelsDir\\kitako_text_encoder_int8.onnx';
  final tokenizerPath = 'apps\\kitako_app\\assets\\models\\tokenizer\\tokenizer.json';
  final outputIndexPath = '$outputDir\\ann_index.bin';

  // IVF-PQ parameters (must match ANNSearchService._config for compatible search)
  const ivfpqDimension = 768;
  const numClusters = 16;
  const numSubquantizers = 64;
  const numCentroidsPerSubquantizer = 512;
  const numProbes = 16;
  const trainingIterations = 50;

  // ══════════════════════════════════════════════════════════════════════

  print('Configuration:');
  print('  Images directory : $imagesDir');
  print('  Output directory : $outputDir');
  print('  Image encoder    : $imageModelPath');
  print('  Text encoder     : $textModelPath');
  print('  Tokenizer        : $tokenizerPath');
  print('');

  // Validate paths
  if (!Directory(imagesDir).existsSync()) {
    print('ERROR: Images directory does not exist: $imagesDir');
    print('Edit the imagesDir variable in this file.');
    exit(1);
  }
  if (!File(imageModelPath).existsSync()) {
    print('ERROR: Image encoder not found: $imageModelPath');
    print('Run `adb push models/kitako/... /data/local/tmp/` or check modelsDir.');
    exit(1);
  }

  // Create output directory
  Directory(outputDir).createSync(recursive: true);

  // ── Embedding service ──────────────────────────────────────────────
  print('Initializing ONNX embedding service...');
  final embedder = KitakoEmbeddingService();

  try {
    await embedder.initializeFromFiles(
      imageModelPath: imageModelPath,
      textModelPath: textModelPath,
      tokenizerPath: tokenizerPath,
    );
    print('  ✓ Embedding service initialized');
  } catch (e, st) {
    print('ERROR: Failed to initialize embedding service: $e');
    print('Stack trace: $st');
    exit(1);
  }

  // ── Discover images ────────────────────────────────────────────────
  print('');
  print('Scanning for images...');
  final imageFiles = _findImages(imagesDir);
  print('  Found ${imageFiles.length} images');

  if (imageFiles.isEmpty) {
    print('ERROR: No images found in $imagesDir');
    exit(1);
  }

  // ── Generate embeddings ────────────────────────────────────────────
  print('');
  print('Generating embeddings...');
  final embeddings = <int, Float32List>{};
  final metadata = <int, Map<String, dynamic>>{};
  int processed = 0;
  int failed = 0;

  for (int i = 0; i < imageFiles.length; i++) {
    final file = imageFiles[i];
    try {
      final bytes = await File(file).readAsBytes();
      final embedding = await embedder.embedImage(Uint8List.fromList(bytes));

      embeddings[i] = embedding;
      metadata[i] = {
        'path': file,
        'filename': file.split(Platform.pathSeparator).last,
      };
      processed++;

      if (processed % 10 == 0 || processed == imageFiles.length) {
        final pct = (processed / imageFiles.length * 100).toStringAsFixed(1);
        print('  Processing: $processed/${imageFiles.length} ($pct%)');
      }
    } catch (e) {
      failed++;
      print('  WARNING: Failed to process $file: $e');
    }
  }

  print('');
  print('  ✓ Generated $processed embeddings ($failed failed)');

  if (embeddings.isEmpty) {
    print('ERROR: No embeddings generated');
    exit(1);
  }

  if (embeddings.length < 600) {
    print(
      'WARNING: Only ${embeddings.length} embeddings — IVF-PQ training needs '
      'at least 600 vectors for stable results. '
      'Proceeding, but accuracy may be lower.',
    );
  }

  // ── Build IVF-PQ index ─────────────────────────────────────────────
  print('');
  print('Building IVF-PQ index...');

  final config = ann.IvfPqConfig(
    dimension: ivfpqDimension,
    numClusters: numClusters,
    numSubquantizers: numSubquantizers,
    numCentroidsPerSubquantizer: numCentroidsPerSubquantizer,
    numProbes: numProbes,
    trainingIterations: trainingIterations,
  );

  final index = ann.IvfPqAnnIndex(config: config);
  final vectors = embeddings.values.toList();
  final ids = embeddings.keys.toList();

  try {
    print('  Training on ${vectors.length} vectors...');
    await index.train(vectors);

    print('  Adding vectors to index...');
    await index.addVectors(vectors, ids);

    print('  ✓ Index built with ${index.size} vectors');
    print('  Stats: ${index.getStatistics()}');
  } catch (e, st) {
    print('ERROR: Failed to build index: $e');
    print('Stack trace: $st');
    exit(1);
  }

  // ── Save index ─────────────────────────────────────────────────────
  print('');
  print('Saving index...');
  try {
    await index.save(outputIndexPath);
    print('  ✓ Index saved to: $outputIndexPath');
  } catch (e) {
    print('ERROR: Failed to save index: $e');
    exit(1);
  } finally {
    index.dispose();
  }

  // ── Save metadata ──────────────────────────────────────────────────
  final metadataPath = outputIndexPath.replaceAll('.bin', '.meta.json');
  print('');
  print('Saving metadata...');
  try {
    final metaContent = {
      'algorithm': 'IVF-PQ',
      'dimension': ivfpqDimension,
      'numClusters': numClusters,
      'numSubquantizers': numSubquantizers,
      'numCentroidsPerSubquantizer': numCentroidsPerSubquantizer,
      'numProbes': numProbes,
      'item_count': embeddings.length,
      'index_file': 'ann_index.bin',
      'created': DateTime.now().toIso8601String(),
      'items': metadata.map((k, v) => MapEntry(k.toString(), v)),
    };

    final metaJson = const JsonEncoder.withIndent('  ').convert(metaContent);
    await File(metadataPath).writeAsString(metaJson);
    print('  ✓ Metadata saved to: $metadataPath');
  } catch (e) {
    print('ERROR: Failed to save metadata: $e');
    exit(1);
  }

  print('');
  print('╔══════════════════════════════════════════════════════════╗');
  print('║                    BUILD COMPLETE                        ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');
  print('Index stats:');
  print('  - Items     : ${embeddings.length}');
  print('  - Dimension : $ivfpqDimension');
  print('  - Algorithm : IVF-PQ');
  print('  - Index file: $outputIndexPath');
  print('');
  print('You can now load this index in ANNSearchService with index.load(path).');

  exit(0);
}

/// Recursively find all image files under [dirPath].
List<String> _findImages(String dirPath) {
  final dir = Directory(dirPath);
  final images = <String>[];
  const extensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final lower = entity.path.toLowerCase();
      if (extensions.any(lower.endsWith)) {
        images.add(entity.path);
      }
    }
  }

  return images..sort();
}
