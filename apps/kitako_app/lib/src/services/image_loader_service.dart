import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/search_models.dart';

/// Service for loading and managing device images
///
/// TEST MODE: Loads images exclusively from /data/local/tmp/test_images/
/// instead of scanning the device gallery via photo_manager.
///
/// Push test images via ADB:
///   adb push <local_folder>/. /data/local/tmp/test_images/
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

  /// Cache of File objects keyed by image ID (filename)
  final Map<String, File> _fileCache = {};

  /// Cache of loaded bytes for thumbnails/full images
  final Map<String, Uint8List> _bytesCache = {};

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Test images directory (world-readable, no permissions needed)
  static const String _testImagesDir = '/data/local/tmp/test_images';

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

  /// Initialize the image loader service
  ///
  /// Verifies [_testImagesDir] exists and counts images.
  ///
  /// Returns `true` if initialization was successful
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('ImageLoaderService: Initializing (TEST MODE - folder scan)...');
      debugPrint('ImageLoaderService: Test images dir: $_testImagesDir');

      final dir = Directory(_testImagesDir);
      final exists = await dir.exists();
      debugPrint('ImageLoaderService: Directory exists: $exists');
      if (exists) {
        final count = await dir.list().length;
        debugPrint('ImageLoaderService: Files in directory: $count');
      }

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to initialize: $e');
      _isInitialized = true;
      return true;
    }
  }

  /// Load all images from the test images folder
  ///
  /// Scans /sdcard/KitaKo/test_images/ for supported image files.
  /// Returns a list of [ImageItem] objects. Cached for subsequent calls.
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
      debugPrint('ImageLoaderService: Scanning test images folder: $_testImagesDir');

      final dir = Directory(_testImagesDir);
      if (!await dir.exists()) {
        debugPrint('ImageLoaderService: Test images folder not found! '
            'Push images via ADB: adb push <folder>/. $_testImagesDir/');
        _imageCache.addAll(_generateMockImages(9));
        return List.unmodifiable(_imageCache);
      }

      // List all files in the directory
      final entities = await dir.list().toList();
      int imageCount = 0;

      for (final entity in entities) {
        if (entity is File && _isSupported(entity.path)) {
          if (imageCount >= _maxImages) break;

          final filename = entity.path.split('/').last;
          final stat = await entity.stat();

          final imageItem = ImageItem(
            id: filename, // Use filename as unique ID
            path: entity.path,
            createdAt: stat.changed,
            modifiedAt: stat.modified,
            sizeBytes: stat.size,
          );

          _imageCache.add(imageItem);
          _fileCache[filename] = entity;
          imageCount++;
        }
      }

      debugPrint('ImageLoaderService: Loaded ${_imageCache.length} test images from folder');
      return List.unmodifiable(_imageCache);
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load images: $e');
      if (_imageCache.isEmpty) {
        _imageCache.addAll(_generateMockImages(9));
      }
      return List.unmodifiable(_imageCache);
    }
  }

  /// Check if a file path has a supported image extension
  bool _isSupported(String path) {
    final lower = path.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Load thumbnail for a specific image
  ///
  /// For test mode, returns the full image bytes (the embedding
  /// service will resize internally). Results are cached.
  Future<Uint8List?> loadThumbnail(String imageId) async {
    // Return cached bytes if available
    if (_bytesCache.containsKey(imageId)) {
      return _bytesCache[imageId];
    }

    final file = _fileCache[imageId];
    if (file == null) {
      debugPrint('ImageLoaderService: File not found for $imageId');
      return null;
    }

    try {
      final bytes = await file.readAsBytes();
      _bytesCache[imageId] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load thumbnail for $imageId: $e');
      return null;
    }
  }

  /// Load full image bytes for a specific image
  ///
  /// Returns image file data as Uint8List, or null if not available.
  Future<Uint8List?> loadImageBytes(String imageId) async {
    // Reuse cached bytes from thumbnail load if available
    if (_bytesCache.containsKey(imageId)) {
      return _bytesCache[imageId];
    }

    final file = _fileCache[imageId];
    if (file == null) {
      debugPrint('ImageLoaderService: File not found for $imageId');
      return null;
    }

    try {
      final bytes = await file.readAsBytes();
      _bytesCache[imageId] = bytes;
      return bytes;
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
  /// Forces a reload of all images from the test folder.
  Future<List<ImageItem>> refreshImages() async {
    _imageCache.clear();
    _fileCache.clear();
    _bytesCache.clear();
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
    _fileCache.clear();
    _bytesCache.clear();
  }

  /// Dispose of resources
  ///
  /// Call this when the service is no longer needed
  void dispose() {
    clearCache();
    _isInitialized = false;
  }

  /// In test mode, permission is always granted (file system access)
  bool get hasPermission => true;

  /// Open app settings (no-op in test mode)
  Future<void> openSettings() async {
    debugPrint('ImageLoaderService: openSettings not needed in test mode');
  }

  // ========== Mock Implementation ==========
  // Used as fallback when test folder is missing

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
