import 'package:flutter_test/flutter_test.dart';
import 'package:kitako_embedding/kitako_embedding.dart';

void main() {
  test('SiglipModelConfig.siglip2Config has correct parameters', () {
    final config = SiglipModelConfig.siglip2Config;
    expect(config.version, SiglipModelVersion.siglip2);
    expect(config.imageSize, 224);
    expect(config.embeddingDimension, 768);
    expect(config.vocabularySize, 256000);
  });
}
