import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Image preprocessor for SigLIP model.
///
/// Handles resizing, normalization, and format conversion for the
/// image encoder model.
class ImagePreprocessor {
  /// Target image size for SigLIP (224x224)
  static const int targetSize = 224;

  /// Preprocessing constants from preprocessor_config.json
  static const double rescaleFactor = 1.0 / 255.0; // 0.00392156862745098
  static const double imageMean = 0.5;
  static const double imageStd = 0.5;

  /// Preprocesses an image for the SigLIP image encoder.
  ///
  /// [imageBytes] - Raw image bytes (PNG, JPEG, etc.)
  ///
  /// Returns a Float32List of shape [1, 224, 224, 3] with values
  /// normalized to [-1, 1] using mean=0.5 and std=0.5.
  ///
  /// NOTE: This uses pure Dart and can be slow for large images.
  /// Use [preprocessImageAsync] for better performance on large images.
  static Float32List preprocessImage(Uint8List imageBytes) {
    // Decode the image
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }

    return preprocessDecodedImage(image);
  }

  /// Preprocesses an image asynchronously in a background isolate.
  ///
  /// This is significantly faster for large images as it doesn't block
  /// the main thread and can utilize background processing.
  static Future<Float32List> preprocessImageAsync(Uint8List imageBytes) async {
    return compute(_preprocessInIsolate, imageBytes);
  }

  /// Preprocesses already-decoded RGBA bytes in a background isolate.
  ///
  /// Use this with [ImageLoaderService.loadResizedForEmbedding] to avoid
  /// decoding full-resolution JPEGs in the isolate. The RGBA bytes must be
  /// tightly packed (width × height × 4 bytes, row-major).
  static Future<Float32List> preprocessRgbaAsync(
      Uint8List rgba, int width, int height) {
    return compute(
      _preprocessRgbaInIsolate,
      (rgba: rgba, width: width, height: height),
    );
  }

  static Float32List _preprocessRgbaInIsolate(
      ({Uint8List rgba, int width, int height}) args) {
    final image = img.Image.fromBytes(
      width: args.width,
      height: args.height,
      bytes: args.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return _preprocessDecodedImageFast(image);
  }

  /// Internal function that runs in isolate
  static Float32List _preprocessInIsolate(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }
    return _preprocessDecodedImageFast(image);
  }

  /// Fast preprocessing - decodes at reduced size if possible
  static Float32List _preprocessDecodedImageFast(img.Image image) {
    // If image is much larger than target, use nearest neighbor for speed
    // then do a final bilinear pass at small size
    img.Image resized;

    if (image.width > targetSize * 4 || image.height > targetSize * 4) {
      // First pass: quick resize to 2x target using nearest neighbor
      final intermediateSize = targetSize * 2;
      final intermediate = img.copyResize(
        image,
        width: intermediateSize,
        height: intermediateSize,
        interpolation: img.Interpolation.nearest,
      );
      // Second pass: bilinear to final size
      resized = img.copyResize(
        intermediate,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.linear,
      );
    } else {
      // Image is small enough for direct bilinear resize
      resized = img.copyResize(
        image,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.linear,
      );
    }

    // Convert to normalized float array in NCHW format [1, 3, 224, 224]
    // (batch, channels, height, width) - required by ONNX SigLIP model
    final Float32List result = Float32List(1 * 3 * targetSize * targetSize);
    final int channelSize = targetSize * targetSize;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        final pixelIdx = y * targetSize + x;
        // Channel-first layout: R plane, then G plane, then B plane
        result[0 * channelSize + pixelIdx] = (r * rescaleFactor - imageMean) / imageStd;
        result[1 * channelSize + pixelIdx] = (g * rescaleFactor - imageMean) / imageStd;
        result[2 * channelSize + pixelIdx] = (b * rescaleFactor - imageMean) / imageStd;
      }
    }

    return result;
  }

  /// Preprocesses an already-decoded image.
  ///
  /// [image] - Decoded image object
  ///
  /// Returns a Float32List ready for model input in NCHW format [1, 3, 224, 224].
  static Float32List preprocessDecodedImage(img.Image image) {
    // Resize to 224x224 using bilinear interpolation (resample=2 in config)
    final resized = img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to RGB if necessary and normalize in NCHW format
    // (batch, channels, height, width) - required by ONNX SigLIP model
    final Float32List result = Float32List(1 * 3 * targetSize * targetSize);
    final int channelSize = targetSize * targetSize;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final pixel = resized.getPixel(x, y);

        // Get RGB values (0-255)
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        // Apply preprocessing:
        // 1. Rescale: value * (1/255) -> [0, 1]
        // 2. Normalize: (value - mean) / std -> with mean=0.5, std=0.5: [0,1] -> [-1, 1]
        // Combined: ((value / 255) - 0.5) / 0.5 = (value / 255 - 0.5) * 2 = value / 127.5 - 1
        final pixelIdx = y * targetSize + x;
        // Channel-first layout: R plane, then G plane, then B plane
        result[0 * channelSize + pixelIdx] = (r * rescaleFactor - imageMean) / imageStd;
        result[1 * channelSize + pixelIdx] = (g * rescaleFactor - imageMean) / imageStd;
        result[2 * channelSize + pixelIdx] = (b * rescaleFactor - imageMean) / imageStd;
      }
    }

    return result;
  }

  /// Preprocesses an image from raw RGB bytes (already decoded).
  ///
  /// [rgbBytes] - Raw RGB pixel data
  /// [width] - Image width
  /// [height] - Image height
  ///
  /// Returns a Float32List ready for model input.
  static Float32List preprocessRgbBytes(
    Uint8List rgbBytes,
    int width,
    int height,
  ) {
    // Create image from raw bytes
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbBytes.buffer,
      numChannels: 3,
    );

    return preprocessDecodedImage(image);
  }

  /// Creates a placeholder/test image for validation.
  ///
  /// Returns a preprocessed 224x224 gray image in NCHW format [1, 3, 224, 224].
  static Float32List createTestImage() {
    final Float32List result = Float32List(1 * 3 * targetSize * targetSize);

    // Fill with gray (0.0 after normalization)
    for (int i = 0; i < result.length; i++) {
      result[i] = 0.0;
    }

    return result;
  }
}
