/// KitaKo Index Builder
///
/// Command-line tool to build HNSW indexes from image directories.
///
/// Usage:
/// ```bash
/// dart run tools/build_index.dart --images /path/to/images --output index.bin
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:kitako_ann/kitako_ann.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

/// Build an HNSW index from a directory of images
Future<void> main(List<String> args) async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║          KitaKo HNSW Index Builder                       ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');

  // Parse arguments
  final config = _parseArgs(args);
  if (config == null) {
    _printUsage();
    exit(1);
  }

  print('Configuration:');
  print('  Images directory: ${config.imagesDir}');
  print('  Output index: ${config.outputPath}');
  print('  Model paths:');
  print('    Image encoder: ${config.imageModelPath}');
  print('    Text encoder: ${config.textModelPath}');
  print('    Tokenizer: ${config.tokenizerPath}');
  print('');

  // Validate paths
  if (!Directory(config.imagesDir).existsSync()) {
    print('ERROR: Images directory does not exist: ${config.imagesDir}');
    exit(1);
  }

  // Initialize embedding service
  print('Initializing embedding service...');
  final embedder = KitakoEmbeddingService();

  try {
    await embedder.initializeFromFiles(
      imageModelPath: config.imageModelPath,
      textModelPath: config.textModelPath,
      tokenizerPath: config.tokenizerPath,
    );
    print('  ✓ Embedding service initialized');
  } catch (e) {
    print('ERROR: Failed to initialize embedding service: $e');
    print('');
    print('Make sure the model files exist at the specified paths.');
    exit(1);
  }

  // Find all images
  print('');
  print('Scanning for images...');
  final imageFiles = _findImages(config.imagesDir);
  print('  Found ${imageFiles.length} images');

  if (imageFiles.isEmpty) {
    print('ERROR: No images found in directory');
    exit(1);
  }

  // Generate embeddings
  print('');
  print('Generating embeddings...');
  final embeddings = <int, Float32List>{};
  final metadata = <int, String>{};
  int processed = 0;
  int failed = 0;

  for (int i = 0; i < imageFiles.length; i++) {
    final file = imageFiles[i];
    try {
      final bytes = await File(file).readAsBytes();
      final embedding = embedder.embedImage(Uint8List.fromList(bytes));

      embeddings[i] = embedding;
      metadata[i] = file;
      processed++;

      // Progress update
      if (processed % 10 == 0 || processed == imageFiles.length) {
        final pct = (processed / imageFiles.length * 100).toStringAsFixed(1);
        stdout.write('\r  Processing: $processed/${imageFiles.length} ($pct%)');
      }
    } catch (e) {
      failed++;
      print('\n  WARNING: Failed to process $file: $e');
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
  final client = LocalAnnClient(config: AnnClientConfig.siglip768);

  try {
    await client.buildIndex(
      embeddings,
      M: config.m,
      efConstruction: config.efConstruction,
    );
    print('  ✓ Index built with ${client.itemCount} items');
  } catch (e) {
    print('ERROR: Failed to build index: $e');
    exit(1);
  }

  // Save index
  print('');
  print('Saving index...');
  try {
    await client.saveIndex(config.outputPath);
    print('  ✓ Index saved to: ${config.outputPath}');
  } catch (e) {
    print('ERROR: Failed to save index: $e');
    exit(1);
  }

  // Save metadata
  final metadataPath = config.outputPath.replaceAll('.bin', '.meta.json');
  print('');
  print('Saving metadata...');
  try {
    final metaJson = StringBuffer();
    metaJson.writeln('{');
    metaJson.writeln('  "dimension": 768,');
    metaJson.writeln('  "space_type": 0,');
    metaJson.writeln('  "item_count": ${embeddings.length},');
    metaJson.writeln('  "M": ${config.m},');
    metaJson.writeln('  "ef_construction": ${config.efConstruction},');
    metaJson.writeln('  "description": "KitaKo ANN Index for SigLIP-768 embeddings",');
    metaJson.writeln('  "created_at": "${DateTime.now().toIso8601String()}",');
    metaJson.writeln('  "files": {');

    final entries = metadata.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final comma = i < entries.length - 1 ? ',' : '';
      metaJson.writeln('    "${entries[i].key}": "${entries[i].value.replaceAll('\\', '/')}"$comma');
    }

    metaJson.writeln('  }');
    metaJson.writeln('}');

    await File(metadataPath).writeAsString(metaJson.toString());
    print('  ✓ Metadata saved to: $metadataPath');
  } catch (e) {
    print('WARNING: Failed to save metadata: $e');
  }

  // Cleanup
  client.dispose();
  embedder.dispose();

  print('');
  print('╔══════════════════════════════════════════════════════════╗');
  print('║                    BUILD COMPLETE!                       ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');
  print('Next steps:');
  print('  1. Copy ${config.outputPath} to apps/kitako_app/assets/index/');
  print('  2. Copy $metadataPath to apps/kitako_app/assets/index/');
  print('  3. Run: flutter clean && flutter run');
}

/// Configuration for index building
class BuildConfig {
  final String imagesDir;
  final String outputPath;
  final String imageModelPath;
  final String textModelPath;
  final String tokenizerPath;
  final int m;
  final int efConstruction;

  BuildConfig({
    required this.imagesDir,
    required this.outputPath,
    required this.imageModelPath,
    required this.textModelPath,
    required this.tokenizerPath,
    this.m = 16,
    this.efConstruction = 200,
  });
}

/// Parse command-line arguments
BuildConfig? _parseArgs(List<String> args) {
  String? imagesDir;
  String? outputPath;
  String imageModelPath = 'assets/models/image_encoder/kitako_image_encoder_int8.tflite';
  String textModelPath = 'assets/models/text_encoder/kitako_text_encoder_dynamic.tflite';
  String tokenizerPath = 'assets/models/tokenizer/tokenizer.json';
  int m = 16;
  int efConstruction = 200;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--images':
      case '-i':
        if (i + 1 < args.length) imagesDir = args[++i];
        break;
      case '--output':
      case '-o':
        if (i + 1 < args.length) outputPath = args[++i];
        break;
      case '--image-model':
        if (i + 1 < args.length) imageModelPath = args[++i];
        break;
      case '--text-model':
        if (i + 1 < args.length) textModelPath = args[++i];
        break;
      case '--tokenizer':
        if (i + 1 < args.length) tokenizerPath = args[++i];
        break;
      case '--m':
        if (i + 1 < args.length) m = int.parse(args[++i]);
        break;
      case '--ef':
        if (i + 1 < args.length) efConstruction = int.parse(args[++i]);
        break;
      case '--help':
      case '-h':
        return null;
    }
  }

  if (imagesDir == null) {
    print('ERROR: --images directory is required');
    return null;
  }

  outputPath ??= 'ann_index.bin';

  return BuildConfig(
    imagesDir: imagesDir,
    outputPath: outputPath,
    imageModelPath: imageModelPath,
    textModelPath: textModelPath,
    tokenizerPath: tokenizerPath,
    m: m,
    efConstruction: efConstruction,
  );
}

/// Print usage information
void _printUsage() {
  print('');
  print('Usage: dart run tools/build_index.dart [options]');
  print('');
  print('Required:');
  print('  --images, -i <path>    Directory containing images to index');
  print('');
  print('Optional:');
  print('  --output, -o <path>    Output index file (default: ann_index.bin)');
  print('  --image-model <path>   Image encoder TFLite model');
  print('  --text-model <path>    Text encoder TFLite model');
  print('  --tokenizer <path>     Tokenizer JSON file');
  print('  --m <int>              HNSW M parameter (default: 16)');
  print('  --ef <int>             HNSW efConstruction (default: 200)');
  print('  --help, -h             Show this help');
  print('');
  print('Example:');
  print('  dart run tools/build_index.dart \\');
  print('    --images ./my_photos \\');
  print('    --output ./assets/index/ann_index.bin');
}

/// Find all image files in a directory (recursive)
List<String> _findImages(String directory) {
  final images = <String>[];
  final extensions = ['.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'];

  final dir = Directory(directory);
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final ext = entity.path.toLowerCase();
      if (extensions.any((e) => ext.endsWith(e))) {
        images.add(entity.path);
      }
    }
  }

  images.sort();
  return images;
}
