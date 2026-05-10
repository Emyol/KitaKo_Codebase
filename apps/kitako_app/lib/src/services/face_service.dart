import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kitako_core/kitako_core.dart';
import 'package:kitako_embedding/kitako_embedding.dart';
import 'package:path_provider/path_provider.dart';

/// Top-level function run inside a background isolate via [compute].
///
/// Loads face models fresh in the isolate (ONNX sessions cannot cross
/// isolate boundaries), processes a batch of images, and returns
/// serializable face detection results.
Future<List<Map<String, dynamic>>> _runFaceBatchInIsolate(
  Map<String, dynamic> params,
) async {
  final detectorPath = params['detectorPath'] as String;
  final embedderPath = params['embedderPath'] as String;
  final images = params['images'] as List<dynamic>;

  final pipeline = FacePipeline();
  try {
    final ready = await pipeline.initialize(
      detectorModelPath: detectorPath,
      embedderModelPath: embedderPath,
    );
    if (!ready) return const [];

    final results = <Map<String, dynamic>>[];
    for (final imgEntry in images) {
      final imgMap = imgEntry as Map<String, dynamic>;
      final imageId = imgMap['id'] as String;
      final bytes = imgMap['bytes'] as Uint8List;
      try {
        final faceResults = pipeline.processImage(bytes);
        for (final r in faceResults) {
          final bb = r.detection.boundingBox;
          results.add(<String, dynamic>{
            'imageId': imageId,
            'bbox': <double>[bb.left, bb.top, bb.width, bb.height],
            'confidence': r.detection.confidence,
            'embedding': r.embedding,
            'thumbnail': r.thumbnail,
          });
        }
      } catch (_) {}
    }
    return results;
  } finally {
    pipeline.dispose();
  }
}

/// Status of the face recognition subsystem.
enum FaceServiceStatus {
  /// Not yet initialized
  uninitialized,

  /// Initializing (loading models)
  initializing,

  /// Models loaded, ready for face processing
  ready,

  /// Models not available — feature gracefully disabled
  unavailable,

  /// Currently indexing faces from gallery
  indexing,

  /// An error occurred but the rest of the app is unaffected
  error,
}

/// State broadcast for face indexing progress.
class FaceIndexingState {
  final int processedImages;
  final int totalImages;
  final int facesFound;
  final int personsIdentified;
  final bool isComplete;
  final String? error;

  const FaceIndexingState({
    this.processedImages = 0,
    this.totalImages = 0,
    this.facesFound = 0,
    this.personsIdentified = 0,
    this.isComplete = false,
    this.error,
  });

  double get progress =>
      totalImages > 0 ? processedImages / totalImages : 0.0;

  @override
  String toString() =>
      'FaceIndexingState($processedImages/$totalImages, '
      'faces: $facesFound, persons: $personsIdentified)';
}

/// Application-level service for face recognition features.
///
/// Wraps [FacePipeline] and [FaceDbscan] with app-level concerns:
/// gallery indexing, person management, state broadcasting,
/// persistence, and graceful degradation.
///
/// ## Graceful Degradation
///
/// This service is **completely optional**. If face models are not available:
/// - [status] will be [FaceServiceStatus.unavailable]
/// - [isAvailable] will be `false`
/// - All query methods return empty results
/// - The rest of the app works normally
///
/// This service NEVER throws exceptions to the caller. Errors are
/// logged and the service transitions to [FaceServiceStatus.unavailable]
/// or [FaceServiceStatus.error].
class FaceService {
  final FacePipeline _pipeline = FacePipeline();
  final FaceDbscan _clusterer;

  FaceServiceStatus _status = FaceServiceStatus.uninitialized;

  // Stored so the background isolate can load its own sessions from the same paths
  String? _detectorPath;
  String? _embedderPath;

  final Map<String, FaceRecord> _faceRecords = {};
  final Map<int, Person> _persons = {};
  final Map<String, List<String>> _imageFaces = {};

  final _statusController =
      StreamController<FaceServiceStatus>.broadcast();
  final _indexingController =
      StreamController<FaceIndexingState>.broadcast();

  int _faceIdCounter = 0;

  FaceService({
    double clusteringEps = kFaceClusteringThreshold,
    int clusteringMinPoints = kFaceClusteringMinPoints,
  }) : _clusterer = FaceDbscan(
          eps: clusteringEps,
          minPoints: clusteringMinPoints,
        );

  // ========== Public Getters ==========

  FaceServiceStatus get status => _status;
  bool get isAvailable => _status == FaceServiceStatus.ready;
  bool get isModelLoaded => _pipeline.isReady;

  Stream<FaceServiceStatus> get statusStream => _statusController.stream;
  Stream<FaceIndexingState> get indexingStream => _indexingController.stream;

  List<FaceRecord> get allFaces => _faceRecords.values.toList();
  List<Person> get allPersons => _persons.values.toList();
  int get faceCount => _faceRecords.length;
  int get personCount => _persons.length;

  // ========== Initialization ==========

  /// Initialize with explicit model paths.
  ///
  /// Returns false (and sets status to unavailable) if models are missing —
  /// never throws.
  Future<bool> initialize({
    required String detectorModelPath,
    required String embedderModelPath,
  }) async {
    _detectorPath = detectorModelPath;
    _embedderPath = embedderModelPath;
    _setStatus(FaceServiceStatus.initializing);

    try {
      final ready = await _pipeline.initialize(
        detectorModelPath: detectorModelPath,
        embedderModelPath: embedderModelPath,
      );

      if (!ready) {
        debugPrint('FaceService: Models not available, face recognition disabled');
        _setStatus(FaceServiceStatus.unavailable);
        return false;
      }

      await _loadPersistedData();

      _setStatus(FaceServiceStatus.ready);
      debugPrint('FaceService: Initialized — '
          'detector: ${_pipeline.canDetect}, embedder: ${_pipeline.canEmbed}');
      return true;
    } catch (e) {
      debugPrint('FaceService: Initialization failed: $e');
      _setStatus(FaceServiceStatus.unavailable);
      return false;
    }
  }

  /// Auto-detect and load face models, extracting from bundled assets if needed.
  ///
  /// Resolution order:
  ///   1. App documents directory (already extracted on a prior run).
  ///   2. Bundled Flutter assets (`assets/models/face/`) — extracted once on
  ///      first run and reused on every subsequent launch.
  ///   3. /data/local/tmp/face_models/ (Android ADB push, dev only).
  ///
  /// Returns true if models were found and loaded.
  Future<bool> tryAutoInitialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = '${appDir.path}/face_models';

      final detectorPath = '$modelDir/${FaceModelFiles.faceDetector}';
      final embedderPath = '$modelDir/${FaceModelFiles.faceEmbedder}';

      // 1. Already extracted from a previous run — fastest path.
      if (await File(detectorPath).exists() &&
          await File(embedderPath).exists()) {
        return await initialize(
          detectorModelPath: detectorPath,
          embedderModelPath: embedderPath,
        );
      }

      // 2. Extract from bundled assets (first launch or after app reinstall).
      final extracted = await _extractBundledModels(modelDir);
      if (extracted) {
        return await initialize(
          detectorModelPath: detectorPath,
          embedderModelPath: embedderPath,
        );
      }

      // 3. Android ADB push location (dev workflow).
      if (Platform.isAndroid) {
        const tmpDetector =
            '/data/local/tmp/face_models/${FaceModelFiles.faceDetector}';
        const tmpEmbedder =
            '/data/local/tmp/face_models/${FaceModelFiles.faceEmbedder}';

        if (await File(tmpDetector).exists() &&
            await File(tmpEmbedder).exists()) {
          await Directory(modelDir).create(recursive: true);
          await File(tmpDetector).copy(detectorPath);
          await File(tmpEmbedder).copy(embedderPath);

          return await initialize(
            detectorModelPath: detectorPath,
            embedderModelPath: embedderPath,
          );
        }
      }

      debugPrint('FaceService: No face models found, feature disabled');
      _setStatus(FaceServiceStatus.unavailable);
      return false;
    } catch (e) {
      debugPrint('FaceService: Auto-initialize failed: $e');
      _setStatus(FaceServiceStatus.unavailable);
      return false;
    }
  }

  /// Extract face model assets from the Flutter bundle to [destDir].
  ///
  /// Skips files that already exist (safe to call on every launch).
  /// Returns true if both model files are present after the attempt.
  Future<bool> _extractBundledModels(String destDir) async {
    const assets = <String, String>{
      'assets/models/face/${FaceModelFiles.faceDetector}':
          FaceModelFiles.faceDetector,
      'assets/models/face/${FaceModelFiles.faceEmbedder}':
          FaceModelFiles.faceEmbedder,
    };

    try {
      await Directory(destDir).create(recursive: true);

      for (final entry in assets.entries) {
        final dest = File('$destDir/${entry.value}');
        if (await dest.exists()) continue;

        debugPrint('FaceService: Extracting ${entry.value} from assets…');
        final data = await rootBundle.load(entry.key);
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        debugPrint(
          'FaceService: Extracted ${entry.value} '
          '(${(data.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
        );
      }

      // Verify both files are present.
      return await File('$destDir/${FaceModelFiles.faceDetector}').exists() &&
          await File('$destDir/${FaceModelFiles.faceEmbedder}').exists();
    } catch (e) {
      debugPrint('FaceService: Asset extraction failed: $e');
      return false;
    }
  }

  // ========== Face Indexing ==========

  /// Process a batch of images for face detection and embedding,
  /// then run DBSCAN clustering.
  Future<void> indexImages(
    List<MapEntry<String, Uint8List>> imageEntries, {
    void Function(FaceIndexingState)? onProgress,
  }) async {
    if (!isAvailable) {
      debugPrint('FaceService: Not available, skipping face indexing');
      return;
    }

    _setStatus(FaceServiceStatus.indexing);

    final total = imageEntries.length;
    int processed = 0;
    int facesFound = 0;

    for (final entry in imageEntries) {
      try {
        final results = _pipeline.processImage(entry.value);

        for (final result in results) {
          final faceId = _generateFaceId();
          final record = FaceRecord(
            faceId: faceId,
            imageId: entry.key,
            boundingBox: result.detection.boundingBox,
            embedding: result.embedding,
            confidence: result.detection.confidence,
            faceThumbnail: result.thumbnail,
          );

          _faceRecords[faceId] = record;
          _imageFaces.putIfAbsent(entry.key, () => []).add(faceId);
          facesFound++;
        }
      } catch (e) {
        debugPrint('FaceService: Error processing image ${entry.key}: $e');
      }

      processed++;

      final state = FaceIndexingState(
        processedImages: processed,
        totalImages: total,
        facesFound: facesFound,
      );
      _indexingController.add(state);
      onProgress?.call(state);
    }

    _runClustering();
    await _persistData();

    _setStatus(FaceServiceStatus.ready);

    final finalState = FaceIndexingState(
      processedImages: total,
      totalImages: total,
      facesFound: facesFound,
      personsIdentified: _persons.length,
      isComplete: true,
    );
    _indexingController.add(finalState);

    debugPrint('FaceService: Indexing complete — '
        '$facesFound faces, ${_persons.length} persons');
  }

  /// Process a batch without clustering (call [finalizeClustering] after all batches).
  ///
  /// Runs ONNX inference in a background isolate so the UI thread stays
  /// responsive. Models are loaded fresh inside the isolate each call —
  /// use a reasonable batch size (≥20) to amortize that overhead.
  Future<void> indexImageBatch(
    List<MapEntry<String, Uint8List>> imageEntries,
  ) async {
    if (!isAvailable) return;
    final detectorPath = _detectorPath;
    final embedderPath = _embedderPath;
    if (detectorPath == null || embedderPath == null) return;

    _setStatus(FaceServiceStatus.indexing);

    final params = <String, dynamic>{
      'detectorPath': detectorPath,
      'embedderPath': embedderPath,
      'images': imageEntries
          .map((e) => <String, dynamic>{'id': e.key, 'bytes': e.value})
          .toList(),
    };

    try {
      final batchResults = await compute(_runFaceBatchInIsolate, params);

      for (final result in batchResults) {
        final faceId = _generateFaceId();
        final imageId = result['imageId'] as String;
        final bboxList = result['bbox'] as List<dynamic>;
        final bbox = Rect.fromLTWH(
          (bboxList[0] as num).toDouble(),
          (bboxList[1] as num).toDouble(),
          (bboxList[2] as num).toDouble(),
          (bboxList[3] as num).toDouble(),
        );
        _faceRecords[faceId] = FaceRecord(
          faceId: faceId,
          imageId: imageId,
          boundingBox: bbox,
          embedding: result['embedding'] as Float32List,
          confidence: (result['confidence'] as num).toDouble(),
          faceThumbnail: result['thumbnail'] as Uint8List?,
        );
        _imageFaces.putIfAbsent(imageId, () => []).add(faceId);
      }
    } catch (e) {
      debugPrint('FaceService: Batch isolate failed: $e');
    }
  }

  /// Run clustering + persistence after all batches are indexed.
  Future<void> finalizeClustering() async {
    if (_faceRecords.isEmpty) {
      _setStatus(FaceServiceStatus.ready);
      return;
    }

    _runClustering();
    await _persistData();
    _setStatus(FaceServiceStatus.ready);

    debugPrint('FaceService: Finalized — '
        '${_faceRecords.length} faces, ${_persons.length} persons');
  }

  /// Process a single image for faces. Returns created records (empty on failure).
  List<FaceRecord> processImage(String imageId, Uint8List imageBytes) {
    if (!isAvailable) return [];

    try {
      final results = _pipeline.processImage(imageBytes);
      final records = <FaceRecord>[];

      for (final result in results) {
        final faceId = _generateFaceId();
        final record = FaceRecord(
          faceId: faceId,
          imageId: imageId,
          boundingBox: result.detection.boundingBox,
          embedding: result.embedding,
          confidence: result.detection.confidence,
          faceThumbnail: result.thumbnail,
        );

        _faceRecords[faceId] = record;
        _imageFaces.putIfAbsent(imageId, () => []).add(faceId);
        records.add(record);
      }

      return records;
    } catch (e) {
      debugPrint('FaceService: Error processing image $imageId: $e');
      return [];
    }
  }

  // ========== Person Management ==========

  /// Assign a label to a person cluster. Returns true on success.
  bool labelPerson(int personId, String label) {
    final person = _persons[personId];
    if (person == null) return false;

    _persons[personId] = person.copyWith(label: label);

    for (final faceId in person.faceIds) {
      final record = _faceRecords[faceId];
      if (record != null) {
        _faceRecords[faceId] = record.copyWith(personLabel: label);
      }
    }

    _persistData();
    debugPrint('FaceService: Labeled person $personId as "$label"');
    return true;
  }

  /// Merge two clusters into one. Use when user identifies two clusters
  /// as the same person.
  bool mergePersons(int keepPersonId, int mergePersonId) {
    final keep = _persons[keepPersonId];
    final merge = _persons[mergePersonId];
    if (keep == null || merge == null) return false;

    final mergedFaceIds = [...keep.faceIds, ...merge.faceIds];

    final embeddings = mergedFaceIds
        .map((id) => _faceRecords[id]?.embedding)
        .whereType<Float32List>()
        .toList();
    final newCentroid = FaceDbscan.computeCentroid(embeddings);

    _persons[keepPersonId] = keep.copyWith(
      faceIds: mergedFaceIds,
      centroidEmbedding: newCentroid,
    );

    for (final faceId in merge.faceIds) {
      final record = _faceRecords[faceId];
      if (record != null) {
        _faceRecords[faceId] = record.copyWith(
          clusterId: keepPersonId,
          personLabel: keep.label,
        );
      }
    }

    _persons.remove(mergePersonId);
    _persistData();

    debugPrint('FaceService: Merged person $mergePersonId into $keepPersonId');
    return true;
  }

  // ========== Query / Retrieval ==========

  /// Get all image IDs containing a specific person.
  List<String> getImageIdsForPerson(int personId) {
    final person = _persons[personId];
    if (person == null) return [];

    return person.faceIds
        .map((faceId) => _faceRecords[faceId]?.imageId)
        .whereType<String>()
        .toSet()
        .toList();
  }

  /// Find the person ID whose centroid is closest to [faceEmbedding].
  int? findMatchingPerson(
    Float32List faceEmbedding, {
    double threshold = kFaceClusteringThreshold,
  }) {
    if (_persons.isEmpty) return null;

    int? bestPersonId;
    double bestDistance = double.infinity;

    for (final person in _persons.values) {
      final dist = _cosineDistance(faceEmbedding, person.centroidEmbedding);
      if (dist < threshold && dist < bestDistance) {
        bestDistance = dist;
        bestPersonId = person.personId;
      }
    }

    return bestPersonId;
  }

  /// Get faces in a specific image.
  List<FaceRecord> getFacesInImage(String imageId) {
    final faceIds = _imageFaces[imageId];
    if (faceIds == null) return [];

    return faceIds
        .map((id) => _faceRecords[id])
        .whereType<FaceRecord>()
        .toList();
  }

  Person? getPerson(int personId) => _persons[personId];
  FaceRecord? getFace(String faceId) => _faceRecords[faceId];

  /// Search image IDs containing a person whose label matches [label].
  List<String> searchByPersonLabel(String label) {
    final matchingPersons = _persons.values
        .where((p) =>
            p.label != null &&
            p.label!.toLowerCase().contains(label.toLowerCase()))
        .toList();

    final imageIds = <String>{};
    for (final person in matchingPersons) {
      imageIds.addAll(getImageIdsForPerson(person.personId));
    }

    return imageIds.toList();
  }

  // ========== Statistics ==========

  Map<String, dynamic> getStats() {
    return {
      'status': _status.name,
      'isAvailable': isAvailable,
      'totalFaces': _faceRecords.length,
      'totalPersons': _persons.length,
      'imagesWithFaces': _imageFaces.length,
      'detectorReady': _pipeline.canDetect,
      'embedderReady': _pipeline.canEmbed,
    };
  }

  // ========== Cleanup ==========

  void clearAllData() {
    _faceRecords.clear();
    _persons.clear();
    _imageFaces.clear();
    _faceIdCounter = 0;
    debugPrint('FaceService: All data cleared');
  }

  void dispose() {
    _pipeline.dispose();
    _statusController.close();
    _indexingController.close();
    _faceRecords.clear();
    _persons.clear();
    _imageFaces.clear();
    debugPrint('FaceService: Disposed');
  }

  // ========== Private Methods ==========

  void _setStatus(FaceServiceStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  String _generateFaceId() {
    _faceIdCounter++;
    return 'face_$_faceIdCounter';
  }

  void _runClustering() {
    if (_faceRecords.isEmpty) return;

    try {
      final embeddings = <Float32List>[];
      final faceIds = <String>[];

      for (final record in _faceRecords.values) {
        embeddings.add(record.embedding);
        faceIds.add(record.faceId);
      }

      final result = _clusterer.cluster(embeddings, faceIds);

      _persons.clear();
      for (final entry in result.clusters.entries) {
        final clusterId = entry.key;
        final clusterFaceIds = entry.value;

        final clusterEmbeddings = clusterFaceIds
            .map((id) => _faceRecords[id]?.embedding)
            .whereType<Float32List>()
            .toList();
        final centroid = FaceDbscan.computeCentroid(clusterEmbeddings);

        Uint8List? bestThumbnail;
        double bestConfidence = 0;
        for (final faceId in clusterFaceIds) {
          final record = _faceRecords[faceId];
          if (record != null &&
              record.faceThumbnail != null &&
              record.confidence > bestConfidence) {
            bestConfidence = record.confidence;
            bestThumbnail = record.faceThumbnail;
          }
        }

        String? existingLabel;
        for (final faceId in clusterFaceIds) {
          final record = _faceRecords[faceId];
          if (record != null && record.isLabeled) {
            existingLabel = record.personLabel;
            break;
          }
        }

        _persons[clusterId] = Person(
          personId: clusterId,
          label: existingLabel,
          centroidEmbedding: centroid,
          faceIds: clusterFaceIds,
          representativeThumbnail: bestThumbnail,
        );

        for (final faceId in clusterFaceIds) {
          final record = _faceRecords[faceId];
          if (record != null) {
            _faceRecords[faceId] = record.copyWith(
              clusterId: clusterId,
              personLabel: existingLabel,
            );
          }
        }
      }

      // Singleton Person entries for unclustered faces that have sufficiently
      // high detection confidence. Low-confidence isolates are almost always
      // false positives (posters, stickers, cartoon art) — skip them.
      int noisePersonId = 10000;
      for (final faceId in result.noise) {
        final record = _faceRecords[faceId];
        if (record == null) continue;
        if (record.confidence < 0.50 && !record.isLabeled) continue;

        _persons[noisePersonId] = Person(
          personId: noisePersonId,
          label: record.isLabeled ? record.personLabel : null,
          centroidEmbedding: record.embedding,
          faceIds: [faceId],
          representativeThumbnail: record.faceThumbnail,
        );

        _faceRecords[faceId] = record.copyWith(clusterId: noisePersonId);
        noisePersonId++;
      }

      debugPrint('FaceService: Clustering found ${result.clusters.length} clusters '
          '+ ${result.noise.length} singletons = ${_persons.length} persons '
          'from ${_faceRecords.length} faces');
    } catch (e) {
      debugPrint('FaceService: Clustering failed: $e');
    }
  }

  double _cosineDistance(Float32List a, Float32List b) {
    double dot = 0.0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
    }
    return 1.0 - dot;
  }

  // ========== Persistence ==========

  Future<String> get _persistPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/face_data';
  }

  Future<void> _persistData() async {
    try {
      final dir = await _persistPath;
      await Directory(dir).create(recursive: true);

      final faceMap = <String, Map<String, dynamic>>{};
      for (final record in _faceRecords.values) {
        final entry = <String, dynamic>{
          'imageId': record.imageId,
          'clusterId': record.clusterId,
          'personLabel': record.personLabel,
          'confidence': record.confidence,
          'bbox': [
            record.boundingBox.left,
            record.boundingBox.top,
            record.boundingBox.width,
            record.boundingBox.height,
          ],
          'embedding': record.embedding.toList(),
        };
        if (record.faceThumbnail != null) {
          entry['thumbnail'] = base64Encode(record.faceThumbnail!);
        }
        faceMap[record.faceId] = entry;
      }
      await File('$dir/face_records.json').writeAsString(jsonEncode(faceMap));

      final labels = <String, dynamic>{};
      for (final person in _persons.values) {
        if (person.isLabeled) {
          labels[person.personId.toString()] = person.label;
        }
      }
      await File('$dir/person_labels.json').writeAsString(jsonEncode(labels));

      debugPrint('FaceService: Data persisted (${_faceRecords.length} faces, '
          '${labels.length} labels)');
    } catch (e) {
      debugPrint('FaceService: Failed to persist data: $e');
    }
  }

  Future<void> _loadPersistedData() async {
    try {
      final dir = await _persistPath;
      final recordsFile = File('$dir/face_records.json');
      if (!await recordsFile.exists()) return;

      final faceMap =
          jsonDecode(await recordsFile.readAsString()) as Map<String, dynamic>;
      if (faceMap.isEmpty) return;

      int maxIdNum = 0;
      final clusterToFaces = <int, List<String>>{};

      for (final entry in faceMap.entries) {
        final faceId = entry.key;
        final data = entry.value as Map<String, dynamic>;

        // Embedding is required — skip records without it (legacy format)
        final embeddingData = data['embedding'] as List<dynamic>?;
        if (embeddingData == null) continue;
        final embedding = Float32List.fromList(
            embeddingData.map((e) => (e as num).toDouble()).toList());

        final bboxData = data['bbox'] as List<dynamic>;
        final bbox = Rect.fromLTWH(
          (bboxData[0] as num).toDouble(),
          (bboxData[1] as num).toDouble(),
          (bboxData[2] as num).toDouble(),
          (bboxData[3] as num).toDouble(),
        );

        final clusterId = (data['clusterId'] as num?)?.toInt();
        final personLabel = data['personLabel'] as String?;
        Uint8List? thumbnail;
        if (data['thumbnail'] is String) {
          try {
            thumbnail = base64Decode(data['thumbnail'] as String);
          } catch (_) {}
        }

        final record = FaceRecord(
          faceId: faceId,
          imageId: data['imageId'] as String,
          boundingBox: bbox,
          embedding: embedding,
          confidence: (data['confidence'] as num).toDouble(),
          clusterId: clusterId,
          personLabel: personLabel,
          faceThumbnail: thumbnail,
        );

        _faceRecords[faceId] = record;
        _imageFaces.putIfAbsent(record.imageId, () => []).add(faceId);

        if (clusterId != null) {
          clusterToFaces.putIfAbsent(clusterId, () => []).add(faceId);
        }

        final idNum = int.tryParse(faceId.replaceFirst('face_', ''));
        if (idNum != null && idNum > maxIdNum) maxIdNum = idNum;
      }

      _faceIdCounter = maxIdNum;

      // Rebuild Person entries from loaded cluster assignments
      for (final clusterEntry in clusterToFaces.entries) {
        final clusterId = clusterEntry.key;
        final faceIds = clusterEntry.value;

        final embeddings = faceIds
            .map((id) => _faceRecords[id]?.embedding)
            .whereType<Float32List>()
            .toList();
        final centroid = FaceDbscan.computeCentroid(embeddings);

        Uint8List? bestThumbnail;
        String? label;
        double bestConf = 0;
        for (final faceId in faceIds) {
          final r = _faceRecords[faceId];
          if (r == null) continue;
          if (r.personLabel != null) label = r.personLabel;
          if (r.faceThumbnail != null && r.confidence > bestConf) {
            bestConf = r.confidence;
            bestThumbnail = r.faceThumbnail;
          }
        }

        _persons[clusterId] = Person(
          personId: clusterId,
          label: label,
          centroidEmbedding: centroid,
          faceIds: faceIds,
          representativeThumbnail: bestThumbnail,
        );
      }

      debugPrint('FaceService: Restored ${_faceRecords.length} faces, '
          '${_persons.length} persons from cache');
    } catch (e) {
      debugPrint('FaceService: Failed to load persisted data: $e');
      // Reset to clean state so a fresh index can be triggered
      _faceRecords.clear();
      _persons.clear();
      _imageFaces.clear();
    }
  }
}
