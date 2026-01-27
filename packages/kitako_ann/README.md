# kitako_ann

HNSW-based Approximate Nearest Neighbor (ANN) search for KitaKo on-device multimodal image retrieval.

## Features

- **Fast ANN search** using HNSW algorithm
- **On-device execution** - no server calls required
- **Native performance** via FFI bridge to C++ implementation
- **Easy to use** high-level Dart API
- **Cross-platform** - Android, iOS, macOS, Windows, Linux
- **Web fallback** - brute-force search for web platform

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  kitako_ann:
    path: ../packages/kitako_ann
```

## Quick Start

```dart
import 'package:kitako_ann/kitako_ann.dart';

// Initialize the search service
final service = AnnSearchService();
await service.initialize(
  indexPath: '/path/to/index.bin',
  config: AnnClientConfig.siglip768,
);

// Search for similar items
final queryEmbedding = Float32List(768); // Your 768-dim embedding
final results = await service.search(queryEmbedding, k: 10);

for (final result in results) {
  print('ID: ${result.id}, Similarity: ${result.similarity}');
}

// Clean up
service.dispose();
```

## Using with Flutter Assets

```dart
// For indexes bundled as Flutter assets
final indexManager = IndexManager(
  assetPath: 'assets/index/ann_index.bin',
  metadataAssetPath: 'assets/index/ann_index.meta.json',
);

final service = AnnSearchService();
await service.initializeWithManager(indexManager: indexManager);
```

## Configuration

```dart
// Custom configuration
const config = AnnClientConfig(
  dimension: 768,                    // Embedding dimension
  spaceType: AnnSpaceType.innerProduct, // Distance metric
  defaultEfSearch: 100,              // Search accuracy
);
```

## Building Indexes

```dart
final client = LocalAnnClient(config: AnnClientConfig.siglip768);

final embeddings = <int, Float32List>{
  0: embedding0,
  1: embedding1,
  // ...
};

await client.buildIndex(embeddings, M: 16, efConstruction: 200);
await client.saveIndex('/path/to/output.bin');
client.dispose();
```

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │───▶│   kitako_ann     │───▶│   kitako_ffi    │
│                 │    │  (Dart API)      │    │  (FFI Bridge)   │
└─────────────────┘    └──────────────────┘    └────────┬────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │  Native C++     │
                                               │  (hnswlib)      │
                                               └─────────────────┘
```

## HNSW Parameters

| Parameter | Description | Recommended |
|-----------|-------------|-------------|
| `M` | Max connections per node | 16-48 |
| `efConstruction` | Build-time search quality | 100-200 |
| `efSearch` | Query-time search quality | 50-200 |
| `dimension` | Embedding dimension | 768 (SigLIP) |

Higher `M` and `efConstruction` improve recall but increase index size and build time.
Higher `efSearch` improves query recall but slows queries.

## License

MIT License - see [LICENSE](LICENSE) for details.
