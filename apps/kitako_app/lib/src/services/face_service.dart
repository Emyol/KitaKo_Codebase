import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kitako_core/kitako_core.dart';
import 'package:kitako_embedding/src/face/face_dbscan.dart';
import 'package:kitako_embedding/src/face/face_pipeline.dart';
import 'package:path_provider/path_provider.dart';

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
/// This service wraps the embedding-level [FacePipeline] and [FaceDbscan]
/// with app-level concerns: gallery indexing, person management,
/// state broadcasting, persistence, and graceful degradation.
///
/// ## Modularity / Graceful Degradation
///
/// This service is **completely optional**. If face recognition models
/// are not available:
/// - [status] will be [FaceServiceStatus.unavailable]
/// - [isAvailable] will be `false`
/// - All query methods return empty results
/// - The `ImageSearchService` and rest of the app work normally
///
/// The service NEVER throws exceptions to the caller. Errors are
/// logged and the service transitions to [FaceServiceStatus.unavailable]
/// or [FaceServiceStatus.error].
class FaceService {
  final FacePipeline _pipeline = FacePipeline();
  final FaceDbscan _clusterer;

  /// Current status of the face recognition subsystem.
  FaceServiceStatus _status = FaceServiceStatus.uninitialized;

  /// All face records indexed so far.
  final Map<String, FaceRecord> _faceRecords = {};

  /// All identified persons (clusters with optional labels).
  final Map<int, Person> _persons = {};

  /// Map of imageId → list of faceIds found in that image.
  final Map<String, List<String>> _imageFaces = {};

  /// Stream controller for status changes.
  final _statusController =
      StreamController<FaceServiceStatus>.broadcast();

  /// Stream controller for indexing progress.
  final _indexingController =
      StreamController<FaceIndexingState>.broadcast();

  /// Counter for generating unique face IDs.
  int _faceIdCounter = 0;

  /// Create a new FaceService with optional clustering parameters.
  FaceService({
    double clusteringEps = kFaceClusteringThreshold,
    int clusteringMinPoints = kFaceClusteringMinPoints,
  }) : _clusterer = FaceDbscan(
          eps: clusteringEps,
          minPoints: clusteringMinPoints,
        );

  // ========== Public Getters ==========

  /// Current status of the face recognition subsystem.
  FaceServiceStatus get status => _status;

  /// Whether face recognition is available and ready.
  bool get isAvailable => _status == FaceServiceStatus.ready;

  /// Whether face models are loaded (even if indexing hasn't started).
  bool get isModelLoaded => _pipeline.isReady;

  /// Stream of status changes.
  Stream<FaceServiceStatus> get statusStream => _statusController.stream;

  /// Stream of indexing progress updates.
  Stream<FaceIndexingState> get indexingStream => _indexingController.stream;

  /// All indexed face records.
  List<FaceRecord> get allFaces => _faceRecords.values.toList();

  /// All identified persons (clusters).
  List<Person> get allPersons => _persons.values.toList();

  /// Number of faces indexed.
  int get faceCount => _faceRecords.length;

  /// Number of persons identified.
  int get personCount => _persons.length;

  // ========== Initialization ==========

  /// Initialize the face recognition service.
  ///
  /// Tries to load face detection and embedding models. If models are
  /// not found, sets status to [FaceServiceStatus.unavailable] and
  /// returns false. Does NOT throw.
  ///
  /// Parameters:
  /// - [detectorModelPath]: Path to SCRFD ONNX model
  /// - [embedderModelPath]: Path to ArcFace ONNX model
  Future<bool> initialize({
    required String detectorModelPath,
    required String embedderModelPath,
  }) async {
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

      // Try to load persisted data
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

  /// Try to auto-detect and load face models from common locations.
  ///
  /// Searches for face models in app documents dir and /data/local/tmp/.
  /// Returns true if models were found and loaded.
  Future<bool> tryAutoInitialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = '${appDir.path}/face_models';

      // Check app documents directory first
      final detectorPath = '$modelDir/${FaceModelFiles.faceDetector}';
      final embedderPath = '$modelDir/${FaceModelFiles.faceEmbedder}';

      if (await File(detectorPath).exists() &&
          await File(embedderPath).exists()) {
        return await initialize(
          detectorModelPath: detectorPath,
          embedderModelPath: embedderPath,
        );
      }

      // Check /data/local/tmp/ (Android ADB push location)
      if (Platform.isAndroid) {
        const tmpDetector =
            '/data/local/tmp/face_models/${FaceModelFiles.faceDetector}';
        const tmpEmbedder =
            '/data/local/tmp/face_models/${FaceModelFiles.faceEmbedder}';

        if (await File(tmpDetector).exists() &&
            await File(tmpEmbedder).exists()) {
          // Copy to app directory for persistence
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

  // ========== Face Indexing ==========

  /// Process a batch of images for face detection and embedding.
  ///
  /// This runs faces through the full pipeline for each image:
  /// detect → align → embed → store.
  ///
  /// Parameters:
  /// - [imageEntries]: List of (imageId, imageBytes) pairs
  /// - [onProgress]: Optional callback for per-image progress
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
        // Per-image failure: skip and continue
        debugPrint('FaceService: Error processing image ${entry.key}: $e');
      }

      processed++;

      // Broadcast progress
      final state = FaceIndexingState(
        processedImages: processed,
        totalImages: total,
        facesFound: facesFound,
      );
      _indexingController.add(state);
      onProgress?.call(state);
    }

    // Run clustering on all accumulated face embeddings
    _runClustering();

    // Persist data
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

  /// Process a batch of images for faces (no clustering).
  ///
  /// Call [finalizeClustering] after all batches are done.
  Future<void> indexImageBatch(
    List<MapEntry<String, Uint8List>> imageEntries,
  ) async {
    if (!isAvailable) return;

    _setStatus(FaceServiceStatus.indexing);

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
        }
      } catch (e) {
        // Per-image failure: skip and continue
      }

      // Yield to event loop between images to prevent ANR
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Run clustering + persistence after all batches are indexed.
  void finalizeClustering() {
    if (_faceRecords.isEmpty) {
      _setStatus(FaceServiceStatus.ready);
      return;
    }

    _runClustering();
    _persistData();
    _setStatus(FaceServiceStatus.ready);

    debugPrint('FaceService: Finalized — '
        '${_faceRecords.length} faces, ${_persons.length} persons');
  }

  /// Process a single image for faces.
  ///
  /// Returns the face records created, or empty list if processing fails.
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

  /// Assign a label to a person cluster.
  ///
  /// Returns true if the label was set successfully.
  bool labelPerson(int personId, String label) {
    final person = _persons[personId];
    if (person == null) return false;

    _persons[personId] = person.copyWith(label: label);

    // Update all face records in this cluster
    for (final faceId in person.faceIds) {
      final record = _faceRecords[faceId];
      if (record != null) {
        _faceRecords[faceId] = record.copyWith(personLabel: label);
      }
    }

    // Persist change
    _persistData();
    debugPrint('FaceService: Labeled person $personId as "$label"');
    return true;
  }

  /// Merge two person clusters into one.
  ///
  /// Use when the user identifies that two clusters are the same person.
  bool mergePersons(int keepPersonId, int mergePersonId) {
    final keep = _persons[keepPersonId];
    final merge = _persons[mergePersonId];
    if (keep == null || merge == null) return false;

    // Move all faces from merge → keep
    final mergedFaceIds = [...keep.faceIds, ...merge.faceIds];

    // Recompute centroid
    final embeddings = mergedFaceIds
        .map((id) => _faceRecords[id]?.embedding)
        .whereType<Float32List>()
        .toList();
    final newCentroid = FaceDbscan.computeCentroid(embeddings);

    _persons[keepPersonId] = keep.copyWith(
      faceIds: mergedFaceIds,
      centroidEmbedding: newCentroid,
    );

    // Update face records
    for (final faceId in merge.faceIds) {
      final record = _faceRecords[faceId];
      if (record != null) {
        _faceRecords[faceId] = record.copyWith(
          clusterId: keepPersonId,
          personLabel: keep.label,
        );
      }
    }

    // Remove merged person
    _persons.remove(mergePersonId);
    _persistData();

    debugPrint('FaceService: Merged person $mergePersonId into $keepPersonId');
    return true;
  }

  // ========== Query / Retrieval ==========

  /// Get all image IDs containing a specific person.
  ///
  /// Returns empty list if person not found or face service unavailable.
  List<String> getImageIdsForPerson(int personId) {
    final person = _persons[personId];
    if (person == null) return [];

    return person.faceIds
        .map((faceId) => _faceRecords[faceId]?.imageId)
        .whereType<String>()
        .toSet()
        .toList();
  }

  /// Find the person matching a given face embedding.
  ///
  /// Returns the best matching person ID, or null if no match.
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

  /// Get a specific person by ID.
  Person? getPerson(int personId) => _persons[personId];

  /// Get a specific face record by ID.
  FaceRecord? getFace(String faceId) => _faceRecords[faceId];

  /// Search for images containing a person by label.
  ///
  /// Returns image IDs of photos containing any person matching [label].
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

  /// Get face service statistics.
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

  /// Clear all face data (records, persons, clusters).
  void clearAllData() {
    _faceRecords.clear();
    _persons.clear();
    _imageFaces.clear();
    _faceIdCounter = 0;
    debugPrint('FaceService: All data cleared');
  }

  /// Dispose of all resources.
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

  /// Run DBSCAN clustering on all face embeddings.
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

      // Build Person objects from clusters
      _persons.clear();
      for (final entry in result.clusters.entries) {
        final clusterId = entry.key;
        final clusterFaceIds = entry.value;

        // Compute centroid
        final clusterEmbeddings = clusterFaceIds
            .map((id) => _faceRecords[id]?.embedding)
            .whereType<Float32List>()
            .toList();
        final centroid = FaceDbscan.computeCentroid(clusterEmbeddings);

        // Find best representative thumbnail (highest confidence)
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

        // Check if this cluster already had a label (from previous clustering)
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

        // Update face records with cluster assignment
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

      // Also create singleton Person entries for noise faces (unclustered).
      // This ensures faces that appear only once still show in the People tab.
      int noisePersonId = 10000;
      for (final faceId in result.noise) {
        final record = _faceRecords[faceId];
        if (record == null) continue;

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
      // Clustering failure is non-fatal — faces are still stored
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

  /// Persist face records and person labels to disk.
  Future<void> _persistData() async {
    try {
      final dir = await _persistPath;
      await Directory(dir).create(recursive: true);

      // Save person labels
      final labels = <String, dynamic>{};
      for (final person in _persons.values) {
        if (person.isLabeled) {
          labels[person.personId.toString()] = person.label;
        }
      }
      await File('$dir/person_labels.json')
          .writeAsString(jsonEncode(labels));

      // Save face-to-image mapping
      final faceMap = <String, Map<String, dynamic>>{};
      for (final record in _faceRecords.values) {
        faceMap[record.faceId] = {
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
        };
      }
      await File('$dir/face_records.json')
          .writeAsString(jsonEncode(faceMap));

      debugPrint('FaceService: Data persisted (${_faceRecords.length} faces, '
          '${labels.length} labels)');
    } catch (e) {
      debugPrint('FaceService: Failed to persist data: $e');
      // Persistence failure is non-fatal
    }
  }

  /// Load persisted person labels from disk.
  Future<void> _loadPersistedData() async {
    try {
      final dir = await _persistPath;
      final labelsFile = File('$dir/person_labels.json');

      if (await labelsFile.exists()) {
        final content = await labelsFile.readAsString();
        final labels = jsonDecode(content) as Map<String, dynamic>;
        debugPrint('FaceService: Loaded ${labels.length} persisted labels');
        // Labels will be applied after clustering
      }
    } catch (e) {
      debugPrint('FaceService: Failed to load persisted data: $e');
      // Load failure is non-fatal
    }
  }
}
