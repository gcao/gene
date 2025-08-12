// Standalone LLaMA.cpp inference example
// Compile: gcc -o llama_inference llama_inference.c -Lexternal/llama.cpp/build/bin -lllama -lggml -lggml-base -lggml-cpu -Iexternal/llama.cpp/include -Iexternal/llama.cpp/ggml/include

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../external/llama.cpp/include/llama.h"
#include "../external/llama.cpp/ggml/include/ggml.h"

int main(int argc, char** argv) {
    printf("🤖 LLaMA.cpp Inference Example\n");
    printf("==============================\n\n");
    
    const char* model_path = argc > 1 ? argv[1] : "models/tinyllama.gguf";
    const char* prompt = argc > 2 ? argv[2] : "Once upon a time";
    int max_tokens = argc > 3 ? atoi(argv[3]) : 50;
    
    // Initialize backends
    ggml_backend_load_all();
    printf("✅ Backends loaded\n");
    
    // Load model
    printf("📚 Loading model: %s\n", model_path);
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0; // CPU only for now
    
    struct llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        fprintf(stderr, "❌ Failed to load model\n");
        return 1;
    }
    printf("✅ Model loaded\n");
    
    // Create context
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 512;
    ctx_params.n_batch = 512;
    ctx_params.n_threads = 4;
    
    struct llama_context* ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
        fprintf(stderr, "❌ Failed to create context\n");
        llama_model_free(model);
        return 1;
    }
    printf("✅ Context created\n\n");
    
    // Get vocab for tokenization
    const struct llama_vocab* vocab = llama_model_get_vocab(model);
    int n_vocab = llama_vocab_n_tokens(vocab);
    printf("📊 Vocab size: %d\n", n_vocab);
    
    // Tokenize prompt
    printf("📝 Prompt: \"%s\"\n", prompt);
    llama_token tokens[512];
    
    // Get token count first
    int n_tokens = -llama_tokenize(
        vocab,
        prompt,
        strlen(prompt),
        NULL,
        0,
        true,  // add_bos
        true   // special
    );
    
    if (n_tokens > 512) {
        fprintf(stderr, "❌ Prompt too long\n");
        llama_free(ctx);
        llama_model_free(model);
        return 1;
    }
    
    // Now tokenize
    n_tokens = llama_tokenize(
        vocab,
        prompt,
        strlen(prompt),
        tokens,
        n_tokens,
        true,  // add_bos
        true   // special
    );
    
    printf("🔢 Tokens: %d\n\n", n_tokens);
    
    // Decode initial batch
    printf("🤖 Generating text...\n");
    printf("=====================================\n");
    printf("%s", prompt);
    
    llama_batch batch = llama_batch_get_one(tokens, n_tokens);
    if (llama_decode(ctx, batch) != 0) {
        fprintf(stderr, "\n❌ Decode failed\n");
        llama_free(ctx);
        llama_model_free(model);
        return 1;
    }
    
    // Generate tokens
    llama_token new_token;
    for (int i = 0; i < max_tokens; i++) {
        // Get logits
        float* logits = llama_get_logits_ith(ctx, -1);
        
        // Simple greedy sampling
        new_token = 0;
        float max_logit = logits[0];
        for (int j = 1; j < n_vocab; j++) {
            if (logits[j] > max_logit) {
                max_logit = logits[j];
                new_token = j;
            }
        }
        
        // Check for EOS
        if (llama_vocab_is_eog(vocab, new_token)) {
            break;
        }
        
        // Convert token to text
        char token_str[256];
        int n = llama_token_to_piece(vocab, new_token, token_str, sizeof(token_str), 0, true);
        if (n > 0) {
            printf("%.*s", n, token_str);
            fflush(stdout);
        }
        
        // Decode next token
        llama_batch next = llama_batch_get_one(&new_token, 1);
        if (llama_decode(ctx, next) != 0) {
            fprintf(stderr, "\n❌ Decode failed during generation\n");
            break;
        }
    }
    
    printf("\n=====================================\n");
    printf("✅ Generation complete!\n\n");
    
    // Cleanup
    llama_free(ctx);
    llama_model_free(model);
    
    return 0;
}