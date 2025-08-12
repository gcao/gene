// Simplified LLaMA.cpp wrapper for Gene
// Provides C interface for Nim FFI

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../../external/llama.cpp/include/llama.h"
#include "../../../external/llama.cpp/ggml/include/ggml.h"

typedef struct {
    struct llama_model* model;
    struct llama_context* context;
    const struct llama_vocab* vocab;
    int n_vocab;
    int n_ctx;
} LlamaWrapper;

// Initialize llama backend
int llama_wrapper_init() {
    ggml_backend_load_all();
    return 0;
}

// Load a model and return wrapper
void* llama_wrapper_load_model(const char* model_path) {
    // Set up model parameters
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;  // CPU only for now
    
    // Load model
    struct llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        fprintf(stderr, "[LlamaWrapper] Failed to load model: %s\n", model_path);
        return NULL;
    }
    
    // Create wrapper
    LlamaWrapper* wrapper = (LlamaWrapper*)malloc(sizeof(LlamaWrapper));
    if (!wrapper) {
        llama_model_free(model);
        return NULL;
    }
    
    wrapper->model = model;
    wrapper->context = NULL;
    wrapper->vocab = llama_model_get_vocab(model);
    wrapper->n_vocab = llama_vocab_n_tokens(wrapper->vocab);
    wrapper->n_ctx = 512;  // Default context size
    
    fprintf(stderr, "[LlamaWrapper] Model loaded: vocab=%d\n", wrapper->n_vocab);
    return wrapper;
}

// Create context for a model
void* llama_wrapper_create_context(void* model_wrapper) {
    if (!model_wrapper) return NULL;
    
    LlamaWrapper* wrapper = (LlamaWrapper*)model_wrapper;
    
    // Create context
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = wrapper->n_ctx;
    ctx_params.n_batch = 512;
    ctx_params.n_threads = 4;
    
    wrapper->context = llama_init_from_model(wrapper->model, ctx_params);
    if (!wrapper->context) {
        fprintf(stderr, "[LlamaWrapper] Failed to create context\n");
        return NULL;
    }
    
    return wrapper;
}

// Generate text
char* llama_wrapper_generate(void* context_wrapper, const char* prompt, int max_tokens) {
    if (!context_wrapper) return NULL;
    
    LlamaWrapper* wrapper = (LlamaWrapper*)context_wrapper;
    if (!wrapper->context) return NULL;
    
    // Tokenize prompt
    llama_token tokens[512];
    
    // Get token count first
    int n_tokens = -llama_tokenize(
        wrapper->vocab,
        prompt,
        strlen(prompt),
        NULL,
        0,
        true,  // add_bos
        true   // special
    );
    
    if (n_tokens > 512) {
        return strdup("Error: prompt too long");
    }
    
    // Now tokenize
    n_tokens = llama_tokenize(
        wrapper->vocab,
        prompt,
        strlen(prompt),
        tokens,
        n_tokens,
        true,  // add_bos
        true   // special
    );
    
    if (n_tokens < 0) {
        return strdup("Error: tokenization failed");
    }
    
    // Decode initial batch
    llama_batch batch = llama_batch_get_one(tokens, n_tokens);
    if (llama_decode(wrapper->context, batch) != 0) {
        return strdup("Error: decode failed");
    }
    
    // Allocate result buffer
    char* result = (char*)malloc(4096);
    strcpy(result, prompt);
    
    // Generate tokens
    llama_token new_token;
    for (int i = 0; i < max_tokens; i++) {
        // Get logits
        float* logits = llama_get_logits_ith(wrapper->context, -1);
        
        // Simple greedy sampling
        new_token = 0;
        float max_logit = logits[0];
        for (int j = 1; j < wrapper->n_vocab; j++) {
            if (logits[j] > max_logit) {
                max_logit = logits[j];
                new_token = j;
            }
        }
        
        // Check for EOS
        if (llama_vocab_is_eog(wrapper->vocab, new_token)) {
            break;
        }
        
        // Convert token to text
        char token_str[256];
        int n = llama_token_to_piece(wrapper->vocab, new_token, token_str, sizeof(token_str), 0, true);
        if (n > 0) {
            strncat(result, token_str, n);
        }
        
        // Decode next token
        llama_batch next = llama_batch_get_one(&new_token, 1);
        if (llama_decode(wrapper->context, next) != 0) {
            break;
        }
    }
    
    return result;
}

// Free context
void llama_wrapper_free_context(void* context_wrapper) {
    if (!context_wrapper) return;
    
    LlamaWrapper* wrapper = (LlamaWrapper*)context_wrapper;
    if (wrapper->context) {
        llama_free(wrapper->context);
        wrapper->context = NULL;
    }
}

// Free model
void llama_wrapper_free_model(void* model_wrapper) {
    if (!model_wrapper) return;
    
    LlamaWrapper* wrapper = (LlamaWrapper*)model_wrapper;
    
    if (wrapper->context) {
        llama_free(wrapper->context);
    }
    
    if (wrapper->model) {
        llama_model_free(wrapper->model);
    }
    
    free(wrapper);
}

// Cleanup
void llama_wrapper_cleanup() {
    // Cleanup if needed
}