import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/search_models.dart';

/// Identifier for a test dataset directory.
class TestDataset {
  /// Directory name under `test_datasets/`.
  final String dirName;

  /// Human-readable label for UI.
  final String label;

  const TestDataset({required this.dirName, required this.label});

  static const personal = TestDataset(
    dirName: 'personal_1k',
    label: 'Personal',
  );
  static const scraped = TestDataset(
    dirName: 'scraped_1k',
    label: 'Scraped',
  );

  static const all = <TestDataset>[personal, scraped];

  static TestDataset? byDirName(String name) {
    for (final d in all) {
      if (d.dirName == name) return d;
    }
    return null;
  }

  /// Prefix used to namespace ImageItem ids belonging to this dataset.
  /// e.g. `personal_1k_IMG_0001.jpg`
  String idPrefix() => '${dirName}_';

  @override
  String toString() => 'TestDataset($dirName)';
}

/// Service for loading and managing device images from the test datasets.
///
/// Two test sets are supported in parallel — `personal_1k` and `scraped_1k`.
/// Both are discovered and loaded on init so the search index contains
/// embeddings for both. The "active" dataset (persisted in SharedPreferences)
/// controls which subset is returned by [getActiveDatasetImages] and used
/// for search-time filtering by [ImageSearchService].
///
/// Image IDs are namespaced as `<datasetDir>_<filename>`, e.g.
/// `personal_1k_IMG_0001.jpg`. The prefix is what the dataset toggle
/// filters on.
class ImageLoaderService {
  static const String _kActiveDatasetPrefKey = 'active_test_dataset';

  /// All loaded images across all discovered datasets.
  final List<ImageItem> _imageCache = [];

  /// (id -> File) for every image found.
  final Map<String, File> _testFileCache = {};

  /// Which dataset each id belongs to (id -> dirName).
  final Map<String, String> _idToDataset = {};

  /// Datasets that were found on disk during init (their dirName).
  final Set<String> _availableDatasets = {};

  bool _isInitialized = false;

  /// Currently selected dataset (dirName). Null until [initialize] runs.
  String? _activeDataset;

  static const List<String> _supportedExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
  ];

  /// Initialize: discover both datasets, build the file cache, restore
  /// active-dataset preference. Returns `true` on success (always — failures
  /// are logged but don't throw).
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      for (final dataset in TestDataset.all) {
        final dir = await _resolveDatasetDirectory(dataset);
        if (dir == null) continue;

        final imageFiles = await _listImageFiles(dir);
        if (imageFiles.isEmpty) continue;

        _availableDatasets.add(dataset.dirName);
        for (final file in imageFiles) {
          final name = file.uri.pathSegments.last;
          final id = '${dataset.idPrefix()}$name';
          _testFileCache[id] = file;
          _idToDataset[id] = dataset.dirName;
        }
        debugPrint(
          'ImageLoaderService: ${dataset.dirName} → '
          '${imageFiles.length} images at ${dir.path}',
        );
      }

      if (_availableDatasets.isEmpty) {
        debugPrint(
          'ImageLoaderService: No test datasets found. See '
          'docs/development/TEST_DATASETS.md for setup. '
          'Expected dirs: test_datasets/personal_1k or test_datasets/scraped_1k.',
        );
      }

      _activeDataset = await _restoreActiveDataset();
      debugPrint(
        'ImageLoaderService: Total ${_testFileCache.length} images, '
        'active=$_activeDataset, available=$_availableDatasets',
      );
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to initialize: $e');
    }

    _isInitialized = true;
    return true;
  }

  /// Load **all** images from every discovered dataset.
  ///
  /// Used by the indexing pipeline so embeddings are cached for both sets
  /// in a single pass at startup. Search-time filtering (via the active
  /// dataset) is applied by [ImageSearchService].
  Future<List<ImageItem>> loadDeviceImages() async {
    if (!_isInitialized) {
      throw StateError(
        'ImageLoaderService not initialized. Call initialize() first.',
      );
    }
    if (_imageCache.isNotEmpty) {
      return List.unmodifiable(_imageCache);
    }
    for (final entry in _testFileCache.entries) {
      final stat = await entry.value.stat();
      _imageCache.add(ImageItem(
        id: entry.key,
        path: entry.value.path,
        createdAt: stat.changed,
        modifiedAt: stat.modified,
        sizeBytes: stat.size,
      ));
    }
    debugPrint('ImageLoaderService: Loaded ${_imageCache.length} images');
    return List.unmodifiable(_imageCache);
  }

  /// Get only the images belonging to the active dataset (or empty if none).
  List<ImageItem> getActiveDatasetImages() {
    final active = _activeDataset;
    if (active == null) return const [];
    return _imageCache
        .where((img) => _idToDataset[img.id] == active)
        .toList(growable: false);
  }

  /// Whether [imageId] belongs to the active dataset.
  bool isInActiveDataset(String imageId) {
    final active = _activeDataset;
    if (active == null) return true; // No filter when no active set.
    return _idToDataset[imageId] == active;
  }

  /// Currently active dataset dirName (e.g. `personal_1k`), or null.
  String? get activeDataset => _activeDataset;

  /// Datasets that were found on disk during init.
  Set<String> get availableDatasets => Set.unmodifiable(_availableDatasets);

  /// Switch the active dataset and persist the choice.
  /// Returns true if the dataset was found and is now active.
  Future<bool> setActiveDataset(String dirName) async {
    if (!_availableDatasets.contains(dirName)) {
      debugPrint(
        'ImageLoaderService: Cannot activate $dirName — not found on disk',
      );
      return false;
    }
    _activeDataset = dirName;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveDatasetPrefKey, dirName);
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to persist active dataset: $e');
    }
    return true;
  }

  Future<Uint8List?> loadThumbnail(String imageId) async {
    final file = _testFileCache[imageId];
    if (file == null) return null;
    try {
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to load thumbnail for $imageId: $e');
      return null;
    }
  }

  /// Loads an image pre-downscaled to at most 512×512 RGBA using the
  /// platform JPEG decoder, avoiding the ~48 MB buffer cost of decoding
  /// a full-resolution phone photo before the 224×224 model resize.
  ///
  /// Returns null if the file is missing or cannot be decoded.
  Future<({Uint8List rgba, int width, int height})?> loadResizedForEmbedding(
      String imageId) async {
    final file = _testFileCache[imageId];
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      // targetWidth/targetHeight hint lets the platform JPEG decoder use DCT
      // scaling — it never allocates the full-res buffer at all.
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
    final file = _testFileCache[imageId];
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
    _testFileCache.clear();
    _idToDataset.clear();
    _availableDatasets.clear();
  }

  /// Drop only the in-memory thumbnail bytes attached to cached items, but
  /// keep the [ImageItem] metadata and (id → File) map intact so search
  /// and gallery rendering keep working. The next render of a thumbnail
  /// will re-read from disk.
  ///
  /// Used by the lifecycle observer when Android signals memory pressure.
  /// 2005 cached items × ~2 MB raw thumbnail = ~4 GB worst case; this
  /// reclaims that without invalidating the index.
  int clearThumbnailBytes() {
    int cleared = 0;
    for (var i = 0; i < _imageCache.length; i++) {
      final item = _imageCache[i];
      if (item.thumbnail != null) {
        // copyWith uses `??` so passing null falls through — rebuild explicitly.
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

  /// Backwards-compat: any of the discovered datasets.
  bool get isTestDataset => _availableDatasets.isNotEmpty;

  // ── Discovery ───────────────────────────────────────────────────────────

  /// Find a dataset directory across desktop + Android paths.
  /// Returns the first non-empty match, or null.
  Future<Directory?> _resolveDatasetDirectory(TestDataset dataset) async {
    // 1. Desktop / dev: walk up from Directory.current to find a sibling
    //    `test_datasets/<dirName>` folder. Covers `flutter run -d windows`
    //    from apps/kitako_app, and also unit-test runs from package roots.
    if (!Platform.isAndroid && !Platform.isIOS) {
      final repoRelative = await _findRepoRelativeDir(dataset.dirName);
      if (repoRelative != null) return repoRelative;
    }

    // 2. Android: prefer external files dir, then ADB staging.
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final extTarget = Directory(
            '${extDir.path}/test_datasets/${dataset.dirName}',
          );
          // If empty/missing, try copying from ADB staging.
          if (!await extTarget.exists() || await _isDirEmpty(extTarget)) {
            final adbStaged = Directory(
              '/data/local/tmp/test_datasets/${dataset.dirName}',
            );
            if (await adbStaged.exists() && !await _isDirEmpty(adbStaged)) {
              await extTarget.create(recursive: true);
              int copied = 0;
              await for (final entity in adbStaged.list()) {
                if (entity is File && isImageSupported(entity.path)) {
                  final name = entity.uri.pathSegments.last;
                  await entity.copy('${extTarget.path}/$name');
                  copied++;
                }
              }
              debugPrint(
                'ImageLoaderService: Copied $copied images from '
                '${adbStaged.path} → ${extTarget.path}',
              );
            }
          }
          if (await extTarget.exists() && !await _isDirEmpty(extTarget)) {
            return extTarget;
          }
          // Fall back to direct ADB staging if external copy didn't happen.
          final adbDirect = Directory(
            '/data/local/tmp/test_datasets/${dataset.dirName}',
          );
          if (await adbDirect.exists() && !await _isDirEmpty(adbDirect)) {
            return adbDirect;
          }
        }
      } catch (e) {
        debugPrint('ImageLoaderService: Android dataset discovery failed: $e');
      }
    }

    return null;
  }

  /// Walk up to 5 parent levels from `Directory.current` looking for a
  /// `test_datasets/<dirName>` folder. Used on desktop where the working
  /// directory is the Flutter project (`apps/kitako_app`).
  Future<Directory?> _findRepoRelativeDir(String dirName) async {
    Directory current = Directory.current;
    for (int i = 0; i < 6; i++) {
      final candidate = Directory('${current.path}/test_datasets/$dirName');
      if (await candidate.exists() && !await _isDirEmpty(candidate)) {
        return candidate;
      }
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return null;
  }

  Future<List<File>> _listImageFiles(Directory dir) async {
    final out = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && isImageSupported(entity.path)) {
        out.add(entity);
      }
    }
    return out;
  }

  Future<bool> _isDirEmpty(Directory dir) async {
    await for (final _ in dir.list()) {
      return false;
    }
    return true;
  }

  /// Restore the active-dataset preference, falling back to the first
  /// available dataset if no preference is set or the saved dataset is
  /// missing on disk.
  Future<String?> _restoreActiveDataset() async {
    String? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString(_kActiveDatasetPrefKey);
    } catch (e) {
      debugPrint('ImageLoaderService: Failed to read prefs: $e');
    }
    if (saved != null && _availableDatasets.contains(saved)) return saved;
    if (_availableDatasets.contains(TestDataset.personal.dirName)) {
      return TestDataset.personal.dirName;
    }
    if (_availableDatasets.isNotEmpty) return _availableDatasets.first;
    return null;
  }
}
