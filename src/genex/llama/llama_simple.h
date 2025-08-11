#ifndef LLAMA_SIMPLE_H
#define LLAMA_SIMPLE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SimpleLlamaModel {
    char* model_path;
    int vocab_size;
    int context_size;
    float* weights;
} SimpleLlamaModel;

SimpleLlamaModel* simple_llama_init(const char* path);
char* simple_llama_generate(SimpleLlamaModel* model, const char* prompt, int max_tokens);
int* simple_tokenize(const char* text, int* n_tokens);
float* simple_llama_embeddings(SimpleLlamaModel* model, const char* text, int* n_dims);
void simple_llama_free(SimpleLlamaModel* model);
void simple_llama_info(SimpleLlamaModel* model, char* buffer, int size);

#ifdef __cplusplus
}
#endif

#endif