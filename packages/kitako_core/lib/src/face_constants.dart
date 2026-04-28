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

/// Default minimum confidence for face detection
const double kFaceDetectionConfidenceThreshold = 0.3;

/// Default cosine distance threshold for same-person clustering
/// Lower = stricter (fewer false merges), Higher = more lenient
/// ArcFace typical range: 0.3–0.5 cosine distance
const double kFaceClusteringThreshold = 0.45;

/// Minimum faces to form a person cluster in DBSCAN
const int kFaceClusteringMinPoints = 2;

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
