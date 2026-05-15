import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/search_models.dart';

/// Service for loading and managing device images from the real photo gallery.
///
/// Uses [photo_manager] to enumerate all images on the device. Permissions are
/// requested on [initialize]. Image IDs are the stable asset IDs provided by
/// the platform photo library.
class ImageLoaderService {
  /// All loaded images across the device gallery.
  final List<ImageItem> _imageCache = [];

  /// asset ID → AssetEntity (kept for efficient thumbnail generation).
  final Map<String, AssetEntity> _assetCache = {};

  bool _isInitialized = false;

  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  /// Initialize: request permission and enumerate all gallery images.
  /// Returns `true` if permission was granted, `false` if denied.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final PermissionState ps =
          await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        debugPrint('ImageLoaderService: Photo library access denied');
        _isInitialized = true;
        return false;
      }

      // Get the "all images" album sorted newest-first at the platform level.
      // OrderOption on createDate (asc: false) means page 0 contains the most
      // recently created images — so the first 200 assets loaded are today's
      // photos, and the gallery renders the correct date sections immediately
      // without any secondary sort in the UI layer.
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(
              type: OrderOptionType.createDate,
              asc: false,
            ),
          ],
        ),
      );

      if (albums.isEmpty) {
        debugPrint('ImageLoaderService: No photo albums found on device');
        _isInitialized = true;
        return true;
      }

      final allAlbum = albums.first;
      final count = await allAlbum.assetCountAsync;
      debugPrint('ImageLoaderService: Device gallery has $count images');

      // Load assets in pages to avoid OOM on large galleries.
      const pageSize = 200;
      int loaded = 0;
      for (int start = 0; start < count; start += pageSize) {
        final end = (start + pageSize).clamp(0, count);
        final assets =
            await allAlbum.getAssetListRange(start: start, end: end);
        for (final asset in assets) {
          _assetCache[asset.id] = asset;
        }
        loaded += assets.length;
      }

      debugPrint('ImageLoaderService: Indexed $loaded images from gallery');
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to initialize: $e');
    }

    _isInitialized = true;
    return true;
  }

  /// Resolves a list of [AssetEntity] objects into [ImageItem]s concurrently.
  /// All assets in the batch are resolved in parallel to minimise platform-
  /// channel round-trip latency.
  Future<List<ImageItem>> _resolveAssets(List<AssetEntity> assets) async {
    final results = await Future.wait(
      assets.map((asset) async {
        try {
          final file = await asset.file;
          if (file == null || !isImageSupported(file.path)) return null;
          return ImageItem(
            id: asset.id,
            path: file.path,
            createdAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            sizeBytes: await file.length(),
            width: asset.width,
            height: asset.height,
          );
        } catch (e) {
          debugPrint('ImageLoaderService: Skipped asset ${asset.id}: $e');
          return null;
        }
      }),
    );
    return results.whereType<ImageItem>().toList();
  }

  /// Load all images from the device gallery as [ImageItem] objects.
  ///
  /// File paths and metadata are resolved in parallel on first call and cached.
  Future<List<ImageItem>> loadDeviceImages() async {
    if (!_isInitialized) {
      throw StateError(
          'ImageLoaderService not initialized. Call initialize() first.');
    }
    if (_imageCache.isNotEmpty) return List.unmodifiable(_imageCache);

    final resolved = await _resolveAssets(_assetCache.values.toList());
    _imageCache.addAll(resolved);

    debugPrint('ImageLoaderService: Loaded ${_imageCache.length} images');
    return List.unmodifiable(_imageCache);
  }

  /// Loads images progressively, calling [onBatch] with the growing cumulative
  /// list after each batch resolves. Batch schedule: 50 → 100 → 200 → 200…
  ///
  /// Because assets are pre-sorted newest-first, the very first batch contains
  /// today's photos and the gallery is usable in milliseconds.
  Future<void> loadDeviceImagesProgressive({
    required void Function(List<ImageItem> cumulative) onBatch,
  }) async {
    if (!_isInitialized) {
      throw StateError(
          'ImageLoaderService not initialized. Call initialize() first.');
    }
    if (_imageCache.isNotEmpty) {
      onBatch(List.unmodifiable(_imageCache));
      return;
    }

    // Batch sizes: small first so the grid renders quickly, then larger
    // to amortise the overhead of multiple round-trips.
    const batchSchedule = [50, 100, 200];
    const defaultBatch  = 200;

    final allAssets = _assetCache.values.toList();
    int cursor   = 0;
    int batchIdx = 0;

    while (cursor < allAssets.length) {
      final batchSize = batchIdx < batchSchedule.length
          ? batchSchedule[batchIdx]
          : defaultBatch;
      final end     = (cursor + batchSize).clamp(0, allAssets.length);
      final batch   = allAssets.sublist(cursor, end);
      final resolved = await _resolveAssets(batch);
      _imageCache.addAll(resolved);
      onBatch(List.unmodifiable(_imageCache));
      cursor   = end;
      batchIdx++;
    }

    debugPrint(
        'ImageLoaderService: Progressive load complete — ${_imageCache.length} images');
  }

  /// Loads an image pre-downscaled to at most 512×512 RGBA via the platform
  /// JPEG decoder (DCT scaling), avoiding the ~48 MB buffer cost of a
  /// full-resolution decode before the 224×224 model resize.
  Future<({Uint8List rgba, int width, int height})?> loadResizedForEmbedding(
      String imageId) async {
    final item = getImageById(imageId);
    if (item == null) return null;
    try {
      final bytes = await File(item.path).readAsBytes();
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

  Future<Uint8List?> loadThumbnail(String imageId) async {
    final asset = _assetCache[imageId];
    if (asset == null) return null;
    try {
      return await asset.thumbnailDataWithSize(
          const ThumbnailSize(256, 256));
    } catch (e) {
      debugPrint(
          'ImageLoaderService: Failed to load thumbnail for $imageId: $e');
      return null;
    }
  }

  Future<Uint8List?> loadImageBytes(String imageId) async {
    final item = getImageById(imageId);
    if (item == null) {
      debugPrint('ImageLoaderService: Image not found for $imageId');
      return null;
    }
    try {
      return await File(item.path).readAsBytes();
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load image for $imageId: $e');
      return null;
    }
  }

  Future<ImageItem> getImageWithThumbnail(String imageId) async {
    final image = getImageById(imageId);
    if (image == null) throw StateError('Image not found: $imageId');
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
    _assetCache.clear();
  }

  /// Drop in-memory thumbnail bytes while keeping metadata and asset refs
  /// intact. Called on Android memory pressure.
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
      debugPrint(
          'ImageLoaderService: Cleared $cleared thumbnail buffers');
    }
    return cleared;
  }

  void dispose() {
    clearCache();
    _isInitialized = false;
  }
}
