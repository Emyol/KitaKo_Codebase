import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:kitako_core/kitako_core.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

/// ONNX-based face detector using SCRFD (Sample and Computation
/// Redistribution for Face Detection).
///
/// Detects faces in images and returns bounding boxes, 5-point facial
/// landmarks, and confidence scores. The landmarks are used for face
/// alignment before embedding.
///
/// ## Model Details
/// - **Model**: SCRFD-2.5G with keypoints
/// - **Input**: RGB image [1, 3, 640, 640] NCHW Float32
/// - **Output**: Bounding boxes, scores, landmarks (multi-scale)
/// - **Size**: ~3 MB
///
/// ## Graceful Degradation
/// If the SCRFD model is not available or fails to load, [isReady]
/// returns false and all detection methods return empty results.
/// The rest of the KitaKo system continues to function normally.
class OnnxFaceDetector {
  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _isReady = false;
  bool _loggedOutputShapes = false;

  /// Input image size expected by the SCRFD model
  static const int inputSize = kFaceDetectorInputSize;

  /// Whether the detector model is loaded and ready
  bool get isReady => _isReady;

  /// Initialize the ONNX Runtime environment for face detection.
  ///
  /// This is safe to call even if OrtEnv is already initialized by
  /// [OnnxSiglipInference] — the ONNX Runtime handles multiple inits.
  void initialize() {
    try {
      OrtEnv.instance.init();
      _sessionOptions = OrtSessionOptions();
      debugPrint('OnnxFaceDetector: Initialized');
    } catch (e) {
      debugPrint('OnnxFaceDetector: Init failed (may already be initialized): $e');
      // OrtEnv may already be initialized by SigLIP — that's fine
      _sessionOptions ??= OrtSessionOptions();
    }
  }

  /// Load the SCRFD face detection model from a file path or asset.
  ///
  /// Returns true if successful, false otherwise. Does NOT throw — this
  /// is intentional for graceful degradation.
  Future<bool> loadModel(String modelPath) async {
    try {
      if (_sessionOptions == null) initialize();

      if (modelPath.startsWith('assets/')) {
        final data = await rootBundle.load(modelPath);
        final bytes = data.buffer.asUint8List();
        _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      } else {
        final file = File(modelPath);
        if (!await file.exists()) {
          debugPrint('OnnxFaceDetector: Model file not found: $modelPath');
          return false;
        }
        _session = OrtSession.fromFile(file, _sessionOptions!);
      }

      _isReady = true;
      debugPrint('OnnxFaceDetector: Model loaded from $modelPath');

      if (_session != null) {
        debugPrint('OnnxFaceDetector: Output names: ${_session!.outputNames}');
      }

      return true;
    } catch (e) {
      _isReady = false;
      debugPrint('OnnxFaceDetector: Failed to load model: $e');
      return false;
    }
  }

  /// Detect faces in an image.
  ///
  /// Returns a list of [FaceDetection] objects, each containing a bounding
  /// box, 5-point landmarks, and confidence score.
  ///
  /// If the detector is not ready, returns an empty list (graceful degradation).
  ///
  /// Parameters:
  /// - [imageBytes]: Raw image data (JPEG, PNG, etc.)
  /// - [confidenceThreshold]: Minimum confidence to keep a detection
  /// - [nmsThreshold]: IoU threshold for Non-Maximum Suppression
  List<FaceDetection> detectFaces(
    Uint8List imageBytes, {
    double confidenceThreshold = kFaceDetectionConfidenceThreshold,
    double nmsThreshold = 0.45,
  }) {
    if (!_isReady || _session == null) {
      debugPrint('OnnxFaceDetector: Not ready, returning empty results');
      return [];
    }

    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('OnnxFaceDetector: Failed to decode image');
        return [];
      }
      return detectFacesFromImage(
        image,
        confidenceThreshold: confidenceThreshold,
        nmsThreshold: nmsThreshold,
      );
    } catch (e) {
      debugPrint('OnnxFaceDetector: Detection failed: $e');
      return [];
    }
  }

  /// Detect faces from a pre-decoded image.
  ///
  /// Use this to avoid decoding the same image twice when the caller
  /// also needs the decoded image (e.g., for face alignment).
  List<FaceDetection> detectFacesFromImage(
    img.Image image, {
    double confidenceThreshold = kFaceDetectionConfidenceThreshold,
    double nmsThreshold = 0.45,
  }) {
    if (!_isReady || _session == null) {
      debugPrint('OnnxFaceDetector: Not ready, returning empty results');
      return [];
    }

    try {
      final originalWidth = image.width;
      final originalHeight = image.height;

      // Letterbox resize: maintain aspect ratio, pad to square with gray
      final ratio = math.min(
        inputSize / originalWidth,
        inputSize / originalHeight,
      );
      final newW = (originalWidth * ratio).round();
      final newH = (originalHeight * ratio).round();
      final padX = (inputSize - newW) ~/ 2;
      final padY = (inputSize - newH) ~/ 2;

      final resized = img.copyResize(
        image,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.linear,
      );

      // Convert to NCHW Float32 with letterbox padding
      final inputData = _preprocessImageLetterbox(
        resized, padX, padY, newW, newH,
      );

      // Run inference
      final shape = [1, 3, inputSize, inputSize];
      final inputTensor =
          OrtValueTensor.createTensorWithDataList(inputData, shape);
      final runOptions = OrtRunOptions();
      final inputs = {'input.1': inputTensor};

      List<OrtValue?> outputs;
      try {
        outputs = _session!.run(runOptions, inputs);
      } catch (e) {
        // Try alternative input name
        try {
          outputs = _session!.run(runOptions, {'images': inputTensor});
        } catch (e2) {
          debugPrint('OnnxFaceDetector: Inference failed: $e2');
          inputTensor.release();
          runOptions.release();
          return [];
        }
      }

      // Parse SCRFD multi-scale output with letterbox unscaling
      final detections = _parseOutputs(
        outputs,
        originalWidth,
        originalHeight,
        confidenceThreshold,
        ratio,
        padX,
        padY,
      );

      // Release resources
      inputTensor.release();
      runOptions.release();
      for (final output in outputs) {
        output?.release();
      }

      // Apply NMS
      final nmsDetections = _nonMaxSuppression(detections, nmsThreshold);

      if (nmsDetections.isNotEmpty) {
        debugPrint(
            'OnnxFaceDetector: Found ${nmsDetections.length} faces');
      }

      return nmsDetections;
    } catch (e) {
      debugPrint('OnnxFaceDetector: Detection failed: $e');
      return [];
    }
  }

  /// Preprocess a letterbox-resized image to NCHW Float32 [1, 3, 640, 640].
  ///
  /// The resized image is placed at (padX, padY) on a 640×640 canvas.
  /// Padding area is filled with ~0.0 (equivalent to gray=128 after
  /// SCRFD normalization: (128 - 127.5) / 128.0 ≈ 0).
  Float32List _preprocessImageLetterbox(
    img.Image resized, int padX, int padY, int newW, int newH,
  ) {
    final total = inputSize * inputSize;
    final data = Float32List(3 * total);
    // Padding stays at 0.0 ≈ neutral gray after normalization

    for (int y = 0; y < newH; y++) {
      for (int x = 0; x < newW; x++) {
        final pixel = resized.getPixel(x, y);
        final outIdx = (y + padY) * inputSize + (x + padX);
        data[0 * total + outIdx] = (pixel.r.toDouble() - 127.5) / 128.0;
        data[1 * total + outIdx] = (pixel.g.toDouble() - 127.5) / 128.0;
        data[2 * total + outIdx] = (pixel.b.toDouble() - 127.5) / 128.0;
      }
    }

    return data;
  }

  /// Parse multi-scale SCRFD outputs into face detections.
  ///
  /// SCRFD outputs feature maps at 3 scales (stride 8, 16, 32).
  /// Each scale produces scores, bounding boxes, and landmarks.
  List<FaceDetection> _parseOutputs(
    List<OrtValue?> outputs,
    int originalWidth,
    int originalHeight,
    double confidenceThreshold,
    double ratio,
    int padX,
    int padY,
  ) {
    final detections = <FaceDetection>[];

    // Letterbox unscaling: convert model coords back to original image
    // originalCoord = (modelCoord - pad) / ratio
    final invRatio = 1.0 / ratio;
    final padXd = padX.toDouble();
    final padYd = padY.toDouble();

    // SCRFD outputs: [score_8, score_16, score_32, bbox_8, bbox_16, bbox_32, kps_8, kps_16, kps_32]
    // But actual output structure depends on the model export.
    // We do a flexible parse: try to read scores, boxes, keypoints.

    try {
      final outputNames = _session!.outputNames;

      // Group outputs by type
      final scores = <List<dynamic>>[];
      final boxes = <List<dynamic>>[];
      final keypoints = <List<dynamic>>[];

      for (int i = 0; i < outputs.length; i++) {
        final output = outputs[i];
        if (output == null) continue;
        final value = output.value;

        final name = i < outputNames.length ? outputNames[i] : 'output_$i';
        if (name.contains('score') || name.contains('cls')) {
          scores.add(value as List<dynamic>);
        } else if (name.contains('bbox') || name.contains('box')) {
          boxes.add(value as List<dynamic>);
        } else if (name.contains('kps') || name.contains('landmark')) {
          keypoints.add(value as List<dynamic>);
        }
      }

      // If we couldn't identify all groups by name, fall back to positional.
      // Standard SCRFD: 9 outputs = 3 scores + 3 boxes + 3 keypoints.
      // Trigger when scores OR boxes are empty to handle partial name-match.
      if ((scores.isEmpty || boxes.isEmpty) && outputs.length >= 9) {
        scores.clear();
        boxes.clear();
        keypoints.clear();
        for (int i = 0; i < 3; i++) {
          if (outputs[i]?.value != null) {
            scores.add(outputs[i]!.value as List<dynamic>);
          }
        }
        for (int i = 3; i < 6; i++) {
          if (outputs[i]?.value != null) {
            boxes.add(outputs[i]!.value as List<dynamic>);
          }
        }
        for (int i = 6; i < 9; i++) {
          if (outputs[i]?.value != null) {
            keypoints.add(outputs[i]!.value as List<dynamic>);
          }
        }
      }

      // One-time debug: log output shapes and per-scale max scores
      if (!_loggedOutputShapes) {
        _loggedOutputShapes = true;
        for (int i = 0; i < outputs.length; i++) {
          if (outputs[i]?.value != null) {
            final flat = _flattenToDoubles(outputs[i]!.value as List<dynamic>);
            debugPrint('OnnxFaceDetector: output[$i] name=${outputNames[i]} flatSize=${flat.length}');
          }
        }
        final diagStrides = <int>[8, 16, 32];
        for (int i = 0; i < scores.length; i++) {
          final flatS = _flattenToDoubles(scores[i]);
          final maxScore = flatS.isEmpty ? 0.0 : flatS.reduce((a, b) => a > b ? a : b);
          final maxSigmoid = maxScore > 1.0 || maxScore < 0.0
              ? 1.0 / (1.0 + math.exp(-maxScore))
              : maxScore;
          final stride = i < diagStrides.length ? diagStrides[i] : i;
          debugPrint('OnnxFaceDetector: scores[$i] stride=$stride '
              'flatSize=${flatS.length} '
              'maxRaw=${maxScore.toStringAsFixed(4)} '
              'maxSigmoid=${maxSigmoid.toStringAsFixed(4)}');
        }
        for (int i = 0; i < boxes.length; i++) {
          final flatB = _flattenToDoubles(boxes[i]);
          debugPrint('OnnxFaceDetector: boxes[$i] flatSize=${flatB.length}');
        }
      }

      // Parse each scale
      final strides = [8, 16, 32];
      for (int scaleIdx = 0;
          scaleIdx < scores.length && scaleIdx < boxes.length;
          scaleIdx++) {
        final stride = scaleIdx < strides.length ? strides[scaleIdx] : 8;

        final scaleDetections = _parseScale(
          scores[scaleIdx],
          boxes[scaleIdx],
          scaleIdx < keypoints.length ? keypoints[scaleIdx] : null,
          stride,
          invRatio,
          padXd,
          padYd,
          confidenceThreshold,
        );

        detections.addAll(scaleDetections);
      }
    } catch (e) {
      debugPrint('OnnxFaceDetector: Output parsing failed, '
          'attempting fallback parse: $e');

      // Fallback: Try to parse as simple [N, 5+] format
      _parseFallback(
          outputs, detections, invRatio, padXd, padYd, confidenceThreshold);
    }

    return detections;
  }

  /// Parse detections from a single scale of SCRFD output.
  List<FaceDetection> _parseScale(
    List<dynamic> scoreData,
    List<dynamic> boxData,
    List<dynamic>? kpsData,
    int stride,
    double invRatio,
    double padX,
    double padY,
    double confidenceThreshold,
  ) {
    final detections = <FaceDetection>[];

    try {
      // Flatten nested lists
      final flatScores = _flattenToDoubles(scoreData);
      final flatBoxes = _flattenToDoubles(boxData);
      final flatKps = kpsData != null ? _flattenToDoubles(kpsData) : null;

      final gridH = inputSize ~/ stride;
      final gridW = inputSize ~/ stride;
      final numAnchors = flatScores.length ~/ (gridH * gridW);

      for (int i = 0; i < flatScores.length; i++) {
        final score = flatScores[i];
        // Apply sigmoid if scores are logits
        final confidence = score > 1.0 || score < 0.0
            ? 1.0 / (1.0 + math.exp(-score))
            : score;

        if (confidence < confidenceThreshold) continue;

        // Compute anchor position
        final anchorIdx = i ~/ numAnchors;
        final cy = (anchorIdx ~/ gridW) * stride;
        final cx = (anchorIdx % gridW) * stride;

        // Decode bounding box (distance from anchor)
        final boxOffset = i * 4;
        if (boxOffset + 3 >= flatBoxes.length) continue;

        final x1 = (cx - flatBoxes[boxOffset + 0] * stride - padX) * invRatio;
        final y1 = (cy - flatBoxes[boxOffset + 1] * stride - padY) * invRatio;
        final x2 = (cx + flatBoxes[boxOffset + 2] * stride - padX) * invRatio;
        final y2 = (cy + flatBoxes[boxOffset + 3] * stride - padY) * invRatio;

        final bbox = Rect.fromLTRB(
          x1.clamp(0.0, double.infinity),
          y1.clamp(0.0, double.infinity),
          x2.clamp(0.0, double.infinity),
          y2.clamp(0.0, double.infinity),
        );

        // Reject non-face detections: too small or wrong aspect ratio.
        // 10 px in model-input space to capture small faces in group shots.
        // 2.5:1 aspect-ratio cap removes text banners, logos, thin strips.
        final bboxWModel = bbox.width / invRatio;
        final bboxHModel = bbox.height / invRatio;
        if (bboxWModel < 10.0 || bboxHModel < 10.0) continue;
        if (bboxHModel > 0 &&
            (bboxWModel / bboxHModel > 2.5 ||
                bboxHModel / bboxWModel > 2.5)) continue;

        // Decode landmarks
        final landmarks = <Offset>[];
        if (flatKps != null) {
          final kpsOffset = i * 10; // 5 landmarks × 2 coords
          if (kpsOffset + 9 < flatKps.length) {
            for (int lm = 0; lm < 5; lm++) {
              final lx =
                  (cx + flatKps[kpsOffset + lm * 2] * stride - padX) * invRatio;
              final ly =
                  (cy + flatKps[kpsOffset + lm * 2 + 1] * stride - padY) * invRatio;
              landmarks.add(Offset(lx, ly));
            }
          }
        }

        // Geometry check with 35% slack — tolerates tilted/angled faces
        // while rejecting completely wrong landmark layouts (cartoons, logos).
        if (landmarks.length == 5) {
          final leftEye = landmarks[0];
          final rightEye = landmarks[1];
          final nose = landmarks[2];
          final leftMouth = landmarks[3];
          final rightMouth = landmarks[4];
          final slack = bbox.height * 0.35;
          final eyeMidY = (leftEye.dy + rightEye.dy) / 2;
          if (nose.dy < eyeMidY - slack) continue;
          if (leftMouth.dy < nose.dy - slack) continue;
          if (rightMouth.dy < nose.dy - slack) continue;
          final eyeDist = (rightEye.dx - leftEye.dx).abs();
          if (eyeDist < bbox.width * 0.08) continue;
        }

        detections.add(FaceDetection(
          boundingBox: bbox,
          landmarks: landmarks,
          confidence: confidence,
        ));
      }
    } catch (e) {
      debugPrint('OnnxFaceDetector: Scale parsing error: $e');
    }

    return detections;
  }

  /// Fallback parser for simple output formats.
  void _parseFallback(
    List<OrtValue?> outputs,
    List<FaceDetection> detections,
    double invRatio,
    double padX,
    double padY,
    double confidenceThreshold,
  ) {
    try {
      for (final output in outputs) {
        if (output == null) continue;
        final value = output.value;
        final flat = _flattenToDoubles(value as List<dynamic>);

        // Try to interpret as [N, 15] or [N, 5] format
        // [x1, y1, x2, y2, score, lm0x, lm0y, lm1x, lm1y, ...]
        final stride = flat.length > 15 * 10 ? 15 : 5;

        for (int i = 0; i + stride <= flat.length; i += stride) {
          final score = flat[i + 4];
          final confidence = score > 1.0 || score < 0.0
              ? 1.0 / (1.0 + math.exp(-score))
              : score;

          if (confidence < confidenceThreshold) continue;

          final bbox = Rect.fromLTRB(
            (flat[i + 0] - padX) * invRatio,
            (flat[i + 1] - padY) * invRatio,
            (flat[i + 2] - padX) * invRatio,
            (flat[i + 3] - padY) * invRatio,
          );

          final landmarks = <Offset>[];
          if (stride >= 15) {
            for (int lm = 0; lm < 5; lm++) {
              landmarks.add(Offset(
                (flat[i + 5 + lm * 2] - padX) * invRatio,
                (flat[i + 5 + lm * 2 + 1] - padY) * invRatio,
              ));
            }
          }

          detections.add(FaceDetection(
            boundingBox: bbox,
            landmarks: landmarks,
            confidence: confidence,
          ));
        }
      }
    } catch (e) {
      debugPrint('OnnxFaceDetector: Fallback parse also failed: $e');
    }
  }

  /// Flatten arbitrarily nested List into a flat List<double>.
  List<double> _flattenToDoubles(List<dynamic> nested) {
    final result = <double>[];
    _flattenRecursive(nested, result);
    return result;
  }

  void _flattenRecursive(dynamic value, List<double> result) {
    if (value is num) {
      result.add(value.toDouble());
    } else if (value is List) {
      for (final item in value) {
        _flattenRecursive(item, result);
      }
    }
  }

  /// Non-Maximum Suppression to remove overlapping detections.
  List<FaceDetection> _nonMaxSuppression(
    List<FaceDetection> detections,
    double iouThreshold,
  ) {
    if (detections.isEmpty) return detections;

    // Sort by confidence (highest first)
    final sorted = List<FaceDetection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <FaceDetection>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (int i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;
      kept.add(sorted[i]);

      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        if (_computeIoU(sorted[i].boundingBox, sorted[j].boundingBox) >
            iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
  }

  /// Compute Intersection over Union (IoU) between two bounding boxes.
  double _computeIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea = a.width * a.height + b.width * b.height - intersectionArea;

    return unionArea > 0 ? intersectionArea / unionArea : 0.0;
  }

  /// Release all resources.
  void dispose() {
    _session?.release();
    _sessionOptions?.release();
    _session = null;
    _sessionOptions = null;
    _isReady = false;
    debugPrint('OnnxFaceDetector: Disposed');
  }
}
