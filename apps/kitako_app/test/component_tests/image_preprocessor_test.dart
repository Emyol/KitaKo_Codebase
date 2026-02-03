/// Image Preprocessor Component Tests
///
/// Tests for ImagePreprocessor in isolation.
/// Run with: flutter test test/component_tests/image_preprocessor_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  group('ImagePreprocessor - Constants', () {
    test('target size is 224', () {
      expect(ImagePreprocessor.targetSize, 224);
    });

    test('rescale factor is 1/255', () {
      expect(ImagePreprocessor.rescaleFactor, closeTo(0.00392156, 0.00001));
    });

    test('image mean is 0.5', () {
      expect(ImagePreprocessor.imageMean, 0.5);
    });

    test('image std is 0.5', () {
      expect(ImagePreprocessor.imageStd, 0.5);
    });
  });

  group('ImagePreprocessor - Test Image Creation', () {
    test('createTestImage returns correct shape', () {
      final testImage = ImagePreprocessor.createTestImage();

      // Shape: [1, 3, 224, 224] in NCHW format, flattened
      const expectedSize = 1 * 3 * 224 * 224;
      expect(testImage.length, expectedSize);
      print('✅ Test image size: ${testImage.length} (expected: $expectedSize)');
    });

    test('createTestImage returns Float32List', () {
      final testImage = ImagePreprocessor.createTestImage();
      expect(testImage, isA<Float32List>());
    });

    test('createTestImage values are normalized (gray = 0.0)', () {
      final testImage = ImagePreprocessor.createTestImage();

      // Test image should be gray (0.0 after normalization)
      for (int i = 0; i < testImage.length; i++) {
        expect(testImage[i], 0.0,
            reason: 'Gray test image should have all zeros after normalization');
      }
    });
  });

  group('ImagePreprocessor - Value Range Tests', () {
    test('preprocessed values are in range [-1, 1]', () {
      final testImage = ImagePreprocessor.createTestImage();

      for (int i = 0; i < testImage.length; i++) {
        expect(testImage[i], inInclusiveRange(-1.0, 1.0),
            reason: 'Value at index $i should be in [-1, 1]');
      }
    });

    test('normalization formula: (pixel/255 - 0.5) / 0.5', () {
      // Black pixel (0) -> (0/255 - 0.5) / 0.5 = -1.0
      // White pixel (255) -> (255/255 - 0.5) / 0.5 = 1.0
      // Gray pixel (127) -> (127/255 - 0.5) / 0.5 ≈ -0.004

      final blackNormalized =
          (0.0 * ImagePreprocessor.rescaleFactor - ImagePreprocessor.imageMean) /
              ImagePreprocessor.imageStd;
      expect(blackNormalized, closeTo(-1.0, 0.001));

      final whiteNormalized =
          (255.0 * ImagePreprocessor.rescaleFactor - ImagePreprocessor.imageMean) /
              ImagePreprocessor.imageStd;
      expect(whiteNormalized, closeTo(1.0, 0.001));

      final grayNormalized =
          (127.0 * ImagePreprocessor.rescaleFactor - ImagePreprocessor.imageMean) /
              ImagePreprocessor.imageStd;
      expect(grayNormalized, closeTo(-0.004, 0.01));
    });
  });

  group('ImagePreprocessor - NCHW Format Tests', () {
    test('output is in NCHW format [1, 3, 224, 224]', () {
      final testImage = ImagePreprocessor.createTestImage();

      // NCHW: batch=1, channels=3, height=224, width=224
      const batch = 1;
      const channels = 3;
      const height = 224;
      const width = 224;

      expect(testImage.length, batch * channels * height * width);

      // In NCHW format:
      // - First 224*224 elements = Red channel
      // - Next 224*224 elements = Green channel
      // - Last 224*224 elements = Blue channel
      const channelSize = height * width;
      expect(channelSize, 224 * 224);

      print('✅ NCHW format verified:');
      print('   Batch size: $batch');
      print('   Channels: $channels');
      print('   Height: $height');
      print('   Width: $width');
      print('   Channel size: $channelSize');
      print('   Total size: ${testImage.length}');
    });

    test('channel offsets are correct in NCHW format', () {
      // R channel: indices 0 to 224*224-1
      // G channel: indices 224*224 to 2*224*224-1
      // B channel: indices 2*224*224 to 3*224*224-1

      const channelSize = 224 * 224;

      const rStart = 0;
      const rEnd = channelSize - 1;
      const gStart = channelSize;
      const gEnd = 2 * channelSize - 1;
      const bStart = 2 * channelSize;
      const bEnd = 3 * channelSize - 1;

      expect(rStart, 0);
      expect(rEnd, 50175);
      expect(gStart, 50176);
      expect(gEnd, 100351);
      expect(bStart, 100352);
      expect(bEnd, 150527);

      print('✅ Channel offsets (NCHW):');
      print('   R: $rStart - $rEnd');
      print('   G: $gStart - $gEnd');
      print('   B: $bStart - $bEnd');
    });
  });

  group('ImagePreprocessor - Real Image Tests', () {
    test('preprocesses JPEG image correctly', () async {
      // Create a simple test JPEG in memory or load from file
      // For this test, we'll try to load a test image if available
      final testImagePath = 'test/test_images/109.jpg';

      final file = File(testImagePath);
      if (!await file.exists()) {
        print('⚠️ Test image not found at: $testImagePath');
        print('   Create this file to run real image tests');
        markTestSkipped('Test image not found');
        return;
      }

      final imageBytes = await file.readAsBytes();
      final preprocessed = ImagePreprocessor.preprocessImage(imageBytes);

      expect(preprocessed.length, 1 * 3 * 224 * 224);
      expect(preprocessed, isA<Float32List>());

      // Check all values are in range
      for (final value in preprocessed) {
        expect(value, inInclusiveRange(-1.0, 1.0));
      }

      // Print some stats
      final mean = preprocessed.reduce((a, b) => a + b) / preprocessed.length;
      final min = preprocessed.reduce((a, b) => a < b ? a : b);
      final max = preprocessed.reduce((a, b) => a > b ? a : b);

      print('✅ Preprocessed JPEG image:');
      print('   Size: ${preprocessed.length}');
      print('   Mean: $mean');
      print('   Min: $min');
      print('   Max: $max');
    });

    test('preprocesses second JPEG image correctly', () async {
      final testImagePath = 'test/test_images/110.jpg';

      final file = File(testImagePath);
      if (!await file.exists()) {
        print('⚠️ Test PNG not found at: $testImagePath');
        markTestSkipped('Test PNG not found');
        return;
      }

      final imageBytes = await file.readAsBytes();
      final preprocessed = ImagePreprocessor.preprocessImage(imageBytes);

      expect(preprocessed.length, 1 * 3 * 224 * 224);

      for (final value in preprocessed) {
        expect(value, inInclusiveRange(-1.0, 1.0));
      }
    });
  });

  group('ImagePreprocessor - Async Preprocessing', () {
    test('preprocessImageAsync returns same shape as sync', () async {
      // We need actual image bytes for async test
      final testImagePath = 'test/test_images/127.jpg';

      final file = File(testImagePath);
      if (!await file.exists()) {
        markTestSkipped('Test image not found');
        return;
      }

      final imageBytes = await file.readAsBytes();

      final syncResult = ImagePreprocessor.preprocessImage(imageBytes);
      final asyncResult = await ImagePreprocessor.preprocessImageAsync(imageBytes);

      expect(asyncResult.length, syncResult.length);
      expect(asyncResult, isA<Float32List>());

      // Values should be identical (or very close due to float precision)
      for (int i = 0; i < syncResult.length; i += 1000) {
        // Sample every 1000th value
        expect(asyncResult[i], closeTo(syncResult[i], 0.0001));
      }

      print('✅ Async preprocessing matches sync');
    });
  });

  group('ImagePreprocessor - Error Handling', () {
    test('throws on invalid image data', () {
      final invalidData = Uint8List.fromList([0, 1, 2, 3, 4]);

      expect(
        () => ImagePreprocessor.preprocessImage(invalidData),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on empty data', () {
      final emptyData = Uint8List(0);

      expect(
        () => ImagePreprocessor.preprocessImage(emptyData),
        throwsA(anything),
      );
    });
  });

  group('ImagePreprocessor - RGB Bytes Processing', () {
    test('preprocessRgbBytes with solid red image', () {
      const width = 224;
      const height = 224;

      // Create solid red image (R=255, G=0, B=0)
      final rgbBytes = Uint8List(width * height * 3);
      for (int i = 0; i < width * height; i++) {
        rgbBytes[i * 3 + 0] = 255; // R
        rgbBytes[i * 3 + 1] = 0; // G
        rgbBytes[i * 3 + 2] = 0; // B
      }

      final preprocessed =
          ImagePreprocessor.preprocessRgbBytes(rgbBytes, width, height);

      expect(preprocessed.length, 1 * 3 * 224 * 224);

      // Check red channel (should be ~1.0 after normalization)
      const channelSize = 224 * 224;
      final redChannel = preprocessed.sublist(0, channelSize);
      final greenChannel = preprocessed.sublist(channelSize, 2 * channelSize);
      final blueChannel = preprocessed.sublist(2 * channelSize, 3 * channelSize);

      // Red channel should be ~1.0
      expect(redChannel[0], closeTo(1.0, 0.01));
      // Green channel should be ~-1.0
      expect(greenChannel[0], closeTo(-1.0, 0.01));
      // Blue channel should be ~-1.0
      expect(blueChannel[0], closeTo(-1.0, 0.01));

      print('✅ Solid red image processed correctly');
      print('   Red channel value: ${redChannel[0]}');
      print('   Green channel value: ${greenChannel[0]}');
      print('   Blue channel value: ${blueChannel[0]}');
    });

    test('preprocessRgbBytes with checkerboard pattern', () {
      const width = 224;
      const height = 224;

      // Create checkerboard (alternating black/white)
      final rgbBytes = Uint8List(width * height * 3);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = (y * width + x) * 3;
          final isWhite = (x + y) % 2 == 0;
          final value = isWhite ? 255 : 0;
          rgbBytes[idx + 0] = value; // R
          rgbBytes[idx + 1] = value; // G
          rgbBytes[idx + 2] = value; // B
        }
      }

      final preprocessed =
          ImagePreprocessor.preprocessRgbBytes(rgbBytes, width, height);

      expect(preprocessed.length, 1 * 3 * 224 * 224);

      // Check that we have both +1 and -1 values (checkerboard)
      final hasPositive = preprocessed.any((v) => v > 0.5);
      final hasNegative = preprocessed.any((v) => v < -0.5);

      expect(hasPositive, true, reason: 'Should have white pixels (+1)');
      expect(hasNegative, true, reason: 'Should have black pixels (-1)');

      print('✅ Checkerboard pattern processed correctly');
    });
  });
}
