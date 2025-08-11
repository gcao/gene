// Gene AI C Header
// Type definitions and function declarations

#ifndef GENE_AI_H
#define GENE_AI_H

#include <stddef.h>

// Export macro for shared library visibility
#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

// Type definitions
typedef struct {
    float* data;
    int* shape;
    int ndim;
    int size;
    char* device;
} GeneTensor;

typedef struct {
    int vocab_size;
    char** vocab;
} GeneTokenizer;

typedef struct {
    char* name;
    char* type;
    void* weights;
    int num_params;
} GeneModel;

typedef struct {
    char* type;
    int id;
} GeneDevice;

typedef struct {
    int dim;
    GeneTensor* weights;
} GeneEmbedding;

typedef struct {
    GeneModel* model;
    GeneDevice* device;
} GeneModelSession;

// Function declarations
EXPORT GeneTensor* tensor_create(int* shape, int ndim, const char* dtype, const char* device);
EXPORT GeneTensor* tensor_random(int* shape, int ndim);
EXPORT GeneTensor* tensor_zeros(int* shape, int ndim);
EXPORT GeneTensor* tensor_add(GeneTensor* a, GeneTensor* b);
EXPORT GeneTensor* tensor_matmul(GeneTensor* a, GeneTensor* b);
EXPORT GeneTensor* tensor_transpose(GeneTensor* tensor);
EXPORT void tensor_free(GeneTensor* tensor);
EXPORT int tensor_ndim(GeneTensor* tensor);
EXPORT int* tensor_shape(GeneTensor* tensor);
EXPORT float* tensor_data(GeneTensor* tensor);
EXPORT int tensor_size(GeneTensor* tensor);

EXPORT GeneTokenizer* tokenizer_create(int vocab_size);
EXPORT void tokenizer_free(GeneTokenizer* tokenizer);

EXPORT GeneModel* model_create(const char* name, const char* type);
EXPORT void model_free(GeneModel* model);

EXPORT GeneDevice* device_create(const char* type);
EXPORT void device_free(GeneDevice* device);

EXPORT GeneEmbedding* embedding_create(int dim);
EXPORT void embedding_free(GeneEmbedding* embedding);

EXPORT GeneModelSession* model_session_create(GeneModel* model, GeneDevice* device);
EXPORT void model_session_free(GeneModelSession* session);

#endif // GENE_AI_H