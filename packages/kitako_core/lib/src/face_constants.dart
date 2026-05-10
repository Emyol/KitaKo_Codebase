/// Face recognition constants used across the KitaKo face recognition pipeline.
///
/// These are kept separate from the main constants to maintain modularity —
/// if face recognition is disabled or fails, these constants are simply unused.

/// Default face embedding dimension (ArcFace MobileFaceNet)
const int kFaceEmbeddingDim = 512;

/// Input size for the face recognition model (ArcFace)
const int kFaceInputSize = 112;

/// Input size for the face detection model (SCRFD)
const int kFaceDetectorInputSize = 640;

/// Default minimum confidence for face detection.
/// InsightFace SCRFD uses 0.02 internally and relies on NMS to suppress
/// duplicates. 0.10 is a practical mobile compromise: catches weak detections
/// without flooding NMS with tens of thousands of near-zero candidates.
const double kFaceDetectionConfidenceThreshold = 0.10;

/// Default cosine distance threshold for same-person clustering.
/// InsightFace publishes eps=0.6 for ArcFace DBSCAN clustering.
/// Using 0.6 here matches that reference.
const double kFaceClusteringThreshold = 0.6;

/// Minimum faces to form a person cluster in DBSCAN.
/// 1 = any two faces within eps form a cluster; no face is unreachable
/// just because it only has one similar neighbor.
const int kFaceClusteringMinPoints = 1;

/// Maximum number of faces to process per image
const int kMaxFacesPerImage = 10;

/// Face thumbnail size (pixels, square)
const int kFaceThumbnailSize = 112;

/// Standard ArcFace reference landmarks for 112×112 aligned crop.
///
/// These are the canonical positions used by InsightFace/ArcFace
/// for face alignment before embedding.
const List<List<double>> kArcFaceReferenceLandmarks = [
  [38.2946, 51.6963], // left eye
  [73.5318, 51.5014], // right eye
  [56.0252, 71.7366], // nose tip
  [41.5493, 92.3655], // left mouth corner
  [70.7299, 92.2041], // right mouth corner
];

/// Model file names for face recognition
class FaceModelFiles {
  static const String faceDetector = 'face_detector.onnx';
  static const String faceEmbedder = 'face_embedder.onnx';
}
