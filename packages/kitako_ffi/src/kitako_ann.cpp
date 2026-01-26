/**
 * KitaKo ANN Implementation
 *
 * HNSW-based Approximate Nearest Neighbor search using hnswlib.
 * This implementation wraps hnswlib with a C ABI for FFI compatibility.
 *
 * Key design decisions:
 * - Thread-safe via mutex protection
 * - No exceptions leak across FFI boundary
 * - Error messages stored in thread-local buffer
 * - Inner Product space for normalized embeddings (cosine similarity)
 */

#include "kitako_ann.h"
#include "hnswlib/hnswlib.h"

#include <cstring>
#include <mutex>
#include <memory>
#include <string>

// Thread-local error message buffer
static thread_local char g_error_message[512] = {0};

static void set_error(const char* msg) {
    strncpy(g_error_message, msg, sizeof(g_error_message) - 1);
    g_error_message[sizeof(g_error_message) - 1] = '\0';
}

/**
 * Internal index wrapper holding hnswlib components
 */
struct KitakoAnnIndex {
    int32_t dim;
    KitakoSpaceType space_type;
    
    std::unique_ptr<hnswlib::SpaceInterface<float>> space;
    std::unique_ptr<hnswlib::HierarchicalNSW<float>> hnsw;
    
    bool is_loaded;
    bool is_initialized;
    std::mutex mtx;
    
    KitakoAnnIndex(int32_t d, KitakoSpaceType st)
        : dim(d), space_type(st), is_loaded(false), is_initialized(false) {
        // Create appropriate space based on type
        switch (st) {
            case KITAKO_SPACE_IP:
                space = std::make_unique<hnswlib::InnerProductSpace>(d);
                break;
            case KITAKO_SPACE_L2:
                space = std::make_unique<hnswlib::L2Space>(d);
                break;
            case KITAKO_SPACE_COSINE:
                // Cosine uses IP space but normalizes vectors internally
                space = std::make_unique<hnswlib::InnerProductSpace>(d);
                break;
            default:
                space = std::make_unique<hnswlib::InnerProductSpace>(d);
                break;
        }
    }
};

extern "C" {

KITAKO_ANN_EXPORT KitakoAnnHandle kitako_ann_create(int32_t dim, int32_t space_type) {
    if (dim <= 0 || dim > 4096) {
        set_error("Invalid dimension (must be 1-4096)");
        return nullptr;
    }
    
    if (space_type < 0 || space_type > 2) {
        set_error("Invalid space type (must be 0=IP, 1=L2, 2=Cosine)");
        return nullptr;
    }
    
    try {
        auto* index = new KitakoAnnIndex(dim, static_cast<KitakoSpaceType>(space_type));
        return static_cast<KitakoAnnHandle>(index);
    } catch (const std::exception& e) {
        set_error(e.what());
        return nullptr;
    } catch (...) {
        set_error("Unknown error during index creation");
        return nullptr;
    }
}

KITAKO_ANN_EXPORT int32_t kitako_ann_load(KitakoAnnHandle handle, const char* index_path) {
    if (!handle) {
        set_error("Null handle");
        return KITAKO_ANN_ERR_NULL_HANDLE;
    }
    
    if (!index_path || index_path[0] == '\0') {
        set_error("Invalid index path");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    try {
        // Load the index from file
        index->hnsw = std::make_unique<hnswlib::HierarchicalNSW<float>>(
            index->space.get(), 
            std::string(index_path)
        );
        
        index->is_loaded = true;
        index->is_initialized = true;
        return KITAKO_ANN_OK;
        
    } catch (const std::runtime_error& e) {
        std::string msg = "IO error: ";
        msg += e.what();
        set_error(msg.c_str());
        return KITAKO_ANN_ERR_IO;
    } catch (const std::exception& e) {
        set_error(e.what());
        return KITAKO_ANN_ERR_INTERNAL;
    } catch (...) {
        set_error("Unknown error during index load");
        return KITAKO_ANN_ERR_INTERNAL;
    }
}

KITAKO_ANN_EXPORT int32_t kitako_ann_search(
    KitakoAnnHandle handle,
    const float* query,
    int32_t k,
    int64_t* out_ids,
    float* out_distances
) {
    if (!handle) {
        set_error("Null handle");
        return KITAKO_ANN_ERR_NULL_HANDLE;
    }
    
    if (!query || !out_ids || !out_distances) {
        set_error("Null pointer in search parameters");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    if (k <= 0 || k > 10000) {
        set_error("Invalid k value (must be 1-10000)");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    if (!index->is_loaded || !index->hnsw) {
        set_error("Index not loaded");
        return KITAKO_ANN_ERR_NOT_LOADED;
    }
    
    try {
        // Handle case where k > number of elements
        size_t elem_count = index->hnsw->cur_element_count.load();
        size_t actual_k = (static_cast<size_t>(k) < elem_count) ? static_cast<size_t>(k) : elem_count;
        
        if (actual_k == 0) {
            // Empty index, return zeros
            for (int32_t i = 0; i < k; i++) {
                out_ids[i] = -1;
                out_distances[i] = -1.0f;
            }
            return KITAKO_ANN_OK;
        }
        
        // For cosine space, normalize the query vector
        std::vector<float> normalized_query;
        const float* search_query = query;
        
        if (index->space_type == KITAKO_SPACE_COSINE) {
            normalized_query.resize(index->dim);
            float norm = 0.0f;
            for (int32_t i = 0; i < index->dim; i++) {
                norm += query[i] * query[i];
            }
            norm = std::sqrt(norm);
            if (norm > 0) {
                for (int32_t i = 0; i < index->dim; i++) {
                    normalized_query[i] = query[i] / norm;
                }
            } else {
                std::memcpy(normalized_query.data(), query, index->dim * sizeof(float));
            }
            search_query = normalized_query.data();
        }
        
        // Perform the search
        auto result = index->hnsw->searchKnn(search_query, actual_k);
        
        // Extract results (priority queue returns in reverse order - largest distance first)
        // We need smallest distance first for similarity ranking
        std::vector<std::pair<float, int64_t>> results;
        results.reserve(actual_k);
        
        while (!result.empty()) {
            results.push_back({result.top().first, static_cast<int64_t>(result.top().second)});
            result.pop();
        }
        
        // Reverse to get smallest distance first
        std::reverse(results.begin(), results.end());
        
        // Fill output buffers
        for (size_t i = 0; i < actual_k; i++) {
            out_ids[i] = results[i].second;
            out_distances[i] = results[i].first;
        }
        
        // Fill remaining slots with invalid markers if k > actual results
        for (size_t i = actual_k; i < static_cast<size_t>(k); i++) {
            out_ids[i] = -1;
            out_distances[i] = -1.0f;
        }
        
        return KITAKO_ANN_OK;
        
    } catch (const std::exception& e) {
        set_error(e.what());
        return KITAKO_ANN_ERR_INTERNAL;
    } catch (...) {
        set_error("Unknown error during search");
        return KITAKO_ANN_ERR_INTERNAL;
    }
}

KITAKO_ANN_EXPORT int64_t kitako_ann_get_count(KitakoAnnHandle handle) {
    if (!handle) {
        return -1;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    if (!index->is_loaded || !index->hnsw) {
        return -1;
    }
    
    return static_cast<int64_t>(index->hnsw->cur_element_count);
}

KITAKO_ANN_EXPORT int32_t kitako_ann_get_dim(KitakoAnnHandle handle) {
    if (!handle) {
        return -1;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    return index->dim;
}

KITAKO_ANN_EXPORT int32_t kitako_ann_set_ef(KitakoAnnHandle handle, int32_t ef) {
    if (!handle) {
        set_error("Null handle");
        return KITAKO_ANN_ERR_NULL_HANDLE;
    }
    
    if (ef <= 0 || ef > 10000) {
        set_error("Invalid ef value (must be 1-10000)");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    if (!index->is_loaded || !index->hnsw) {
        set_error("Index not loaded");
        return KITAKO_ANN_ERR_NOT_LOADED;
    }
    
    try {
        index->hnsw->setEf(static_cast<size_t>(ef));
        return KITAKO_ANN_OK;
    } catch (...) {
        set_error("Failed to set ef parameter");
        return KITAKO_ANN_ERR_INTERNAL;
    }
}

KITAKO_ANN_EXPORT void kitako_ann_free(KitakoAnnHandle handle) {
    if (!handle) {
        return;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    
    // Lock and release resources
    {
        std::lock_guard<std::mutex> lock(index->mtx);
        index->hnsw.reset();
        index->space.reset();
        index->is_loaded = false;
        index->is_initialized = false;
    }
    
    delete index;
}

KITAKO_ANN_EXPORT const char* kitako_ann_get_error(void) {
    return g_error_message;
}

// ============================================================================
// Index Building API
// ============================================================================

KITAKO_ANN_EXPORT int32_t kitako_ann_init_index(
    KitakoAnnHandle handle,
    int64_t max_elements,
    int32_t M,
    int32_t ef_construction
) {
    if (!handle) {
        set_error("Null handle");
        return KITAKO_ANN_ERR_NULL_HANDLE;
    }
    
    if (max_elements <= 0 || max_elements > 100000000) {
        set_error("Invalid max_elements (must be 1-100M)");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    if (M <= 0 || M > 200) {
        set_error("Invalid M (must be 1-200)");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    if (ef_construction <= 0 || ef_construction > 2000) {
        set_error("Invalid ef_construction (must be 1-2000)");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    try {
        index->hnsw = std::make_unique<hnswlib::HierarchicalNSW<float>>(
            index->space.get(),
            static_cast<size_t>(max_elements),
            static_cast<size_t>(M),
            static_cast<size_t>(ef_construction)
        );
        
        index->is_initialized = true;
        index->is_loaded = true; // Can be used for searching
        return KITAKO_ANN_OK;
        
    } catch (const std::exception& e) {
        set_error(e.what());
        return KITAKO_ANN_ERR_INTERNAL;
    } catch (...) {
        set_error("Unknown error during index initialization");
        return KITAKO_ANN_ERR_INTERNAL;
    }
}

KITAKO_ANN_EXPORT int32_t kitako_ann_add_item(
    KitakoAnnHandle handle,
    const float* data,
    int64_t id
) {
    if (!handle) {
        set_error("Null handle");
        return KITAKO_ANN_ERR_NULL_HANDLE;
    }
    
    if (!data) {
        set_error("Null data pointer");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    if (id < 0) {
        set_error("Invalid ID (must be >= 0)");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    if (!index->is_initialized || !index->hnsw) {
        set_error("Index not initialized. Call kitako_ann_init_index first.");
        return KITAKO_ANN_ERR_NOT_LOADED;
    }
    
    try {
        // For cosine space, normalize the vector before adding
        std::vector<float> normalized_data;
        const float* add_data = data;
        
        if (index->space_type == KITAKO_SPACE_COSINE) {
            normalized_data.resize(index->dim);
            float norm = 0.0f;
            for (int32_t i = 0; i < index->dim; i++) {
                norm += data[i] * data[i];
            }
            norm = std::sqrt(norm);
            if (norm > 0) {
                for (int32_t i = 0; i < index->dim; i++) {
                    normalized_data[i] = data[i] / norm;
                }
            } else {
                std::memcpy(normalized_data.data(), data, index->dim * sizeof(float));
            }
            add_data = normalized_data.data();
        }
        
        index->hnsw->addPoint(add_data, static_cast<size_t>(id));
        return KITAKO_ANN_OK;
        
    } catch (const std::exception& e) {
        set_error(e.what());
        return KITAKO_ANN_ERR_INTERNAL;
    } catch (...) {
        set_error("Unknown error during item addition");
        return KITAKO_ANN_ERR_INTERNAL;
    }
}

KITAKO_ANN_EXPORT int32_t kitako_ann_save(KitakoAnnHandle handle, const char* index_path) {
    if (!handle) {
        set_error("Null handle");
        return KITAKO_ANN_ERR_NULL_HANDLE;
    }
    
    if (!index_path || index_path[0] == '\0') {
        set_error("Invalid index path");
        return KITAKO_ANN_ERR_INVALID_PARAM;
    }
    
    auto* index = static_cast<KitakoAnnIndex*>(handle);
    std::lock_guard<std::mutex> lock(index->mtx);
    
    if (!index->is_initialized || !index->hnsw) {
        set_error("Index not initialized");
        return KITAKO_ANN_ERR_NOT_LOADED;
    }
    
    try {
        index->hnsw->saveIndex(std::string(index_path));
        return KITAKO_ANN_OK;
        
    } catch (const std::runtime_error& e) {
        std::string msg = "IO error: ";
        msg += e.what();
        set_error(msg.c_str());
        return KITAKO_ANN_ERR_IO;
    } catch (const std::exception& e) {
        set_error(e.what());
        return KITAKO_ANN_ERR_INTERNAL;
    } catch (...) {
        set_error("Unknown error during index save");
        return KITAKO_ANN_ERR_INTERNAL;
    }
}

} // extern "C"
