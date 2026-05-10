import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:kitako_core/kitako_core.dart';

/// Aligns a detected face to the standard ArcFace template using
/// a similarity transformation (rotation + scale + translation).
///
/// This is a pure-math module — no ML model is needed. It uses the
/// 5-point facial landmarks from [FaceDetection] to compute an affine
/// transform that maps the detected landmarks to the canonical
/// ArcFace reference positions on a 112×112 output.
///
/// ## Why Alignment Matters
/// ArcFace accuracy drops significantly without proper alignment.
/// The face must be in a standard pose/position before embedding.
///
/// ## Graceful Degradation
/// If landmarks are missing, returns null. The caller can decide
/// whether to skip that face or use a simple center-crop fallback.
class FaceAligner {
  /// Target output size for ArcFace input
  static const int outputSize = kFaceInputSize;

  /// Reference landmarks for ArcFace 112×112 alignment.
  /// Positions: left eye, right eye, nose, left mouth, right mouth.
  static final List<Offset> _referencePoints = kArcFaceReferenceLandmarks
      .map((lm) => Offset(lm[0], lm[1]))
      .toList();

  /// Align a face crop from the source image using detected landmarks.
  ///
  /// Returns a 112×112 RGB image as NCHW Float32List
  /// suitable for ArcFace input, or null if alignment fails.
  ///
  /// Parameters:
  /// - [image]: The source image (decoded)
  /// - [detection]: Face detection with 5-point landmarks
  static Float32List? alignFace(img.Image image, FaceDetection detection) {
    if (!detection.hasLandmarks) {
      return _fallbackCrop(image, detection);
    }

    try {
      // Compute the similarity transform from detected → reference landmarks
      final transform = _estimateSimilarityTransform(
        detection.landmarks,
        _referencePoints,
      );

      if (transform == null) {
        return _fallbackCrop(image, detection);
      }

      // Apply the affine warp to produce a 112×112 aligned face
      final aligned = _warpAffine(image, transform, outputSize, outputSize);

      // Convert to NCHW Float32 normalized for ArcFace: (pixel/255 - 0.5) / 0.5
      return _toNchwFloat32(aligned);
    } catch (e) {
      // On any failure, try fallback crop
      return _fallbackCrop(image, detection);
    }
  }

  /// Align a face from raw image bytes.
  ///
  /// Convenience method that decodes the image first.
  static Float32List? alignFaceFromBytes(
      Uint8List imageBytes, FaceDetection detection) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;
    return alignFace(image, detection);
  }

  /// Extract a face thumbnail (JPEG bytes) for UI display.
  ///
  /// Returns a square crop of the face resized to [thumbnailSize].
  static Uint8List? extractFaceThumbnail(
    img.Image image,
    FaceDetection detection, {
    int thumbnailSize = kFaceThumbnailSize,
  }) {
    try {
      final bbox = detection.boundingBox;

      // Expand bbox slightly for context
      final expand = bbox.width * 0.15;
      final x = (bbox.left - expand).clamp(0, image.width - 1).toInt();
      final y = (bbox.top - expand).clamp(0, image.height - 1).toInt();
      final w = (bbox.width + expand * 2)
          .clamp(1, image.width - x)
          .toInt();
      final h = (bbox.height + expand * 2)
          .clamp(1, image.height - y)
          .toInt();

      // Make it square (use the larger side)
      final side = math.max(w, h);
      final cx = x + w ~/ 2;
      final cy = y + h ~/ 2;
      final sx = (cx - side ~/ 2).clamp(0, image.width - side);
      final sy = (cy - side ~/ 2).clamp(0, image.height - side);

      final cropped = img.copyCrop(
        image,
        x: sx,
        y: sy,
        width: side.clamp(1, image.width - sx),
        height: side.clamp(1, image.height - sy),
      );

      final resized = img.copyResize(
        cropped,
        width: thumbnailSize,
        height: thumbnailSize,
        interpolation: img.Interpolation.linear,
      );

      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (e) {
      return null;
    }
  }

  /// Estimate a 2×3 similarity transform matrix using Umeyama's method.
  ///
  /// Maps [src] points to [dst] points using rotation + uniform scale + translation.
  /// Returns a 2×3 matrix as [a, b, tx, c, d, ty] or null on failure.
  static List<double>? _estimateSimilarityTransform(
    List<Offset> src,
    List<Offset> dst,
  ) {
    if (src.length != dst.length || src.length < 2) return null;

    final n = src.length;

    // Compute centroids
    double srcMeanX = 0, srcMeanY = 0, dstMeanX = 0, dstMeanY = 0;
    for (int i = 0; i < n; i++) {
      srcMeanX += src[i].dx;
      srcMeanY += src[i].dy;
      dstMeanX += dst[i].dx;
      dstMeanY += dst[i].dy;
    }
    srcMeanX /= n;
    srcMeanY /= n;
    dstMeanX /= n;
    dstMeanY /= n;

    // Center points
    final srcCentered = <Offset>[];
    final dstCentered = <Offset>[];
    for (int i = 0; i < n; i++) {
      srcCentered.add(Offset(src[i].dx - srcMeanX, src[i].dy - srcMeanY));
      dstCentered.add(Offset(dst[i].dx - dstMeanX, dst[i].dy - dstMeanY));
    }

    // Compute variance of source
    double srcVar = 0;
    for (int i = 0; i < n; i++) {
      srcVar +=
          srcCentered[i].dx * srcCentered[i].dx +
          srcCentered[i].dy * srcCentered[i].dy;
    }
    srcVar /= n;
    if (srcVar < 1e-10) return null;

    // Compute covariance matrix elements (2×2)
    double cov00 = 0, cov01 = 0, cov10 = 0, cov11 = 0;
    for (int i = 0; i < n; i++) {
      cov00 += dstCentered[i].dx * srcCentered[i].dx;
      cov01 += dstCentered[i].dx * srcCentered[i].dy;
      cov10 += dstCentered[i].dy * srcCentered[i].dx;
      cov11 += dstCentered[i].dy * srcCentered[i].dy;
    }
    cov00 /= n;
    cov01 /= n;
    cov10 /= n;
    cov11 /= n;

    // SVD of 2×2 covariance matrix
    // For a 2×2 matrix, we can compute SVD analytically
    final svd = _svd2x2(cov00, cov01, cov10, cov11);
    if (svd == null) return null;

    final u = svd.u;
    final s = svd.s;
    final v = svd.v;

    // Determine reflection correction
    final detU = u[0] * u[3] - u[1] * u[2];
    final detV = v[0] * v[3] - v[1] * v[2];

    final d = List<double>.filled(2, 1.0);
    if (detU * detV < 0) {
      d[1] = -1.0;
    }

    // Rotation matrix R = U * diag(d) * V^T
    final uD = [
      u[0] * d[0], u[1] * d[1],
      u[2] * d[0], u[3] * d[1],
    ];
    final r = [
      uD[0] * v[0] + uD[1] * v[1], uD[0] * v[2] + uD[1] * v[3],
      uD[2] * v[0] + uD[3] * v[1], uD[2] * v[2] + uD[3] * v[3],
    ];

    // Scale
    final scale = (s[0] * d[0] + s[1] * d[1]) / srcVar;

    // Translation
    final tx = dstMeanX - scale * (r[0] * srcMeanX + r[1] * srcMeanY);
    final ty = dstMeanY - scale * (r[2] * srcMeanX + r[3] * srcMeanY);

    return [
      scale * r[0], scale * r[1], tx,
      scale * r[2], scale * r[3], ty,
    ];
  }

  /// Analytic SVD of a 2×2 matrix.
  static _Svd2x2? _svd2x2(double a, double b, double c, double d) {
    // M = [a b; c d]
    // M^T * M = [a^2+c^2, ab+cd; ab+cd, b^2+d^2]
    final s1 = a * a + b * b + c * c + d * d;
    final s2 = math.sqrt(
        math.pow(a * a + b * b - c * c - d * d, 2) +
            4 * math.pow(a * c + b * d, 2));

    final sig1 = math.sqrt(math.max(0, (s1 + s2) / 2));
    final sig2 = math.sqrt(math.max(0, (s1 - s2) / 2));

    // Compute rotation angles
    final theta =
        0.5 * math.atan2(2 * (a * c + b * d), a * a + b * b - c * c - d * d);
    final phi =
        0.5 * math.atan2(2 * (a * b + c * d), a * a - b * b + c * c - d * d);

    final cosTheta = math.cos(theta);
    final sinTheta = math.sin(theta);
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);

    // U = [cosTheta, -sinTheta; sinTheta, cosTheta]
    final u = [cosTheta, -sinTheta, sinTheta, cosTheta];
    // V^T = [cosPhi, sinPhi; -sinPhi, cosPhi]
    // V = [cosPhi, -sinPhi; sinPhi, cosPhi]
    final v = [cosPhi, -sinPhi, sinPhi, cosPhi];

    return _Svd2x2(u, [sig1, sig2], v);
  }

  /// Apply an affine warp to produce an aligned output image.
  static img.Image _warpAffine(
    img.Image src,
    List<double> transform,
    int outW,
    int outH,
  ) {
    final result = img.Image(width: outW, height: outH);

    // Compute inverse transform for backward mapping
    final inv = _invertAffine(transform);

    for (int y = 0; y < outH; y++) {
      for (int x = 0; x < outW; x++) {
        // Map output pixel to source coordinates
        final srcX = inv[0] * x + inv[1] * y + inv[2];
        final srcY = inv[3] * x + inv[4] * y + inv[5];

        // Bilinear interpolation
        final pixel = _bilinearSample(src, srcX, srcY);
        result.setPixel(x, y, pixel);
      }
    }

    return result;
  }

  /// Invert a 2×3 affine matrix.
  static List<double> _invertAffine(List<double> m) {
    final a = m[0], b = m[1], tx = m[2];
    final c = m[3], d = m[4], ty = m[5];

    final det = a * d - b * c;
    if (det.abs() < 1e-10) return m; // Fallback: no inversion

    final invDet = 1.0 / det;
    return [
      d * invDet,
      -b * invDet,
      (b * ty - d * tx) * invDet,
      -c * invDet,
      a * invDet,
      (c * tx - a * ty) * invDet,
    ];
  }

  /// Bilinear interpolation sampling.
  static img.Color _bilinearSample(img.Image src, double x, double y) {
    final x0 = x.floor().clamp(0, src.width - 1);
    final y0 = y.floor().clamp(0, src.height - 1);
    final x1 = (x0 + 1).clamp(0, src.width - 1);
    final y1 = (y0 + 1).clamp(0, src.height - 1);

    final fx = x - x.floor();
    final fy = y - y.floor();

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    final r = ((1 - fx) * (1 - fy) * p00.r.toDouble() +
            fx * (1 - fy) * p10.r.toDouble() +
            (1 - fx) * fy * p01.r.toDouble() +
            fx * fy * p11.r.toDouble())
        .round()
        .clamp(0, 255);
    final g = ((1 - fx) * (1 - fy) * p00.g.toDouble() +
            fx * (1 - fy) * p10.g.toDouble() +
            (1 - fx) * fy * p01.g.toDouble() +
            fx * fy * p11.g.toDouble())
        .round()
        .clamp(0, 255);
    final b = ((1 - fx) * (1 - fy) * p00.b.toDouble() +
            fx * (1 - fy) * p10.b.toDouble() +
            (1 - fx) * fy * p01.b.toDouble() +
            fx * fy * p11.b.toDouble())
        .round()
        .clamp(0, 255);

    return img.ColorRgb8(r, g, b);
  }

  /// Fallback: simple center-crop without alignment.
  ///
  /// Used when landmarks are not available. Less accurate but still usable.
  static Float32List? _fallbackCrop(img.Image image, FaceDetection detection) {
    try {
      final bbox = detection.boundingBox;
      final x = bbox.left.clamp(0, image.width - 1).toInt();
      final y = bbox.top.clamp(0, image.height - 1).toInt();
      final w = bbox.width.clamp(1, image.width - x).toInt();
      final h = bbox.height.clamp(1, image.height - y).toInt();

      final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
      final resized = img.copyResize(
        cropped,
        width: outputSize,
        height: outputSize,
        interpolation: img.Interpolation.linear,
      );

      return _toNchwFloat32(resized);
    } catch (e) {
      return null;
    }
  }

  /// Convert image to NCHW Float32 with ArcFace normalization.
  ///
  /// InsightFace standard: (pixel - 127.5) / 128.0
  static Float32List _toNchwFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;
    final data = Float32List(3 * h * w);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        final idx = y * w + x;
        data[0 * h * w + idx] = (pixel.r.toDouble() - 127.5) / 128.0; // R
        data[1 * h * w + idx] = (pixel.g.toDouble() - 127.5) / 128.0; // G
        data[2 * h * w + idx] = (pixel.b.toDouble() - 127.5) / 128.0; // B
      }
    }

    return data;
  }
}

/// Internal: SVD result for 2×2 matrix.
class _Svd2x2 {
  final List<double> u;  // 2×2 as flat [4]
  final List<double> s;  // singular values [2]
  final List<double> v;  // 2×2 as flat [4]
  const _Svd2x2(this.u, this.s, this.v);
}
