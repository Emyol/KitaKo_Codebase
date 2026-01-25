import 'dart:typed_data';
import 'package:kitako_ffi/kitako_ffi.dart';

class KitakoFfiBridge {
  KitakoFfi? _ffi;
  Object? lastError;

  Float32List? getDummyEmbedding() {
    try {
      _ffi ??= KitakoFfi();
      return _ffi!.dummyEmbedding768();
    } catch (e) {
      lastError = e;
      return null;
    }
  }
}
