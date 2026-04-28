/// KitaKo Face Recognition Module
///
/// Provides face detection, alignment, embedding, and clustering
/// for person identification in photos.
///
/// ## Components
/// - [OnnxFaceDetector]: SCRFD-based face detection
/// - [FaceAligner]: Affine alignment using facial landmarks
/// - [OnnxFaceEmbedder]: ArcFace-based face embedding generation
/// - [FaceDbscan]: DBSCAN clustering for person grouping
/// - [FacePipeline]: High-level orchestrator (detect → align → embed)
///
/// ## Graceful Degradation
/// All components are designed to fail safely. If face models are not
/// available, `isReady` returns false and methods return empty results.
/// The rest of the KitaKo system is unaffected.
library kitako_embedding.face;

export 'face_aligner.dart';
export 'face_dbscan.dart';
export 'face_pipeline.dart';
export 'onnx_face_detector.dart';
export 'onnx_face_embedder.dart';
