import 'dart:typed_data';
import 'dart:ui';

/// Represents a single detected face in an image.
///
/// Contains bounding box, facial landmarks, and detection confidence.
/// This is the output of the face detection stage (SCRFD).
class FaceDetection {
  /// Bounding box of the detected face [x, y, width, height]
  /// Coordinates are in pixels relative to the original image.
  final Rect boundingBox;

  /// Five facial landmarks: left eye, right eye, nose tip,
  /// left mouth corner, right mouth corner.
  ///
  /// Coordinates are in pixels relative to the original image.
  final List<Offset> landmarks;

  /// Detection confidence score (0.0 to 1.0)
  final double confidence;

  const FaceDetection({
    required this.boundingBox,
    required this.landmarks,
    required this.confidence,
  });

  /// Whether this detection has valid landmarks for alignment
  bool get hasLandmarks => landmarks.length == 5;

  /// Center point of the bounding box
  Offset get center => boundingBox.center;

  /// Area of the bounding box in pixels squared
  double get area => boundingBox.width * boundingBox.height;

  @override
  String toString() =>
      'FaceDetection(bbox: $boundingBox, confidence: ${confidence.toStringAsFixed(3)}, '
      'landmarks: ${landmarks.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceDetection &&
          boundingBox == other.boundingBox &&
          confidence == other.confidence;

  @override
  int get hashCode => boundingBox.hashCode ^ confidence.hashCode;
}

/// Represents a face that has been detected, aligned, and embedded.
///
/// This is the primary data model for the face recognition pipeline.
/// Each instance links a face embedding back to its source image.
class FaceRecord {
  /// Unique identifier for this face record
  final String faceId;

  /// ID of the source image containing this face
  final String imageId;

  /// Bounding box of the face in the source image
  final Rect boundingBox;

  /// 512-dimensional face embedding (L2-normalized)
  final Float32List embedding;

  /// Detection confidence score
  final double confidence;

  /// Assigned cluster ID (null if not yet clustered)
  final int? clusterId;

  /// User-assigned person label (null if not yet labeled)
  final String? personLabel;

  /// Thumbnail of the cropped face (JPEG bytes, for UI display)
  final Uint8List? faceThumbnail;

  const FaceRecord({
    required this.faceId,
    required this.imageId,
    required this.boundingBox,
    required this.embedding,
    required this.confidence,
    this.clusterId,
    this.personLabel,
    this.faceThumbnail,
  });

  /// Creates a copy with updated fields
  FaceRecord copyWith({
    String? faceId,
    String? imageId,
    Rect? boundingBox,
    Float32List? embedding,
    double? confidence,
    int? clusterId,
    String? personLabel,
    Uint8List? faceThumbnail,
  }) {
    return FaceRecord(
      faceId: faceId ?? this.faceId,
      imageId: imageId ?? this.imageId,
      boundingBox: boundingBox ?? this.boundingBox,
      embedding: embedding ?? this.embedding,
      confidence: confidence ?? this.confidence,
      clusterId: clusterId ?? this.clusterId,
      personLabel: personLabel ?? this.personLabel,
      faceThumbnail: faceThumbnail ?? this.faceThumbnail,
    );
  }

  /// Whether this face has been assigned to a person cluster
  bool get isClustered => clusterId != null;

  /// Whether this face has a user-assigned label
  bool get isLabeled => personLabel != null && personLabel!.isNotEmpty;

  /// Display name — person label if available, otherwise cluster/face ID
  String get displayName {
    if (isLabeled) return personLabel!;
    if (isClustered) return 'Person $clusterId';
    return 'Unknown ($faceId)';
  }

  @override
  String toString() =>
      'FaceRecord(faceId: $faceId, imageId: $imageId, '
      'cluster: $clusterId, label: $personLabel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceRecord && faceId == other.faceId;

  @override
  int get hashCode => faceId.hashCode;
}

/// Represents a person identified across multiple photos.
///
/// A person is a cluster of face records that have been grouped together
/// by the clustering algorithm and optionally labeled by the user.
class Person {
  /// Unique identifier for this person
  final int personId;

  /// User-assigned label (e.g., "Mom", "Dad")
  final String? label;

  /// Centroid embedding — average of all face embeddings in this cluster
  final Float32List centroidEmbedding;

  /// IDs of all face records belonging to this person
  final List<String> faceIds;

  /// Representative face thumbnail (best quality / highest confidence)
  final Uint8List? representativeThumbnail;

  const Person({
    required this.personId,
    this.label,
    required this.centroidEmbedding,
    required this.faceIds,
    this.representativeThumbnail,
  });

  /// Creates a copy with updated fields
  Person copyWith({
    int? personId,
    String? label,
    Float32List? centroidEmbedding,
    List<String>? faceIds,
    Uint8List? representativeThumbnail,
  }) {
    return Person(
      personId: personId ?? this.personId,
      label: label ?? this.label,
      centroidEmbedding: centroidEmbedding ?? this.centroidEmbedding,
      faceIds: faceIds ?? this.faceIds,
      representativeThumbnail:
          representativeThumbnail ?? this.representativeThumbnail,
    );
  }

  /// Display name — label if available, otherwise generic "Person N"
  String get displayName => label ?? 'Person $personId';

  /// Number of photos this person appears in
  int get photoCount => faceIds.length;

  /// Number of faces in this person's cluster
  int get faceCount => faceIds.length;

  /// Whether this person has been labeled
  bool get isLabeled => label != null && label!.isNotEmpty;

  @override
  String toString() =>
      'Person(id: $personId, label: $label, faces: ${faceIds.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Person && personId == other.personId;

  @override
  int get hashCode => personId.hashCode;
}
