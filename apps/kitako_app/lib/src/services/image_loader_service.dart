import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/search_models.dart';

/// Service for loading and managing device images from the test dataset.
///
/// Only loads images from the test dataset directory — either copied from
/// ADB staging (`/data/local/tmp/test_images/`) or already present in
/// the app's external storage (`<extDir>/test_images/`).
class ImageLoaderService {
  /// Cache of loaded images
  final List<ImageItem> _imageCache = [];

  /// File cache for test dataset images (id -> File)
  final Map<String, File> _testFileCache = {};

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Whether we're using a test dataset from the app's external files dir
  bool _useTestDataset = false;

  /// Supported image file extensions
  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  /// Initialize the image loader service.
  ///
  /// Looks for test images in order:
  ///   1. App's external dir (survives flutter re-runs, deleted on uninstall)
  ///   2. /data/local/tmp/test_images/ (where `adb push` lands; flat layout
  ///      with image files directly in the folder)
  ///   3. /data/local/tmp/test_images/test/ (legacy nested layout)
  ///
  /// Returns `true` if initialization was successful.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final appTestDir = Directory('${extDir.path}/test_images');

        // Copy from ADB staging if app dir is empty/missing
        if (!await appTestDir.exists() || await _isDirEmpty(appTestDir)) {
          // Pick whichever ADB staging layout has images: flat or legacy nested.
          Directory? tmpTestDir;
          for (final candidate in [
            Directory('/data/local/tmp/test_images'),
            Directory('/data/local/tmp/test_images/test'),
          ]) {
            if (await candidate.exists() && !await _isDirEmpty(candidate)) {
              tmpTestDir = candidate;
              break;
            }
          }
          if (tmpTestDir != null) {
            debugPrint('ImageLoaderService: Copying test images from ${tmpTestDir.path} to app dir...');
            await appTestDir.create(recursive: true);
            int copied = 0;
            await for (final entity in tmpTestDir.list()) {
              if (entity is File && isImageSupported(entity.path)) {
                final name = entity.uri.pathSegments.last;
                await entity.copy('${appTestDir.path}/$name');
                copied++;
              }
            }
            debugPrint('ImageLoaderService: Copied $copied test images to app dir');
          }
        }

        // Load from app test dir
        if (await appTestDir.exists()) {
          final entries = await appTestDir.list().toList();
          final imageFiles = entries
              .whereType<File>()
              .where((f) => isImageSupported(f.path))
              .toList();
          if (imageFiles.isNotEmpty) {
            _useTestDataset = true;
            for (final file in imageFiles) {
              final name = file.uri.pathSegments.last;
              final id = 'test_$name';
              _testFileCache[id] = file;
            }
            debugPrint('ImageLoaderService: Found ${imageFiles.length} test images — using test dataset');
            _isInitialized = true;
            return true;
          }
        }
      }

      // No test dataset found
      debugPrint('ImageLoaderService: No test dataset found in app dir or ADB staging.');
      debugPrint('ImageLoaderService: Push test images via ADB:');
      debugPrint('  adb push <local_folder>/. /data/local/tmp/test_images/');
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to initialize: $e');
      _isInitialized = true;
      return true;
    }
  }

  /// Load all images from the test dataset.
  ///
  /// Returns an empty list if no test dataset was found during initialization.
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

    if (_useTestDataset) {
      return _loadTestDatasetImages();
    }

    debugPrint('ImageLoaderService: No test dataset loaded. Returning empty image list.');
    return [];
  }

  /// Load thumbnail for a specific image.
  ///
  /// Returns thumbnail data as Uint8List, or null if not available.
  Future<Uint8List?> loadThumbnail(String imageId) async {
    final testFile = _testFileCache[imageId];
    if (testFile != null) {
      try {
        return await testFile.readAsBytes();
      } catch (e) {
        debugPrint('ImageLoaderService: Failed to load thumbnail for $imageId: $e');
        return null;
      }
    }
    return null;
  }

  /// Load full image bytes for a specific image.
  ///
  /// Returns image file data as Uint8List, or null if not available.
  Future<Uint8List?> loadImageBytes(String imageId) async {
    final testFile = _testFileCache[imageId];
    if (testFile != null) {
      try {
        return await testFile.readAsBytes();
      } catch (e) {
        debugPrint('ImageLoaderService: Failed to load image for $imageId: $e');
        return null;
      }
    }
    debugPrint('ImageLoaderService: Image not found for $imageId');
    return null;
  }

  /// Get ImageItem with thumbnail loaded.
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
      final index = _imageCache.indexWhere((img) => img.id == imageId);
      if (index >= 0) {
        _imageCache[index] = updatedImage;
      }
      return updatedImage;
    }

    return image;
  }

  /// Refresh the image cache.
  Future<List<ImageItem>> refreshImages() async {
    _imageCache.clear();
    return loadDeviceImages();
  }

  /// Get a single image by ID.
  ImageItem? getImageById(String id) {
    try {
      return _imageCache.firstWhere((image) => image.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get all loaded images.
  List<ImageItem> getAllImages() {
    return List.unmodifiable(_imageCache);
  }

  /// Check if an image file extension is supported.
  bool isImageSupported(String path) {
    final extension = path.toLowerCase();
    return _supportedExtensions.any((ext) => extension.endsWith(ext));
  }

  /// Clear the image cache.
  void clearCache() {
    _imageCache.clear();
    _testFileCache.clear();
  }

  /// Dispose of resources.
  void dispose() {
    clearCache();
    _isInitialized = false;
  }

  /// Whether the service is using a test dataset.
  bool get isTestDataset => _useTestDataset;

  // ========== Private Helpers ==========

  /// Check if a directory has no files.
  Future<bool> _isDirEmpty(Directory dir) async {
    await for (final _ in dir.list()) {
      return false;
    }
    return true;
  }

  /// Load images from the test dataset directory.
  Future<List<ImageItem>> _loadTestDatasetImages() async {
    debugPrint('ImageLoaderService: Loading test dataset (${_testFileCache.length} files)...');

    for (final entry in _testFileCache.entries) {
      final id = entry.key;
      final file = entry.value;
      final stat = await file.stat();

      _imageCache.add(ImageItem(
        id: id,
        path: file.path,
        createdAt: stat.changed,
        modifiedAt: stat.modified,
        sizeBytes: stat.size,
      ));
    }

    debugPrint('ImageLoaderService: Loaded ${_imageCache.length} test images');
    return List.unmodifiable(_imageCache);
  }
}
