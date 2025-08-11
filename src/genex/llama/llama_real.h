#ifndef LLAMA_REAL_H
#define LLAMA_REAL_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RealLlamaModel RealLlamaModel;

int real_llama_init();
RealLlamaModel* real_llama_load(const char* model_path);
char* real_llama_generate(RealLlamaModel* model, const char* prompt, int max_tokens);
int* real_llama_tokenize(RealLlamaModel* model, const char* text, int* n_tokens);
void real_llama_free(RealLlamaModel* model);
void real_llama_cleanup();
void real_llama_info(RealLlamaModel* model, char* buffer, int buffer_size);

#ifdef __cplusplus
}
#endif

#endif