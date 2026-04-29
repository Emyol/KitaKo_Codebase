import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:kitako_core/kitako_core.dart';

import 'face_aligner.dart';
import 'onnx_face_detector.dart';
import 'onnx_face_embedder.dart';

/// Result of processing a single face in an image.
class FacePipelineResult {
  final FaceDetection detection;
  final Float32List embedding;
  final Uint8List? thumbnail;

  const FacePipelineResult({
    required this.detection,
    required this.embedding,
    this.thumbnail,
  });
}

/// Orchestrates the full face recognition pipeline:
/// detect → align → embed (→ optional thumbnail).
///
/// This class combines [OnnxFaceDetector], [FaceAligner], and
/// [OnnxFaceEmbedder] into a single high-level API. Each stage
/// has independent error handling — a failure in one face does
/// not affect processing of other faces.
///
/// ## Graceful Degradation
/// - If detector model is missing → [isReady] is false, all methods
///   return empty results. The rest of KitaKo works normally.
/// - If embedder model is missing → detection still works but embedding
///   returns null per-face, which is logged and skipped.
/// - If alignment fails for a face → fallback crop is used.
///
/// ## Usage
/// ```dart
/// final pipeline = FacePipeline();
/// final ready = await pipeline.initialize(
///   detectorModelPath: '/path/to/scrfd.onnx',
///   embedderModelPath: '/path/to/arcface.onnx',
/// );
/// if (ready) {
///   final results = pipeline.processImage(imageBytes);
///   for (final r in results) {
///     print('Face at ${r.detection.boundingBox}, embedding dim: ${r.embedding.length}');
///   }
/// }
/// ```
class FacePipeline {
  final OnnxFaceDetector _detector = OnnxFaceDetector();
  final OnnxFaceEmbedder _embedder = OnnxFaceEmbedder();

  /// Whether both the detector and embedder are ready.
  bool get isReady => _detector.isReady && _embedder.isReady;

  /// Whether at least the detector is ready (can detect without embedding).
  bool get canDetect => _detector.isReady;

  /// Whether the embedder is ready.
  bool get canEmbed => _embedder.isReady;

  /// Access to the underlying detector (for advanced usage).
  OnnxFaceDetector get detector => _detector;

  /// Access to the underlying embedder (for advanced usage).
  OnnxFaceEmbedder get embedder => _embedder;

  /// Initialize the face pipeline with model paths.
  ///
  /// Returns true if at least the detector loaded successfully.
  /// Embedder failure is logged but not fatal — detection still works.
  ///
  /// This method NEVER throws. It logs errors and returns false on
  /// complete failure, or true even if only detection is available.
  Future<bool> initialize({
    required String detectorModelPath,
    required String embedderModelPath,
  }) async {
    try {
      _detector.initialize();
      _embedder.initialize();
    } catch (e) {
      debugPrint('FacePipeline: ONNX env init error (may be shared): $e');
    }

    final detReady = await _detector.loadModel(detectorModelPath);
    final embReady = await _embedder.loadModel(embedderModelPath);

    debugPrint('FacePipeline: Initialized — '
        'detector: $detReady, embedder: $embReady');

    return detReady;
  }

  /// Process an image through the full pipeline.
  ///
  /// Detects all faces, aligns each face, generates embeddings,
  /// and optionally extracts thumbnails.
  ///
  /// Returns a list of [FacePipelineResult] for each successfully
  /// processed face. Faces that fail alignment or embedding are skipped
  /// with a debug log (partial results are still returned).
  ///
  /// Parameters:
  /// - [imageBytes]: Raw image data (JPEG, PNG, etc.)
  /// - [confidenceThreshold]: Minimum face detection confidence
  /// - [maxFaces]: Maximum number of faces to process per image
  /// - [extractThumbnails]: Whether to generate face thumbnails for UI
  List<FacePipelineResult> processImage(
    Uint8List imageBytes, {
    double confidenceThreshold = kFaceDetectionConfidenceThreshold,
    int maxFaces = kMaxFacesPerImage,
    bool extractThumbnails = true,
  }) {
    if (!canDetect) {
      debugPrint('FacePipeline: Detector not ready, skipping');
      return [];
    }

    try {
      // Decode image once — shared by detection, alignment, and thumbnails
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('FacePipeline: Could not decode image');
        return [];
      }

      // Stage 1: Detect faces (uses pre-decoded image to avoid double decode)
      final detections = _detector.detectFacesFromImage(
        image,
        confidenceThreshold: confidenceThreshold,
      );

      if (detections.isEmpty) return [];

      // Limit faces per image
      final facesToProcess =
          detections.length > maxFaces ? detections.sublist(0, maxFaces) : detections;

      final results = <FacePipelineResult>[];

      for (final detection in facesToProcess) {
        try {
          // Stage 2: Align face
          final aligned = FaceAligner.alignFace(image, detection);
          if (aligned == null) {
            debugPrint('FacePipeline: Alignment failed for face at '
                '${detection.boundingBox}, skipping');
            continue;
          }

          // Stage 3: Generate embedding
          if (!canEmbed) {
            debugPrint('FacePipeline: Embedder not ready, skipping embedding');
            continue;
          }

          final embedding = _embedder.embedFace(aligned);
          if (embedding == null) {
            debugPrint('FacePipeline: Embedding failed for face at '
                '${detection.boundingBox}, skipping');
            continue;
          }

          // Stage 4 (optional): Extract thumbnail
          Uint8List? thumbnail;
          if (extractThumbnails) {
            thumbnail =
                FaceAligner.extractFaceThumbnail(image, detection);
          }

          results.add(FacePipelineResult(
            detection: detection,
            embedding: embedding,
            thumbnail: thumbnail,
          ));
        } catch (e) {
          // Per-face failure — skip this face, continue with others
          debugPrint('FacePipeline: Error processing face: $e');
        }
      }

      if (results.isNotEmpty) {
        debugPrint('FacePipeline: Processed ${results.length}/${facesToProcess.length} faces');
      }
      return results;
    } catch (e) {
      debugPrint('FacePipeline: Image processing failed: $e');
      return [];
    }
  }

  /// Detect faces only (without alignment or embedding).
  ///
  /// Useful for quick face detection without the full pipeline.
  List<FaceDetection> detectOnly(
    Uint8List imageBytes, {
    double confidenceThreshold = kFaceDetectionConfidenceThreshold,
  }) {
    if (!canDetect) return [];
    return _detector.detectFaces(
      imageBytes,
      confidenceThreshold: confidenceThreshold,
    );
  }

  /// Release all resources.
  void dispose() {
    _detector.dispose();
    _embedder.dispose();
    debugPrint('FacePipeline: Disposed');
  }
}
