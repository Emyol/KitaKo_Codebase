import 'dart:typed_data';

// Stub implementation used on platforms that don't support dart:ffi (web).
class KitakoFfi {
  /// Returns a deterministic dummy embedding for platforms without FFI.
  Float32List dummyEmbedding768() {
    final out = Float32List(768);
    for (var i = 0; i < 768; i++) {
      out[i] = (i % 100) / 100.0;
    }
    return out;
  }
}
