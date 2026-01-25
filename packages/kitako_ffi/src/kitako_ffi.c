#include <stdint.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// Fills `out[0..767]` with deterministic dummy values.
EXPORT void kitako_dummy_embed(float* out, int32_t out_len) {
  if (!out || out_len < 768) return;

  for (int32_t i = 0; i < 768; i++) {
    // simple deterministic pattern; later replace with real inference output
    out[i] = (float)(i % 100) / 100.0f;
  }
}
