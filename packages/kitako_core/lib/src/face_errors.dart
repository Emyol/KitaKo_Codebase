import 'errors.dart';

/// Exception thrown when face detection fails
class FaceDetectionException extends KitakoException {
  const FaceDetectionException(super.message, [super.cause]);
}

/// Exception thrown when face alignment fails
class FaceAlignmentException extends KitakoException {
  const FaceAlignmentException(super.message, [super.cause]);
}

/// Exception thrown when face embedding generation fails
class FaceEmbeddingException extends KitakoException {
  const FaceEmbeddingException(super.message, [super.cause]);
}

/// Exception thrown when face clustering fails
class FaceClusteringException extends KitakoException {
  const FaceClusteringException(super.message, [super.cause]);
}

/// Exception thrown when face recognition pipeline fails
class FaceRecognitionException extends KitakoException {
  const FaceRecognitionException(super.message, [super.cause]);
}
