#include "kitako_ffi.h"

// Fills `out[0..out_len-1]` with deterministic dummy values.
FFI_PLUGIN_EXPORT void kitako_dummy_embed(float* out, int32_t out_len) {
  if (!out || out_len < 768) return;

  for (int32_t i = 0; i < 768; i++) {
    // simple deterministic pattern; later replace with real inference output
    out[i] = (float)(i % 100) / 100.0f;
  }
}
