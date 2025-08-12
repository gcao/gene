// Header file for llama wrapper
#ifndef LLAMA_WRAPPER_H
#define LLAMA_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

int llama_wrapper_init();
void* llama_wrapper_load_model(const char* model_path);
void* llama_wrapper_create_context(void* model_wrapper);
char* llama_wrapper_generate(void* context_wrapper, const char* prompt, int max_tokens);
void llama_wrapper_free_context(void* context_wrapper);
void llama_wrapper_free_model(void* model_wrapper);
void llama_wrapper_cleanup();

#ifdef __cplusplus
}
#endif

#endif // LLAMA_WRAPPER_H