#ifndef KITAKO_FFI_H
#define KITAKO_FFI_H

#include <stdint.h>

#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Fills out[0..out_len-1] with deterministic dummy embedding values.
 * Used for testing FFI bridge connectivity.
 */
FFI_PLUGIN_EXPORT void kitako_dummy_embed(float* out, int32_t out_len);

#ifdef __cplusplus
}
#endif

#endif // KITAKO_FFI_H
