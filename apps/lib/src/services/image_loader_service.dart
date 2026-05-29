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

  // -- Image source toggle ----------------------------------------------------
  // Full device gallery  →  static const String? _kTestAlbum = null;
  // personal_1k dataset  →  static const String? _kTestAlbum = 'personal_1k';
  // --------------------------------------------------------------------------
  static const String? _kTestAlbum = 'personal_1k';

  /// Album the in-app camera writes new captures into.
  ///
  /// Mirrors [_kTestAlbum] so test-build captures land in the same folder the
  /// loader is reading from (otherwise the photo would save successfully but
  /// never appear in Kitako's index). In production builds where the loader
  /// reads the full gallery, this defaults to a Kitako-branded album so the
  /// user can find their Kitako-captured photos as a distinct group.
  static const String kCaptureAlbumName = _kTestAlbum ?? 'Kitako';

  /// Relative path passed to `PhotoManager.editor.saveImageWithPath` —
  /// translates to `/sdcard/DCIM/<album>/` on Android.
  static const String kCaptureRelativePath = 'DCIM/$kCaptureAlbumName';

  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
    '.heic',
    '.heif',
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

      // Load the full "All Photos" album sorted newest-first.
      // If _kTestAlbum is set we post-filter by relativePath after loading,
      // which is more reliable than matching album names in MediaStore.
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );

      if (albums.isEmpty || await albums.first.assetCountAsync == 0) {
        debugPrint('ImageLoaderService: "All Photos" album empty — '
            'trying individual albums');
        final individual = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          hasAll: false,
          onlyAll: false,
          filterOption: FilterOptionGroup(
            orders: [
              const OrderOption(type: OrderOptionType.createDate, asc: false),
            ],
          ),
        );
        if (individual.isEmpty) {
          debugPrint('ImageLoaderService: No photo albums found on device');
          _isInitialized = true;
          return true;
        }
        // Merge assets from all individual albums (deduplicated by asset ID).
        for (final album in individual) {
          final count = await album.assetCountAsync;
          if (count == 0) continue;
          debugPrint('ImageLoaderService: Scanning album "${album.name}" '
              '($count images)');
          const pageSize = 200;
          for (int start = 0; start < count; start += pageSize) {
            final end = (start + pageSize).clamp(0, count).toInt();
            final assets =
                await album.getAssetListRange(start: start, end: end);
            for (final asset in assets) {
              _assetCache.putIfAbsent(asset.id, () => asset);
            }
          }
        }
        if (_assetCache.isNotEmpty) {
          debugPrint('ImageLoaderService: Individual album scan found '
              '${_assetCache.length} images');
          _isInitialized = true;
          return true;
        }
        debugPrint('ImageLoaderService: All albums empty');
        _isInitialized = true;
        return true;
      }

      // -- Pick source album ------------------------------------------------
      // Prefer matching by album name (works on all Android versions); fall
      // back to the full "All Photos" album if the test album isn't found.
      AssetPathEntity? sourceAlbum;

      if (_kTestAlbum != null) {
        final specific = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          hasAll: false,
          onlyAll: false,
          filterOption: FilterOptionGroup(
            orders: [
              const OrderOption(type: OrderOptionType.createDate, asc: false),
            ],
          ),
        );

        // Log every album name so we can see exactly what MediaStore reports.
        debugPrint('ImageLoaderService: ${specific.length} album(s) on device:');
        for (final a in specific) {
          final n = await a.assetCountAsync;
          debugPrint('  • "${a.name}" ($n images)');
        }

        final target = _kTestAlbum!.toLowerCase();
        sourceAlbum = specific
            .where((a) => a.name.toLowerCase() == target)
            .firstOrNull;
        sourceAlbum ??= specific
            .where((a) => a.name.toLowerCase().contains(target))
            .firstOrNull;

        if (sourceAlbum != null) {
          debugPrint(
              'ImageLoaderService: Using test album "${sourceAlbum.name}"');
        } else {
          debugPrint(
              'ImageLoaderService: Test album "$_kTestAlbum" not found by name '
              '— will load full gallery and filter by relativePath');
        }
      }

      sourceAlbum ??= albums.first;
      final count = await sourceAlbum.assetCountAsync;
      debugPrint('ImageLoaderService: Source "${sourceAlbum.name}" has $count images');

      // Load assets in pages to avoid OOM on large galleries.
      const pageSize = 200;
      for (int start = 0; start < count; start += pageSize) {
        final end = (start + pageSize).clamp(0, count).toInt();
        final assets =
            await sourceAlbum.getAssetListRange(start: start, end: end);
        for (final asset in assets) {
          _assetCache[asset.id] = asset;
        }
      }

      // If the album lookup fell through to the full gallery, post-filter by
      // relativePath as a second line of defence.
      if (_kTestAlbum != null && sourceAlbum.name != _kTestAlbum) {
        // Diagnostic: sample relativePath of first few assets so we can see
        // what photo_manager is actually surfacing.
        final sample = _assetCache.values.take(5).toList();
        for (final a in sample) {
          debugPrint('  sample relativePath: "${a.relativePath}"');
        }

        final before = _assetCache.length;
        _assetCache.removeWhere(
          (_, asset) => !(asset.relativePath?.contains(_kTestAlbum!) ?? false),
        );
        debugPrint(
          'ImageLoaderService: relativePath filter kept ${_assetCache.length} '
          'of $before images',
        );
      }

      debugPrint('ImageLoaderService: Indexed ${_assetCache.length} images');
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

  /// Inject a freshly-captured asset into the loader's caches without going
  /// through a full MediaStore re-enumeration.
  ///
  /// Called after the in-app camera saves a new photo: the resulting
  /// [AssetEntity] is resolved to an [ImageItem] and prepended to the cache
  /// so subsequent calls to [loadDeviceImages] / [getAllImages] include it.
  /// Returns the resolved item, or `null` if resolution failed (rare — only
  /// happens if the asset's underlying file is gone).
  Future<ImageItem?> addAsset(AssetEntity asset) async {
    // Avoid duplicates if the caller invokes us twice for the same capture.
    if (_assetCache.containsKey(asset.id)) {
      try {
        return _imageCache.firstWhere((img) => img.id == asset.id);
      } catch (_) {
        // Fall through to re-resolve.
      }
    }

    final resolved = await _resolveAssets([asset]);
    if (resolved.isEmpty) {
      debugPrint('ImageLoaderService: addAsset failed to resolve ${asset.id}');
      return null;
    }

    final item = resolved.first;
    _assetCache[asset.id] = asset;
    // Prepend so the new photo appears at the top of newest-first views.
    _imageCache.insert(0, item);
    debugPrint('ImageLoaderService: addAsset injected ${asset.id} '
        '(cache now ${_imageCache.length})');
    return item;
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

  /// Scan a user-chosen directory for image files and add them to the cache.
  /// Returns the number of new images found.
  Future<int> loadImagesFromDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;

    int added = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isImageSupported(entity.path)) continue;

      final id = 'dir_${entity.path.hashCode}';
      if (_assetCache.containsKey(id) ||
          _imageCache.any((img) => img.id == id)) {
        continue;
      }

      try {
        final stat = await entity.stat();
        final item = ImageItem(
          id: id,
          path: entity.path,
          createdAt: stat.changed,
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        );
        _imageCache.add(item);
        added++;
      } catch (e) {
        debugPrint('ImageLoaderService: Skipped ${entity.path}: $e');
      }
    }

    debugPrint('ImageLoaderService: Directory scan found $added new images '
        'in $dirPath');
    return added;
  }

  void dispose() {
    clearCache();
    _isInitialized = false;
  }
}
