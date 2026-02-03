import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/search_models.dart';

/// Service for loading and managing device images
///
/// This service handles:
/// - Loading images from device storage using photo_manager
/// - Caching image metadata
/// - Managing image permissions
/// - Graceful fallback to mock data if permissions denied
/// - Optimized thumbnail loading for faster embedding
/// - Parallel batch processing for improved performance
///
/// Example usage:
/// ```dart
/// final imageLoader = ImageLoaderService();
/// await imageLoader.initialize();
/// final images = await imageLoader.loadDeviceImages();
///
/// // Fast thumbnail loading for embedding
/// final thumbnails = await imageLoader.loadThumbnailBatch(images.take(10).toList());
/// ```
class ImageLoaderService {
  /// Cache of loaded images
  final List<ImageItem> _imageCache = [];

  /// Cache of AssetEntity objects for getting bytes (Android scoped storage)
  final Map<String, AssetEntity> _assetCache = {};

  /// Cache of thumbnail bytes for fast re-access
  final Map<String, Uint8List> _thumbnailCache = {};

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Thumbnail size for embedding (matches SigLIP input size)
  static const int thumbnailSize = 224;

  /// Default parallel batch size
  static const int defaultBatchSize = 5;

  /// Maximum thumbnail cache size (in number of images)
  static const int maxThumbnailCacheSize = 100;

  /// Supported image file extensions
  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  /// Initialize the image loader service
  ///
  /// This should be called before using any other methods.
  /// It requests gallery permissions and prepares the image cache.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('ImageLoaderService: Requesting gallery permissions...');

      // Request storage permissions with explicit request
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          iosAccessLevel: IosAccessLevel.readWrite,
        ),
      );

      debugPrint('ImageLoaderService: Permission state - isAuth: ${ps.isAuth}, hasAccess: ${ps.hasAccess}');

      // Accept both isAuth and hasAccess (for limited access on iOS/Android 13+)
      if (ps.isAuth || ps.hasAccess) {
        _isInitialized = true;
        debugPrint('ImageLoaderService: ✓ Initialized with gallery access');
        return true;
      } else {
        debugPrint('ImageLoaderService: ⚠️  Permission denied');
        debugPrint('  - Permission state: ${ps.toString()}');
        debugPrint('  - isAuth: ${ps.isAuth}');
        debugPrint('  - hasAccess: ${ps.hasAccess}');
        debugPrint('  - Will use mock data');

        // Still mark as initialized to allow mock fallback
        _isInitialized = true;
        return true;
      }
    } catch (e, stackTrace) {
      debugPrint('ImageLoaderService: Failed to initialize: $e');
      debugPrint('Stack trace: $stackTrace');
      // Mark as initialized anyway to allow mock fallback
      _isInitialized = true;
      return true;
    }
  }

  /// Load all images from device storage
  ///
  /// Returns a list of [ImageItem] objects representing REAL images on the device.
  /// Falls back to mock data only if:
  /// - Permissions are denied
  /// - No images are found
  /// - An error occurs
  ///
  /// Images are cached for subsequent calls.
  ///
  /// Throws [StateError] if service is not initialized
  Future<List<ImageItem>> loadDeviceImages() async {
    if (!_isInitialized) {
      throw StateError(
        'ImageLoaderService not initialized. Call initialize() first.',
      );
    }

    // Return cached images if available
    if (_imageCache.isNotEmpty) {
      return List.unmodifiable(_imageCache);
    }

    try {
      // Check permission
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          iosAccessLevel: IosAccessLevel.readWrite,
        ),
      );

      debugPrint('ImageLoaderService: Checking permission - isAuth: ${ps.isAuth}, hasAccess: ${ps.hasAccess}');

      // Accept both isAuth and hasAccess
      if (!ps.isAuth && !ps.hasAccess) {
        debugPrint('ImageLoaderService: No permission granted, using mock data');
        debugPrint('  - Please grant photo permissions in device settings');
        _imageCache.addAll(_generateMockImages(9));
        return List.unmodifiable(_imageCache);
      }

      // Get image albums
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,  // Get only the "All" album
      );

      if (albums.isEmpty) {
        debugPrint('ImageLoaderService: No albums found, using mock data');
        _imageCache.addAll(_generateMockImages(9));
        return List.unmodifiable(_imageCache);
      }

      // Get images from first album (usually "All Photos")
      final AssetPathEntity album = albums.first;
      final int totalCount = await album.assetCountAsync;

      debugPrint('ImageLoaderService: Found $totalCount images in gallery');

      if (totalCount == 0) {
        debugPrint('ImageLoaderService: No images found, using mock data');
        _imageCache.addAll(_generateMockImages(9));
        return List.unmodifiable(_imageCache);
      }

      // Load up to 1000 images
      final int loadCount = totalCount < 1000 ? totalCount : 1000;
      final stopwatch = Stopwatch()..start();

      final List<AssetEntity> assets = await album.getAssetListRange(
        start: 0,
        end: loadCount,
      );

      debugPrint('ImageLoaderService: Fetched ${assets.length} asset references in ${stopwatch.elapsedMilliseconds}ms');

      // OPTIMIZED: Convert AssetEntity to ImageItem WITHOUT file copy
      // This is much faster as it uses metadata directly from MediaStore
      for (final asset in assets) {
        try {
          // Use metadata directly - no file copy needed!
          // Note: sizeBytes is skipped to avoid slow file access
          final imageItem = ImageItem(
            id: asset.id,
            path: asset.relativePath ?? 'gallery/${asset.id}',
            createdAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            sizeBytes: null, // Skip for speed - can be fetched lazily if needed
            width: asset.width,
            height: asset.height,
          );

          _imageCache.add(imageItem);
          // Cache the asset for later byte retrieval
          _assetCache[asset.id] = asset;
        } catch (e) {
          debugPrint('ImageLoaderService: Error loading asset ${asset.id}: $e');
          continue;
        }
      }

      stopwatch.stop();
      debugPrint('ImageLoaderService: ✓ Loaded ${_imageCache.length} REAL images in ${stopwatch.elapsedMilliseconds}ms (optimized)');

      // If we couldn't load any real images, fall back to mock
      if (_imageCache.isEmpty) {
        debugPrint('ImageLoaderService: Failed to load any real images, using mock data');
        _imageCache.addAll(_generateMockImages(9));
      }

      return List.unmodifiable(_imageCache);
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load images: $e');

      // Fall back to mock data
      _imageCache.addAll(_generateMockImages(9));
      return List.unmodifiable(_imageCache);
    }
  }

  /// Refresh the image cache
  ///
  /// Forces a reload of all images from device storage.
  /// Useful when new images have been added or removed.
  Future<List<ImageItem>> refreshImages() async {
    _imageCache.clear();
    return loadDeviceImages();
  }

  /// Get a single image by ID
  ///
  /// Returns the [ImageItem] if found, or `null` if not found
  ImageItem? getImageById(String id) {
    try {
      return _imageCache.firstWhere((image) => image.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get all loaded images
  ///
  /// Returns a list of all images currently in the cache.
  /// If no images are loaded, returns an empty list.
  List<ImageItem> getAllImages() {
    return List.unmodifiable(_imageCache);
  }

  /// Check if an image file is supported
  ///
  /// Returns `true` if the file extension is in the supported list
  bool isImageSupported(String path) {
    final extension = path.toLowerCase();
    return _supportedExtensions.any((ext) => extension.endsWith(ext));
  }

  /// Get the raw bytes of an image
  ///
  /// This uses photo_manager's API to get bytes, which works correctly
  /// on Android 10+ with scoped storage (unlike direct File access).
  ///
  /// Returns null if the image is not found or bytes cannot be retrieved.
  Future<Uint8List?> getImageBytes(ImageItem image) async {
    // First try to get from cached AssetEntity (real gallery images)
    final asset = _assetCache[image.id];
    if (asset != null) {
      try {
        final bytes = await asset.originBytes;
        if (bytes != null) {
          debugPrint('ImageLoaderService: Got ${bytes.length} bytes for ${image.name}');
          return bytes;
        }
      } catch (e) {
        debugPrint('ImageLoaderService: Failed to get bytes via asset: $e');
      }
    }

    // Fallback: try direct file read (works on some platforms/older Android)
    try {
      final file = File(image.path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to get bytes via file: $e');
    }

    return null;
  }

  /// Get thumbnail bytes for an image (FAST - optimized for embedding)
  ///
  /// This loads a small thumbnail (224x224) instead of the full image,
  /// which is 10-50x faster than loading the full resolution image.
  ///
  /// The thumbnail is cached for subsequent calls.
  ///
  /// Returns null if the image is not found or thumbnail cannot be retrieved.
  Future<Uint8List?> getThumbnailBytes(ImageItem image) async {
    // Check cache first
    if (_thumbnailCache.containsKey(image.id)) {
      return _thumbnailCache[image.id];
    }

    final asset = _assetCache[image.id];
    if (asset == null) {
      debugPrint('ImageLoaderService: Asset not found for ${image.id}');
      return null;
    }

    try {
      // Load thumbnail at model input size (224x224)
      // This is MUCH faster than loading full resolution
      final thumbnail = await asset.thumbnailDataWithSize(
        const ThumbnailSize(thumbnailSize, thumbnailSize),
        quality: 85,
      );

      if (thumbnail != null) {
        // Cache the thumbnail (with LRU eviction)
        _cacheThumbnail(image.id, thumbnail);
        debugPrint('ImageLoaderService: Got ${thumbnail.length} byte thumbnail for ${image.id}');
      }

      return thumbnail;
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to get thumbnail: $e');
      return null;
    }
  }

  /// Load thumbnails for multiple images in parallel (FAST)
  ///
  /// This is the fastest way to load images for embedding.
  /// It uses parallel processing and thumbnails instead of full images.
  ///
  /// [images] - List of images to load thumbnails for
  /// [batchSize] - Number of images to load concurrently (default: 5)
  /// [onProgress] - Optional callback for progress updates
  ///
  /// Returns a map of image ID to thumbnail bytes.
  /// Images that fail to load will not be in the map.
  Future<Map<String, Uint8List>> loadThumbnailBatch(
    List<ImageItem> images, {
    int batchSize = defaultBatchSize,
    void Function(int loaded, int total)? onProgress,
  }) async {
    final results = <String, Uint8List>{};
    final stopwatch = Stopwatch()..start();

    debugPrint('ImageLoaderService: Loading ${images.length} thumbnails in batches of $batchSize...');

    // Process in parallel batches
    for (var i = 0; i < images.length; i += batchSize) {
      final batchEnd = (i + batchSize).clamp(0, images.length);
      final batch = images.sublist(i, batchEnd);

      // Load batch in parallel
      final futures = batch.map((image) async {
        final thumbnail = await getThumbnailBytes(image);
        if (thumbnail != null) {
          return MapEntry(image.id, thumbnail);
        }
        return null;
      });

      final batchResults = await Future.wait(futures);

      // Collect results
      for (final entry in batchResults) {
        if (entry != null) {
          results[entry.key] = entry.value;
        }
      }

      // Report progress
      onProgress?.call(results.length, images.length);
    }

    stopwatch.stop();
    debugPrint(
      'ImageLoaderService: ✓ Loaded ${results.length}/${images.length} thumbnails '
      'in ${stopwatch.elapsedMilliseconds}ms '
      '(${(stopwatch.elapsedMilliseconds / images.length).toStringAsFixed(1)}ms/image)',
    );

    return results;
  }

  /// Load thumbnails and return as a list matching input order
  ///
  /// This is convenient for batch embedding where order matters.
  /// Returns null entries for images that failed to load.
  Future<List<Uint8List?>> loadThumbnailBatchOrdered(
    List<ImageItem> images, {
    int batchSize = defaultBatchSize,
    void Function(int loaded, int total)? onProgress,
  }) async {
    final thumbnailMap = await loadThumbnailBatch(
      images,
      batchSize: batchSize,
      onProgress: onProgress,
    );

    return images.map((img) => thumbnailMap[img.id]).toList();
  }

  /// Cache a thumbnail with LRU eviction
  void _cacheThumbnail(String id, Uint8List thumbnail) {
    // Evict oldest entries if cache is full
    while (_thumbnailCache.length >= maxThumbnailCacheSize) {
      final oldestKey = _thumbnailCache.keys.first;
      _thumbnailCache.remove(oldestKey);
    }
    _thumbnailCache[id] = thumbnail;
  }

  /// Clear the thumbnail cache to free memory
  void clearThumbnailCache() {
    _thumbnailCache.clear();
    debugPrint('ImageLoaderService: Thumbnail cache cleared');
  }

  /// Get thumbnail cache statistics
  Map<String, dynamic> getThumbnailCacheStats() {
    final totalBytes = _thumbnailCache.values.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    );
    return {
      'count': _thumbnailCache.length,
      'maxCount': maxThumbnailCacheSize,
      'totalBytes': totalBytes,
      'totalMB': (totalBytes / (1024 * 1024)).toStringAsFixed(2),
    };
  }

  /// Clear the image cache
  ///
  /// Use this to free up memory when images are no longer needed
  void clearCache() {
    _imageCache.clear();
    _assetCache.clear();
    _thumbnailCache.clear();
  }

  /// Dispose of resources
  ///
  /// Call this when the service is no longer needed
  void dispose() {
    clearCache();
    _isInitialized = false;
  }

  // ========== Mock Implementation (Fallback) ==========
  // Only used when real gallery access fails

  /// Generate mock images for testing when real gallery access fails
  List<ImageItem> _generateMockImages(int count) {
    final now = DateTime.now();
    debugPrint('⚠️  Using MOCK images - add real photos to your device gallery!');
    return List.generate(
      count,
      (index) => ImageItem(
        id: 'mock_image_$index',
        path: '/storage/emulated/0/DCIM/Camera/IMG_$index.jpg',
        createdAt: now.subtract(Duration(days: index)),
        modifiedAt: now.subtract(Duration(days: index)),
        sizeBytes: 1024 * 1024 * (index + 1), // 1-9 MB
        width: 1920,
        height: 1080,
      ),
    );
  }
}
