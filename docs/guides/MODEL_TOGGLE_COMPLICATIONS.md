# Model Toggle Integration Guide

## ⚠️ Important: Complications When Switching Models

### The Core Problem

When you switch between SigLIP-1 and SigLIP-2, **all image embeddings become invalid** because:

1. **Different embedding spaces**: SigLIP-1 (224×224) and SigLIP-2 (256×256) produce embeddings in different vector spaces
2. **Not comparable**: You cannot compare a SigLIP-1 text embedding with a SigLIP-2 image embedding
3. **Must re-index**: All 1000 image embeddings need to be regenerated

### What Happens When You Toggle

```
User toggles SigLIP-1 → SigLIP-2
   ↓
Text queries now use SigLIP-2 embeddings
   ↓
Image embeddings are still SigLIP-1
   ↓
❌ Search returns garbage results (comparing apples to oranges)
   ↓
✅ Must re-index all images with SigLIP-2
   ↓
⏱️ Takes ~2-3 minutes for 1000 images
```

## 🎯 Solutions

### Option 1: Simple Toggle with Re-indexing Warning (Recommended)

Add a dialog that warns the user and triggers re-indexing:

```dart
// Add to SettingsScreen
Future<void> _switchModel(SiglipModelVersion newVersion) async {
  // Show warning dialog
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Switch Model?'),
      content: const Text(
        'Switching models will require re-indexing all images.\n\n'
        'This may take 2-3 minutes.\n\n'
        'Search will not work until re-indexing completes.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Switch & Re-index'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Switching model and re-indexing images...'),
        ],
      ),
    ),
  );

  try {
    // Switch model
    await widget.searchService.embeddingService.switchToModel(newVersion);
    
    // Re-index all images
    await widget.searchService.reindexAllImages();
    
    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      
      // Show success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${newVersion.name}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to switch: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

### Option 2: No Runtime Toggle (Safest)

Make model selection a **startup choice only**:

```dart
// In StartupScreen or initial setup
final modelVersion = await showDialog<SiglipModelVersion>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Select Model'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: const Text('SigLIP-1 (Faster)'),
          subtitle: const Text('224×224, 32K vocab'),
          onTap: () => Navigator.pop(context, SiglipModelVersion.siglip1),
        ),
        ListTile(
          title: const Text('SigLIP-2 (Better)'),
          subtitle: const Text('256×256, 256K vocab'),
          onTap: () => Navigator.pop(context, SiglipModelVersion.siglip2),
        ),
      ],
    ),
  ),
);

// Initialize with chosen model
await searchService.initializeWithModel(modelVersion);
```

### Option 3: Advanced Settings with Cache

Keep separate embedding caches for each model (memory intensive):

```dart
class ImageSearchService {
  Map<String, List<double>> _siglip1Embeddings = {};
  Map<String, List<double>> _siglip2Embeddings = {};
  
  Future<void> switchModel(SiglipModelVersion version) async {
    await _embeddingService.switchToModel(version);
    
    // Use cached embeddings if available
    if (version == SiglipModelVersion.siglip1) {
      if (_siglip1Embeddings.isEmpty) {
        await reindexAllImages(); // First time
      } else {
        _annSearch.setEmbeddings(_siglip1Embeddings);
      }
    } else {
      if (_siglip2Embeddings.isEmpty) {
        await reindexAllImages(); // First time
      } else {
        _annSearch.setEmbeddings(_siglip2Embeddings);
      }
    }
  }
}
```

## 🛠️ Implementation Choice

**I recommend Option 1** for your use case because:
- ✅ Allows testing both models
- ✅ Clear about consequences
- ✅ Automatic re-indexing
- ✅ User understands the wait

## 📝 Code Changes Needed

### 1. Add `reindexAllImages()` to ImageSearchService

```dart
// In image_search_service.dart
Future<void> reindexAllImages() async {
  debugPrint('ImageSearchService: Re-indexing all images...');
  
  // Clear existing embeddings
  await _annSearch.clear();
  
  // Re-index with new model
  await _indexDeviceImages();
  
  debugPrint('ImageSearchService: Re-indexing complete');
}
```

### 2. Expose embeddingService in ImageSearchService

```dart
// In image_search_service.dart
EmbeddingService get embeddingService => _embeddingService;
```

### 3. Add Toggle to Settings Screen

See the complete implementation below.

## ⚙️ Complete Settings Screen Integration

Save this as your new `settings_screen.dart`:

