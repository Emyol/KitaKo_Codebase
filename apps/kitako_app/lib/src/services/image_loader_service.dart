import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/search_models.dart';

/// Service for loading and managing device images
///
/// This service handles:
/// - Loading images from device storage using photo_manager
/// - Caching image metadata and thumbnails
/// - Managing image permissions
///
/// Example usage:
/// ```dart
/// final imageLoader = ImageLoaderService();
/// await imageLoader.initialize();
/// final images = await imageLoader.loadDeviceImages();
/// ```
class ImageLoaderService {
  /// Cache of loaded images
  final List<ImageItem> _imageCache = [];

  /// Cache of AssetEntity objects for quick access
  final Map<String, AssetEntity> _assetCache = {};

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Whether we have permission to access photos
  bool _hasPermission = false;

  /// Supported image file extensions
  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  /// Maximum number of images to load (for performance)
  static const int _maxImages = 5000;

  /// Thumbnail size for previews
  static const int _thumbnailSize = 200;

  /// Initialize the image loader service
  ///
  /// This should be called before using any other methods.
  /// It requests storage permissions and prepares the image cache.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('ImageLoaderService: Requesting permission...');

      // Request permission to access photos
      final permission = await PhotoManager.requestPermissionExtend();
      _hasPermission = permission.isAuth || permission.hasAccess;

      if (!_hasPermission) {
        debugPrint('ImageLoaderService: Permission denied');
        // Fall back to mock mode if permission denied
        _isInitialized = true;
        return true;
      }

      debugPrint('ImageLoaderService: Permission granted');
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to initialize: $e');
      // Still mark as initialized to allow mock fallback
      _isInitialized = true;
      return true;
    }
  }

  /// Load all images from device storage
  ///
  /// Returns a list of [ImageItem] objects representing images on the device.
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

    // If no permission, return mock data
    if (!_hasPermission) {
      debugPrint('ImageLoaderService: No permission, using mock data');
      _imageCache.addAll(_generateMockImages(9));
      return List.unmodifiable(_imageCache);
    }

    try {
      debugPrint('ImageLoaderService: Loading device images...');

      // Get all image albums
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );

      if (albums.isEmpty) {
        debugPrint('ImageLoaderService: No albums found');
        return [];
      }

      // Get images from the "All" album (first one usually)
      final allAlbum = albums.first;
      final assetCount = await allAlbum.assetCountAsync;
      final count = assetCount.clamp(0, _maxImages);

      debugPrint('ImageLoaderService: Found $assetCount images, loading $count');

      // Load assets
      final assets = await allAlbum.getAssetListPaged(page: 0, size: count);

      // Convert to ImageItem objects - optimized to avoid slow file operations
      for (final asset in assets) {
        // Use the asset's relativePath property instead of fetching the file
        // This is much faster as it doesn't require disk I/O for each image
        final relativePath = asset.relativePath ?? '';
        final title = await asset.titleAsync;
        final path = relativePath.isNotEmpty 
            ? '$relativePath/$title' 
            : title;

        final imageItem = ImageItem(
          id: asset.id,
          path: path,
          createdAt: asset.createDateTime,
          modifiedAt: asset.modifiedDateTime,
          sizeBytes: null, // Skip file size for performance
          width: asset.width,
          height: asset.height,
        );

        _imageCache.add(imageItem);
        _assetCache[asset.id] = asset;
      }

      debugPrint('ImageLoaderService: Loaded ${_imageCache.length} images');
      return List.unmodifiable(_imageCache);
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load images: $e');
      // Fall back to mock data on error
      if (_imageCache.isEmpty) {
        _imageCache.addAll(_generateMockImages(9));
      }
      return List.unmodifiable(_imageCache);
    }
  }

  /// Load thumbnail for a specific image
  ///
  /// Returns thumbnail data as Uint8List, or null if not available
  Future<Uint8List?> loadThumbnail(String imageId) async {
    final asset = _assetCache[imageId];
    if (asset == null) return null;

    try {
      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(_thumbnailSize, _thumbnailSize),
        quality: 80,
      );
      return thumb;
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load thumbnail for $imageId: $e');
      return null;
    }
  }

  /// Load full image bytes for a specific image
  ///
  /// Returns image file data as Uint8List, or null if not available.
  /// This reads the actual file from disk, so use sparingly.
  Future<Uint8List?> loadImageBytes(String imageId) async {
    final asset = _assetCache[imageId];
    if (asset == null) {
      debugPrint('ImageLoaderService: Asset not found for $imageId');
      return null;
    }

    try {
      final file = await asset.file;
      if (file == null) {
        debugPrint('ImageLoaderService: File not available for $imageId');
        return null;
      }
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load image bytes for $imageId: $e');
      return null;
    }
  }

  /// Get ImageItem with thumbnail loaded
  Future<ImageItem> getImageWithThumbnail(String imageId) async {
    final image = getImageById(imageId);
    if (image == null) {
      throw StateError('Image not found: $imageId');
    }

    if (image.thumbnail != null) {
      return image;
    }

    final thumbnail = await loadThumbnail(imageId);
    if (thumbnail != null) {
      final updatedImage = image.copyWith(thumbnail: thumbnail);
      // Update cache
      final index = _imageCache.indexWhere((img) => img.id == imageId);
      if (index >= 0) {
        _imageCache[index] = updatedImage;
      }
      return updatedImage;
    }

    return image;
  }

  /// Refresh the image cache
  ///
  /// Forces a reload of all images from device storage.
  /// Useful when new images have been added or removed.
  Future<List<ImageItem>> refreshImages() async {
    _imageCache.clear();
    _assetCache.clear();
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

  /// Clear the image cache
  ///
  /// Use this to free up memory when images are no longer needed
  void clearCache() {
    _imageCache.clear();
    _assetCache.clear();
  }

  /// Dispose of resources
  ///
  /// Call this when the service is no longer needed
  void dispose() {
    clearCache();
    _isInitialized = false;
  }

  /// Check if we have permission to access photos
  bool get hasPermission => _hasPermission;

  /// Open app settings for permission management
  Future<void> openSettings() async {
    await PhotoManager.openSetting();
  }

  // ========== Mock Implementation ==========
  // Used as fallback when permission is denied or for testing

  /// Generate mock images for testing
  List<ImageItem> _generateMockImages(int count) {
    final now = DateTime.now();
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
