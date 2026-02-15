/**
 * KitaKo ANN (Approximate Nearest Neighbor) C API
 *
 * This header defines the C ABI for the HNSW-based ANN index.
 * All functions are designed to be safe across the FFI boundary:
 * - No exceptions leak across
 * - Return error codes for failures
 * - Use opaque handles for index lifetime management
 *
 * Usage:
 *   1. Create index: kitako_ann_create(dim, space_type)
 *   2. Load from file: kitako_ann_load(handle, path)
 *   3. Search: kitako_ann_search(handle, query, k, ids, distances)
 *   4. Free: kitako_ann_free(handle)
 *
 * Error codes:
 *   0 = Success
 *   1 = Invalid handle (null)
 *   2 = File not found / IO error
 *   3 = Invalid parameters
 *   4 = Index not loaded
 *   5 = Internal error
 */

#ifndef KITAKO_ANN_H
#define KITAKO_ANN_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define KITAKO_ANN_EXPORT __declspec(dllexport)
#else
#define KITAKO_ANN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

/**
 * Space type for distance computation
 */
typedef enum {
    KITAKO_SPACE_IP = 0,    // Inner Product (for normalized vectors, IP = cosine)
    KITAKO_SPACE_L2 = 1,    // Euclidean (L2) distance
    KITAKO_SPACE_COSINE = 2 // Cosine similarity (normalizes internally)
} KitakoSpaceType;

/**
 * Error codes returned by ANN functions
 */
typedef enum {
    KITAKO_ANN_OK = 0,
    KITAKO_ANN_ERR_NULL_HANDLE = 1,
    KITAKO_ANN_ERR_IO = 2,
    KITAKO_ANN_ERR_INVALID_PARAM = 3,
    KITAKO_ANN_ERR_NOT_LOADED = 4,
    KITAKO_ANN_ERR_INTERNAL = 5
} KitakoAnnError;

/**
 * Opaque handle to an ANN index
 */
typedef void* KitakoAnnHandle;

/**
 * Creates a new ANN index handle.
 *
 * @param dim        Embedding dimension (e.g., 768 for SigLIP)
 * @param space_type Distance metric (0=IP, 1=L2, 2=Cosine)
 * @return           Opaque handle to the index, or NULL on failure
 */
KITAKO_ANN_EXPORT KitakoAnnHandle kitako_ann_create(int32_t dim, int32_t space_type);

/**
 * Loads a pre-built HNSW index from disk.
 *
 * @param handle     The index handle from kitako_ann_create()
 * @param index_path Absolute path to the index file
 * @return           Error code (0 = success)
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_load(KitakoAnnHandle handle, const char* index_path);

/**
 * Searches for the k nearest neighbors of a query vector.
 *
 * @param handle       The index handle
 * @param query        Query vector (float array of length dim)
 * @param k            Number of neighbors to retrieve
 * @param out_ids      Output buffer for IDs (must be allocated, size >= k)
 * @param out_distances Output buffer for distances (must be allocated, size >= k)
 * @return             Error code (0 = success)
 *
 * Note: For Inner Product space with normalized vectors,
 *       distance = 1 - cosine_similarity.
 *       Lower distance = more similar.
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_search(
    KitakoAnnHandle handle,
    const float* query,
    int32_t k,
    int64_t* out_ids,
    float* out_distances
);

/**
 * Gets the number of items in the loaded index.
 *
 * @param handle The index handle
 * @return       Number of items, or -1 if not loaded
 */
KITAKO_ANN_EXPORT int64_t kitako_ann_get_count(KitakoAnnHandle handle);

/**
 * Gets the embedding dimension of the index.
 *
 * @param handle The index handle
 * @return       Dimension, or -1 if invalid handle
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_get_dim(KitakoAnnHandle handle);

/**
 * Sets the ef (search) parameter for query-time accuracy/speed tradeoff.
 *
 * Higher ef = more accurate but slower.
 * Default is typically 50-200.
 *
 * @param handle The index handle
 * @param ef     The ef parameter value
 * @return       Error code (0 = success)
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_set_ef(KitakoAnnHandle handle, int32_t ef);

/**
 * Frees all resources associated with the index handle.
 *
 * @param handle The index handle to free
 */
KITAKO_ANN_EXPORT void kitako_ann_free(KitakoAnnHandle handle);

/**
 * Gets the last error message (for debugging).
 *
 * @return Pointer to static error message string (do not free)
 */
KITAKO_ANN_EXPORT const char* kitako_ann_get_error(void);

// ============================================================================
// Index Building API (for offline index creation)
// ============================================================================

/**
 * Initializes an empty index for building.
 *
 * @param handle            The index handle
 * @param max_elements      Maximum number of elements the index can hold
 * @param M                 HNSW M parameter (default: 16)
 * @param ef_construction   HNSW ef_construction parameter (default: 200)
 * @return                  Error code (0 = success)
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_init_index(
    KitakoAnnHandle handle,
    int64_t max_elements,
    int32_t M,
    int32_t ef_construction
);

/**
 * Adds a single vector to the index.
 *
 * @param handle The index handle
 * @param data   The vector data (float array of length dim)
 * @param id     The ID to associate with this vector
 * @return       Error code (0 = success)
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_add_item(
    KitakoAnnHandle handle,
    const float* data,
    int64_t id
);

/**
 * Saves the index to disk.
 *
 * @param handle     The index handle
 * @param index_path Path where to save the index
 * @return           Error code (0 = success)
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_save(KitakoAnnHandle handle, const char* index_path);

// ============================================================================
// Metrics API (for diagnosing HNSW vs brute force behavior)
// ============================================================================

/**
 * Gets the number of distance computations performed in the last search.
 *
 * Compare this against the total index size to verify HNSW is doing
 * approximate (not brute-force) search.
 * - HNSW: distance_computations << index_size (typically ef * avg_degree)
 * - Brute force: distance_computations == index_size
 *
 * @param handle The index handle
 * @return       Number of distance computations, or -1 on error
 */
KITAKO_ANN_EXPORT int64_t kitako_ann_get_distance_computations(KitakoAnnHandle handle);

/**
 * Gets the number of hops (graph traversals) in the last search.
 *
 * @param handle The index handle
 * @return       Number of hops, or -1 on error
 */
KITAKO_ANN_EXPORT int64_t kitako_ann_get_hops(KitakoAnnHandle handle);

/**
 * Resets the internal metric counters to zero.
 * Call this before a search to get accurate per-search metrics.
 *
 * @param handle The index handle
 * @return       Error code (0 = success)
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_reset_metrics(KitakoAnnHandle handle);

/**
 * Gets the current ef (search) parameter value.
 *
 * @param handle The index handle
 * @return       Current ef value, or -1 on error
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_get_ef(KitakoAnnHandle handle);

/**
 * Gets the maximum level (number of layers) in the HNSW graph.
 *
 * @param handle The index handle
 * @return       Max level, or -1 on error
 */
KITAKO_ANN_EXPORT int32_t kitako_ann_get_max_level(KitakoAnnHandle handle);

#ifdef __cplusplus
}
#endif

#endif // KITAKO_ANN_H
