import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/search_models.dart';

/// Service for loading and managing device images from the photo gallery.
class ImageLoaderService {
  final List<ImageItem> _imageCache = [];

  /// assetId → resolved File (populated by [loadDeviceImages]).
  final Map<String, File> _fileCache = {};

  bool _isInitialized = false;
  bool _hasPermission = false;

  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  /// Request photo library permission. Always succeeds — permission denied
  /// just means an empty gallery, not a hard failure.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final result = await PhotoManager.requestPermissionExtend();
      _hasPermission = result.hasAccess;
      if (!_hasPermission) {
        debugPrint('ImageLoaderService: Photo permission not granted');
      }
    } catch (e) {
      debugPrint('ImageLoaderService: Permission request failed: $e');
    }
    _isInitialized = true;
    return true;
  }

  /// Load all images from the device gallery.
  ///
  /// File paths are resolved eagerly in batches so [ImageItem.path] is
  /// immediately usable by [Image.file]. On Android, this just creates File
  /// objects pointing to existing media-store paths — it is fast even for
  /// large galleries. Returns cached list on subsequent calls.
  Future<List<ImageItem>> loadDeviceImages() async {
    if (!_isInitialized) {
      throw StateError(
        'ImageLoaderService not initialized. Call initialize() first.',
      );
    }
    if (_imageCache.isNotEmpty) return List.unmodifiable(_imageCache);
    if (!_hasPermission) {
      debugPrint('ImageLoaderService: No photo permission — gallery is empty');
      return const [];
    }

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        debugPrint('ImageLoaderService: No image albums found');
        return const [];
      }

      final allAlbum = albums.first;
      final count = await allAlbum.assetCountAsync;
      if (count == 0) {
        debugPrint('ImageLoaderService: Gallery is empty');
        return const [];
      }

      const maxImages = 5000;
      final assets = await allAlbum.getAssetListRange(
        start: 0,
        end: count.clamp(0, maxImages),
      );

      // Resolve file paths in batches to avoid spawning thousands of futures.
      const batchSize = 50;
      int resolved = 0;
      for (var i = 0; i < assets.length; i += batchSize) {
        final batch = assets.sublist(
          i,
          (i + batchSize).clamp(0, assets.length),
        );
        final files = await Future.wait(batch.map((a) => a.file));
        for (var j = 0; j < batch.length; j++) {
          final asset = batch[j];
          final file = files[j];
          if (file == null) continue;
          if (!isImageSupported(file.path)) continue;
          _fileCache[asset.id] = file;
          _imageCache.add(ImageItem(
            id: asset.id,
            path: file.path,
            createdAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            width: asset.width,
            height: asset.height,
          ));
          resolved++;
        }
      }

      debugPrint('ImageLoaderService: Loaded $resolved images from gallery');
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load gallery: $e');
    }

    return List.unmodifiable(_imageCache);
  }

  Future<Uint8List?> loadThumbnail(String imageId) async {
    final file = _fileCache[imageId];
    if (file == null) return null;
    try {
      return await file.readAsBytes();
    } catch (e) {
      debugPrint(
          'ImageLoaderService: Failed to load thumbnail for $imageId: $e');
      return null;
    }
  }

  /// Loads an image pre-downscaled to at most 512×512 RGBA using the
  /// platform JPEG decoder, avoiding the ~48 MB buffer cost of decoding
  /// a full-resolution phone photo before the 224×224 model resize.
  Future<({Uint8List rgba, int width, int height})?> loadResizedForEmbedding(
      String imageId) async {
    final file = _fileCache[imageId];
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 512,
        targetHeight: 512,
      );
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (byteData == null) return null;
      return (rgba: byteData.buffer.asUint8List(), width: w, height: h);
    } catch (e) {
      debugPrint(
          'ImageLoaderService: Failed to load resized image for $imageId: $e');
      return null;
    }
  }

  Future<Uint8List?> loadImageBytes(String imageId) async {
    final file = _fileCache[imageId];
    if (file == null) {
      debugPrint('ImageLoaderService: Image not found for $imageId');
      return null;
    }
    try {
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load image for $imageId: $e');
      return null;
    }
  }

  Future<ImageItem> getImageWithThumbnail(String imageId) async {
    final image = getImageById(imageId);
    if (image == null) {
      throw StateError('Image not found: $imageId');
    }
    if (image.thumbnail != null) return image;

    final thumbnail = await loadThumbnail(imageId);
    if (thumbnail == null) return image;

    final updated = image.copyWith(thumbnail: thumbnail);
    final i = _imageCache.indexWhere((img) => img.id == imageId);
    if (i >= 0) _imageCache[i] = updated;
    return updated;
  }

  Future<List<ImageItem>> refreshImages() async {
    _imageCache.clear();
    _fileCache.clear();
    return loadDeviceImages();
  }

  ImageItem? getImageById(String id) {
    try {
      return _imageCache.firstWhere((image) => image.id == id);
    } catch (_) {
      return null;
    }
  }

  List<ImageItem> getAllImages() => List.unmodifiable(_imageCache);

  bool isImageSupported(String path) {
    final lower = path.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  void clearCache() {
    _imageCache.clear();
    _fileCache.clear();
  }

  /// Drop only the in-memory thumbnail bytes attached to cached items, but
  /// keep the [ImageItem] metadata and (id → File) map intact so search
  /// and gallery rendering keep working. The next render of a thumbnail
  /// will re-read from disk.
  int clearThumbnailBytes() {
    int cleared = 0;
    for (var i = 0; i < _imageCache.length; i++) {
      final item = _imageCache[i];
      if (item.thumbnail != null) {
        _imageCache[i] = ImageItem(
          id: item.id,
          path: item.path,
          createdAt: item.createdAt,
          modifiedAt: item.modifiedAt,
          sizeBytes: item.sizeBytes,
          width: item.width,
          height: item.height,
        );
        cleared++;
      }
    }
    if (cleared > 0) {
      debugPrint('ImageLoaderService: Cleared $cleared thumbnail buffers');
    }
    return cleared;
  }

  void dispose() {
    clearCache();
    _isInitialized = false;
  }
}
