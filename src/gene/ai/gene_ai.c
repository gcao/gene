// Gene AI C Implementation
// Provides tensor and model operations for Gene language

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

// Export macro for shared library visibility
#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

// Simple tensor structure for Gene
typedef struct {
    float* data;
    int* shape;
    int ndim;
    int size;
    char* device;  // "cpu" or "cuda"
} GeneTensor;

// Tokenizer structure
typedef struct {
    int vocab_size;
    char** vocab;
} GeneTokenizer;

// Model structure
typedef struct {
    char* name;
    char* type;
    void* weights;
    int num_params;
} GeneModel;

// Device structure
typedef struct {
    char* type;  // "cpu", "cuda", "metal"
    int id;
} GeneDevice;

// Helper function to calculate tensor size
static int calculate_size(int* shape, int ndim) {
    int size = 1;
    for (int i = 0; i < ndim; i++) {
        size *= shape[i];
    }
    return size;
}

// Tensor operations
GeneTensor* gene_tensor_create(int* shape, int ndim, const char* dtype, const char* device) {
    GeneTensor* tensor = (GeneTensor*)malloc(sizeof(GeneTensor));
    if (!tensor) return NULL;
    
    tensor->ndim = ndim;
    tensor->shape = (int*)malloc(ndim * sizeof(int));
    memcpy(tensor->shape, shape, ndim * sizeof(int));
    
    tensor->size = calculate_size(shape, ndim);
    tensor->data = (float*)calloc(tensor->size, sizeof(float));
    
    tensor->device = strdup(device ? device : "cpu");
    
    return tensor;
}

void gene_tensor_free(GeneTensor* tensor) {
    if (tensor) {
        free(tensor->data);
        free(tensor->shape);
        free(tensor->device);
        free(tensor);
    }
}

GeneTensor* gene_tensor_random(int* shape, int ndim) {
    GeneTensor* tensor = gene_tensor_create(shape, ndim, "float32", "cpu");
    if (!tensor) return NULL;
    
    // Fill with random values
    for (int i = 0; i < tensor->size; i++) {
        tensor->data[i] = ((float)rand() / RAND_MAX) * 2.0f - 1.0f;
    }
    
    return tensor;
}

GeneTensor* gene_tensor_zeros(int* shape, int ndim) {
    // Already zero-initialized by calloc
    return gene_tensor_create(shape, ndim, "float32", "cpu");
}

GeneTensor* gene_tensor_add(GeneTensor* a, GeneTensor* b) {
    if (!a || !b || a->size != b->size) return NULL;
    
    GeneTensor* result = gene_tensor_create(a->shape, a->ndim, "float32", a->device);
    if (!result) return NULL;
    
    for (int i = 0; i < a->size; i++) {
        result->data[i] = a->data[i] + b->data[i];
    }
    
    return result;
}

GeneTensor* gene_tensor_matmul(GeneTensor* a, GeneTensor* b) {
    if (!a || !b || a->ndim != 2 || b->ndim != 2) return NULL;
    
    int m = a->shape[0];
    int k = a->shape[1];
    int n = b->shape[1];
    
    if (k != b->shape[0]) return NULL;  // Dimension mismatch
    
    int result_shape[2] = {m, n};
    GeneTensor* result = gene_tensor_create(result_shape, 2, "float32", a->device);
    if (!result) return NULL;
    
    // Simple matrix multiplication
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            float sum = 0.0f;
            for (int k_idx = 0; k_idx < k; k_idx++) {
                sum += a->data[i * k + k_idx] * b->data[k_idx * n + j];
            }
            result->data[i * n + j] = sum;
        }
    }
    
    return result;
}

GeneTensor* gene_tensor_transpose(GeneTensor* tensor) {
    if (!tensor || tensor->ndim != 2) return NULL;
    
    int result_shape[2] = {tensor->shape[1], tensor->shape[0]};
    GeneTensor* result = gene_tensor_create(result_shape, 2, "float32", tensor->device);
    if (!result) return NULL;
    
    int rows = tensor->shape[0];
    int cols = tensor->shape[1];
    
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            result->data[j * rows + i] = tensor->data[i * cols + j];
        }
    }
    
    return result;
}

// Tokenizer operations
GeneTokenizer* gene_tokenizer_create(int vocab_size) {
    GeneTokenizer* tokenizer = (GeneTokenizer*)malloc(sizeof(GeneTokenizer));
    if (!tokenizer) return NULL;
    
    tokenizer->vocab_size = vocab_size;
    tokenizer->vocab = NULL;  // Would be loaded from file in real implementation
    
    return tokenizer;
}

void gene_tokenizer_free(GeneTokenizer* tokenizer) {
    if (tokenizer) {
        // Free vocab if allocated
        free(tokenizer);
    }
}

// Model operations
GeneModel* gene_model_create(const char* name, const char* type) {
    GeneModel* model = (GeneModel*)malloc(sizeof(GeneModel));
    if (!model) return NULL;
    
    model->name = strdup(name);
    model->type = strdup(type);
    model->weights = NULL;  // Would load weights in real implementation
    model->num_params = 0;
    
    return model;
}

void gene_model_free(GeneModel* model) {
    if (model) {
        free(model->name);
        free(model->type);
        free(model);
    }
}

// Device operations
GeneDevice* gene_device_create(const char* type) {
    GeneDevice* device = (GeneDevice*)malloc(sizeof(GeneDevice));
    if (!device) return NULL;
    
    device->type = strdup(type);
    device->id = 0;
    
    return device;
}

void gene_device_free(GeneDevice* device) {
    if (device) {
        free(device->type);
        free(device);
    }
}

// Embedding operations
typedef struct {
    int dim;
    GeneTensor* weights;
} GeneEmbedding;

GeneEmbedding* gene_embedding_create(int dim) {
    GeneEmbedding* embedding = (GeneEmbedding*)malloc(sizeof(GeneEmbedding));
    if (!embedding) return NULL;
    
    embedding->dim = dim;
    int shape[2] = {50000, dim};  // Default vocab size
    embedding->weights = gene_tensor_random(shape, 2);
    
    return embedding;
}

void gene_embedding_free(GeneEmbedding* embedding) {
    if (embedding) {
        gene_tensor_free(embedding->weights);
        free(embedding);
    }
}

// Model session for inference
typedef struct {
    GeneModel* model;
    GeneDevice* device;
} GeneModelSession;

GeneModelSession* gene_model_session_create(GeneModel* model, GeneDevice* device) {
    GeneModelSession* session = (GeneModelSession*)malloc(sizeof(GeneModelSession));
    if (!session) return NULL;
    
    session->model = model;
    session->device = device;
    
    return session;
}

void gene_model_session_free(GeneModelSession* session) {
    free(session);
}

// Export functions for FFI
#ifdef _WIN32
    #define EXPORT __declspec(dllexport)
#else
    #define EXPORT __attribute__((visibility("default")))
#endif

EXPORT GeneTensor* tensor_create(int* shape, int ndim, const char* dtype, const char* device) {
    return gene_tensor_create(shape, ndim, dtype, device);
}

EXPORT GeneTensor* tensor_random(int* shape, int ndim) {
    return gene_tensor_random(shape, ndim);
}

EXPORT GeneTensor* tensor_zeros(int* shape, int ndim) {
    return gene_tensor_zeros(shape, ndim);
}

EXPORT GeneTensor* tensor_add(GeneTensor* a, GeneTensor* b) {
    return gene_tensor_add(a, b);
}

EXPORT GeneTensor* tensor_matmul(GeneTensor* a, GeneTensor* b) {
    return gene_tensor_matmul(a, b);
}

EXPORT GeneTensor* tensor_transpose(GeneTensor* tensor) {
    return gene_tensor_transpose(tensor);
}

EXPORT void tensor_free(GeneTensor* tensor) {
    gene_tensor_free(tensor);
}

EXPORT GeneTokenizer* tokenizer_create(int vocab_size) {
    return gene_tokenizer_create(vocab_size);
}

EXPORT void tokenizer_free(GeneTokenizer* tokenizer) {
    gene_tokenizer_free(tokenizer);
}

EXPORT GeneModel* model_create(const char* name, const char* type) {
    return gene_model_create(name, type);
}

EXPORT void model_free(GeneModel* model) {
    gene_model_free(model);
}

EXPORT GeneDevice* device_create(const char* type) {
    return gene_device_create(type);
}

EXPORT void device_free(GeneDevice* device) {
    gene_device_free(device);
}

EXPORT GeneEmbedding* embedding_create(int dim) {
    return gene_embedding_create(dim);
}

EXPORT void embedding_free(GeneEmbedding* embedding) {
    gene_embedding_free(embedding);
}

EXPORT GeneModelSession* model_session_create(GeneModel* model, GeneDevice* device) {
    return gene_model_session_create(model, device);
}

EXPORT void model_session_free(GeneModelSession* session) {
    gene_model_session_free(session);
}

// Utility functions for Gene integration
EXPORT int tensor_ndim(GeneTensor* tensor) {
    return tensor ? tensor->ndim : 0;
}

EXPORT int* tensor_shape(GeneTensor* tensor) {
    return tensor ? tensor->shape : NULL;
}

EXPORT float* tensor_data(GeneTensor* tensor) {
    return tensor ? tensor->data : NULL;
}

EXPORT int tensor_size(GeneTensor* tensor) {
    return tensor ? tensor->size : 0;
}