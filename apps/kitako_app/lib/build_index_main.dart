/// KitaKo Index Builder - Flutter Version
///
/// Run this as a Flutter app in headless mode to build the HNSW index.
///
/// Usage:
/// ```bash
/// flutter run -d windows -t lib/build_index_main.dart
/// ```
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:kitako_ann/kitako_ann.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

/// Build an HNSW index from a directory of images
Future<void> main(List<String> args) async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║          KitaKo HNSW Index Builder (Flutter)             ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');

  // ══════════════════════════════════════════════════════════════════════
  // === CONFIGURATION - EDIT THESE PATHS BEFORE RUNNING ===
  // ══════════════════════════════════════════════════════════════════════
  //
  // 1. Create a folder with your test images (JPG, PNG, etc.)
  // 2. Update imagesDir below to point to that folder
  // 3. Run: flutter run -d windows -t lib/build_index_main.dart
  //
  // Example: Put 10-100 images in a folder like:
  //   C:\Users\Jhezra\Documents\test_images\
  //
  final imagesDir = r'C:\Users\Jhezra\Documents\KitaKo_System\dataset\images\taglish_test_images';
  final outputDir = r'C:\Users\Jhezra\Documents\KitaKo_System\apps\kitako_app\assets\index';
  final modelsDir = r'C:\Users\Jhezra\Documents\KitaKo_System\assets\models';

  final imageModelPath = '$modelsDir\\image_encoder\\kitako_image_encoder_int8.tflite';
  final textModelPath = '$modelsDir\\text_encoder\\kitako_text_encoder_dynamic.tflite';
  final tokenizerPath = '$modelsDir\\tokenizer';
  final outputIndexPath = '$outputDir\\ann_index.bin';

  print('Configuration:');
  print('  Images directory: $imagesDir');
  print('  Output directory: $outputDir');
  print('  Model paths:');
  print('    Image encoder: $imageModelPath');
  print('    Text encoder: $textModelPath');
  print('    Tokenizer: $tokenizerPath');
  print('');

  // Validate paths
  if (!Directory(imagesDir).existsSync()) {
    print('ERROR: Images directory does not exist: $imagesDir');
    print('Please edit the imagesDir variable in this file.');
    exit(1);
  }

  if (!File(imageModelPath).existsSync()) {
    print('ERROR: Image encoder model not found: $imageModelPath');
    exit(1);
  }

  // Create output directory if needed
  final outDir = Directory(outputDir);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Initialize embedding service
  print('Initializing embedding service...');
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
    print('');
    print('Make sure:');
    print('  1. Model files exist at the specified paths');
    print('  2. TFLite DLL is in the blobs/ directory');
    exit(1);
  }

  // Find all images
  print('');
  print('Scanning for images...');
  final imageFiles = _findImages(imagesDir);
  print('  Found ${imageFiles.length} images');

  if (imageFiles.isEmpty) {
    print('ERROR: No images found in directory');
    exit(1);
  }

  // Generate embeddings
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
      final embedding = embedder.embedImage(Uint8List.fromList(bytes));

      embeddings[i] = embedding;
      metadata[i] = {
        'path': file,
        'filename': file.split(Platform.pathSeparator).last,
      };
      processed++;

      // Progress update
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

  // Build HNSW index
  print('');
  print('Building HNSW index...');

  // HNSW parameters
  const m = 16;
  const efConstruction = 200;

  final client = LocalAnnClient(config: AnnClientConfig.siglip768);

  try {
    await client.buildIndex(
      embeddings,
      M: m,
      efConstruction: efConstruction,
    );
    print('  ✓ Index built with ${client.itemCount} items');
  } catch (e, st) {
    print('ERROR: Failed to build index: $e');
    print('Stack trace: $st');
    exit(1);
  }

  // Save index
  print('');
  print('Saving index...');
  try {
    await client.saveIndex(outputIndexPath);
    print('  ✓ Index saved to: $outputIndexPath');
  } catch (e) {
    print('ERROR: Failed to save index: $e');
    exit(1);
  }

  // Save metadata
  final metadataPath = outputIndexPath.replaceAll('.bin', '.meta.json');
  print('');
  print('Saving metadata...');
  try {
    final metaContent = {
      'dimension': 768,
      'space_type': 0,
      'item_count': embeddings.length,
      'M': m,
      'efConstruction': efConstruction,
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
  print('  - Items: ${embeddings.length}');
  print('  - Dimension: 768');
  print('  - Index file: $outputIndexPath');
  print('');
  print('You can now run the app and use real semantic search!');

  // Exit the app
  exit(0);
}

/// Find all image files in a directory (recursive)
List<String> _findImages(String dirPath) {
  final dir = Directory(dirPath);
  final images = <String>[];
  final extensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final ext = entity.path.toLowerCase();
      if (extensions.any((e) => ext.endsWith(e))) {
        images.add(entity.path);
      }
    }
  }

  return images..sort();
}
