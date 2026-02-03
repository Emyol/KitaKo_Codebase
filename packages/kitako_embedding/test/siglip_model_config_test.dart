import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  group('SigLIP Model Configuration Tests', () {
    test('SigLIP-1 configuration has correct parameters', () {
      final config = SiglipModelConfig.siglip1Config;

      expect(config.version, SiglipModelVersion.siglip1);
      expect(config.vocabularySize, 32000);
      expect(config.imageSize, 224);
      expect(config.embeddingDimension, 768);
      expect(config.maxTextLength, 64);
      expect(config.visionOutputTensorName, 'pooler_output');
      expect(config.textOutputTensorName, 'pooler_output');
      expect(config.hasProjectionLayer, false);
    });

    test('SigLIP-2 configuration has correct parameters', () {
      final config = SiglipModelConfig.siglip2Config;

      expect(config.version, SiglipModelVersion.siglip2);
      expect(config.vocabularySize, 256000);
      expect(config.imageSize, 256);
      expect(config.embeddingDimension, 768);
      expect(config.maxTextLength, 64);
      expect(config.hasProjectionLayer, true);
    });

    test('forVersion returns correct configuration', () {
      final config1 = SiglipModelConfig.forVersion(SiglipModelVersion.siglip1);
      expect(config1.version, SiglipModelVersion.siglip1);
      expect(config1.imageSize, 224);

      final config2 = SiglipModelConfig.forVersion(SiglipModelVersion.siglip2);
      expect(config2.version, SiglipModelVersion.siglip2);
      expect(config2.imageSize, 256);
    });

    test('Configuration toString includes key information', () {
      final config = SiglipModelConfig.siglip2Config;
      final str = config.toString();

      expect(str, contains('siglip2'));
      expect(str, contains('256000')); // vocab size
      expect(str, contains('256')); // image size
      expect(str, contains('768')); // embedding dim
      expect(str, contains('true')); // has projection
    });
  });

  group('OnnxSiglipInference Configuration Tests', () {
    test('Initialize with SigLIP-1 configuration', () {
      final inference = OnnxSiglipInference();
      inference.initialize(modelVersion: SiglipModelVersion.siglip1);

      expect(inference.modelVersion, SiglipModelVersion.siglip1);
      expect(inference.imageSize, 224);
      expect(inference.embeddingDim, 768);
      expect(inference.config.vocabularySize, 32000);
    });

    test('Initialize with SigLIP-2 configuration', () {
      final inference = OnnxSiglipInference();
      inference.initialize(modelVersion: SiglipModelVersion.siglip2);

      expect(inference.modelVersion, SiglipModelVersion.siglip2);
      expect(inference.imageSize, 256);
      expect(inference.embeddingDim, 768);
      expect(inference.config.vocabularySize, 256000);
      expect(inference.config.hasProjectionLayer, true);
    });

    test('Default initialization uses SigLIP-1', () {
      final inference = OnnxSiglipInference();
      inference.initialize();

      expect(inference.modelVersion, SiglipModelVersion.siglip1);
      expect(inference.imageSize, 224);
    });
  });
}
