// Real Llama.cpp integration for Gene
// Uses actual llama.cpp for text generation

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../../external/llama.cpp/include/llama.h"
#include "../../../external/llama.cpp/ggml/include/ggml.h"  // For ggml_backend_load_all

typedef struct {
    struct llama_model* model;
    struct llama_context* context;
    char* model_path;
    int n_ctx;
    int n_vocab;
} RealLlamaModel;

// Export macro
#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

// Initialize llama backend
EXPORT int real_llama_init() {
    // Load dynamic backends like in simple.cpp
    ggml_backend_load_all();
    fprintf(stderr, "[RealLlama] Backends loaded\n");
    return 0;
}

// Load a model
EXPORT RealLlamaModel* real_llama_load(const char* model_path) {
    RealLlamaModel* wrapper = (RealLlamaModel*)malloc(sizeof(RealLlamaModel));
    if (!wrapper) return NULL;
    
    // Set up model parameters
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;  // CPU only for faster testing
    model_params.progress_callback = NULL;  // No progress callback
    
    // Load model
    fprintf(stderr, "[RealLlama] Loading model: %s\n", model_path);
    wrapper->model = llama_load_model_from_file(model_path, model_params);
    if (!wrapper->model) {
        fprintf(stderr, "[RealLlama] Failed to load model\n");
        free(wrapper);
        return NULL;
    }
    
    // Create context
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 512;  // Small context for testing
    ctx_params.n_batch = 512;
    ctx_params.n_threads = 4;
    
    wrapper->context = llama_init_from_model(wrapper->model, ctx_params);
    if (!wrapper->context) {
        fprintf(stderr, "[RealLlama] Failed to create context\n");
        llama_free_model(wrapper->model);
        free(wrapper);
        return NULL;
    }
    
    wrapper->model_path = strdup(model_path);
    wrapper->n_ctx = ctx_params.n_ctx;
    wrapper->n_vocab = llama_n_vocab(wrapper->model);
    
    fprintf(stderr, "[RealLlama] Model loaded successfully (vocab=%d, ctx=%d)\n", 
            wrapper->n_vocab, wrapper->n_ctx);
    return wrapper;
}

// Simple text generation
EXPORT char* real_llama_generate(RealLlamaModel* model, const char* prompt, int max_tokens) {
    if (!model || !model->context) return NULL;
    
    // Get vocab
    const struct llama_vocab* vocab = llama_model_get_vocab(model->model);
    
    // Tokenize prompt - first get the count
    const int n_prompt_max = 512;
    llama_token prompt_tokens[512];
    
    // Get token count (negative return)
    int n_prompt = -llama_tokenize(
        vocab,
        prompt,
        strlen(prompt),
        NULL,
        0,
        true,  // add_bos
        true   // special
    );
    
    if (n_prompt > n_prompt_max) {
        fprintf(stderr, "[RealLlama] Prompt too long: %d tokens\n", n_prompt);
        return strdup("Error: prompt too long");
    }
    
    // Now tokenize for real
    n_prompt = llama_tokenize(
        vocab,
        prompt,
        strlen(prompt),
        prompt_tokens,
        n_prompt,
        true,  // add_bos
        true   // special
    );
    
    if (n_prompt < 0) {
        fprintf(stderr, "[RealLlama] Tokenization failed\n");
        return strdup("Error: tokenization failed");
    }
    
    fprintf(stderr, "[RealLlama] Prompt tokenized: %d tokens\n", n_prompt);
    
    // Use simple batch API
    llama_batch batch = llama_batch_get_one(prompt_tokens, n_prompt);
    
    // Decode the batch
    struct llama_context* ctx = model->context;
    if (llama_decode(ctx, batch) != 0) {
        fprintf(stderr, "[RealLlama] Decode failed\n");
        return strdup("Error: decode failed");
    }
    
    // Generate tokens
    char* result = (char*)malloc(2048);
    strcpy(result, prompt);
    
    llama_token new_token_id;
    int n_generated = 0;
    int n_cur = n_prompt;
    
    for (int i = 0; i < max_tokens; i++) {
        // Get logits from last token
        float* logits = llama_get_logits_ith(ctx, -1);
        
        // Simple greedy sampling
        new_token_id = 0;
        float max_logit = logits[0];
        for (int token_id = 1; token_id < model->n_vocab; token_id++) {
            if (logits[token_id] > max_logit) {
                max_logit = logits[token_id];
                new_token_id = token_id;
            }
        }
        
        // Check for EOS using vocab API
        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }
        
        // Decode token to text
        char token_str[256];
        int n = llama_token_to_piece(vocab, new_token_id, token_str, sizeof(token_str), 0, true);
        if (n > 0) {
            strncat(result, token_str, n);
            n_generated++;
        }
        
        // Prepare next batch with the new token
        llama_batch next_batch = llama_batch_get_one(&new_token_id, 1);
        
        if (llama_decode(ctx, next_batch) != 0) {
            fprintf(stderr, "[RealLlama] Decode failed during generation\n");
            break;
        }
        
        n_cur++;
    }
    
    fprintf(stderr, "[RealLlama] Generated %d tokens\n", n_generated);
    return result;
}

// Tokenize text
EXPORT int* real_llama_tokenize(RealLlamaModel* model, const char* text, int* n_tokens) {
    if (!model || !model->model) return NULL;
    
    const struct llama_vocab* vocab = llama_model_get_vocab(model->model);
    
    // Allocate space for tokens
    int max_tokens = 512;
    int* tokens = (int*)malloc(max_tokens * sizeof(int));
    
    *n_tokens = llama_tokenize(
        vocab,
        text,
        strlen(text),
        tokens,
        max_tokens,
        true,   // add_bos
        true    // special
    );
    
    if (*n_tokens < 0) {
        free(tokens);
        return NULL;
    }
    
    return tokens;
}

// Free model
EXPORT void real_llama_free(RealLlamaModel* model) {
    if (model) {
        if (model->context) llama_free(model->context);
        if (model->model) llama_free_model(model->model);
        if (model->model_path) free(model->model_path);
        free(model);
    }
}

// Cleanup
EXPORT void real_llama_cleanup() {
    // No need to call llama_backend_free in newer API
    fprintf(stderr, "[RealLlama] Cleanup complete\n");
}

// Get model info
EXPORT void real_llama_info(RealLlamaModel* model, char* buffer, int buffer_size) {
    if (!model) {
        snprintf(buffer, buffer_size, "No model loaded");
        return;
    }
    
    snprintf(buffer, buffer_size, 
        "Model: %s\nVocab: %d\nContext: %d\nBackend: llama.cpp",
        model->model_path, model->n_vocab, model->n_ctx);
}