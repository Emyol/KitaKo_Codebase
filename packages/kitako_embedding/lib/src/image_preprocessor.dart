import 'dart:typed_data';

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
  static Float32List preprocessImage(Uint8List imageBytes) {
    // Decode the image
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw ArgumentError('Could not decode image');
    }

    return preprocessDecodedImage(image);
  }

  /// Preprocesses an already-decoded image.
  ///
  /// [image] - Decoded image object
  ///
  /// Returns a Float32List ready for model input.
  static Float32List preprocessDecodedImage(img.Image image) {
    // Resize to 224x224 using bilinear interpolation (resample=2 in config)
    final resized = img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to RGB if necessary and normalize
    final Float32List result = Float32List(1 * targetSize * targetSize * 3);
    int idx = 0;

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
        result[idx++] = (r * rescaleFactor - imageMean) / imageStd;
        result[idx++] = (g * rescaleFactor - imageMean) / imageStd;
        result[idx++] = (b * rescaleFactor - imageMean) / imageStd;
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
  /// Returns a preprocessed 224x224 gray image.
  static Float32List createTestImage() {
    final Float32List result = Float32List(1 * targetSize * targetSize * 3);

    // Fill with gray (0.0 after normalization)
    for (int i = 0; i < result.length; i++) {
      result[i] = 0.0;
    }

    return result;
  }
}
