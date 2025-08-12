# Gene AI Architecture - Final Design

## Overview

Gene's AI support is designed with a **generic core** and **provider-specific extensions**, allowing for flexible integration with different AI/LLM backends.

## Architecture

```
┌─────────────────────────────────────┐
│      Gene Application Code          │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│    Generic AI Interface (Core)      │
│   - ai/load-model                   │
│   - ai/generate                     │
│   - ai/embeddings                   │
│   - ai/tokenize                     │
└──────────────┬──────────────────────┘
               │
     ┌─────────┼─────────┬──────────┐
     │         │         │          │
┌────▼───┐ ┌──▼───┐ ┌───▼───┐ ┌────▼────┐
│  Mock  │ │Llama │ │OpenAI │ │Anthropic│
│Provider│ │ .cpp │ │  API  │ │   API   │
└────────┘ └──────┘ └───────┘ └─────────┘
```

## Core Components

### 1. Generic AI Interface (`src/gene/ai/ai_interface.nim`)

Defines abstract types and interfaces:

- **AIModel**: Abstract model representation
- **AIProvider**: Interface for AI backends
- **CompletionRequest/Response**: Generic text generation
- **EmbeddingRequest/Response**: Generic embeddings
- **AICapability**: Provider capabilities enum

### 2. Core Native Functions (`src/gene/ai/ai_core_natives.nim`)

Provides Gene-accessible functions:

```gene
(ai/providers)                    # List available providers
(ai/load-model provider path)     # Load a model
(ai/generate model prompt opts)   # Generate text
(ai/embeddings model text)        # Get embeddings
(ai/tokenize model text)          # Tokenize text
```

### 3. Provider Extensions

#### Mock Provider (`src/genex/ai_mock.nim`)
- In-memory mock implementation
- For testing and development
- No external dependencies

#### Llama Provider (`src/genex/ai_llama.nim`)
- Integrates with llama.cpp
- Supports GGUF model files
- Local inference

## Usage Examples

### Basic Usage

```gene
# Load extension
(import-extension "build/libai_mock.dylib")

# Load model
(var model (ai/load-model "mock" "model.gguf"))

# Generate text
(var response (ai/generate model "Tell me about AI" {
  ^max_tokens 100
  ^temperature 0.7
}))

(println response.text)
```

### Provider Switching

```gene
# Choose provider based on availability
(var provider 
  (if (file-exists? "models/llama.gguf")
    "llama"
    "mock"))

(var model (ai/load-model provider "model.gguf"))
# Same code works with any provider
```

## Adding New Providers

To add a new AI provider (e.g., OpenAI):

1. Create extension file `src/genex/ai_openai.nim`
2. Implement `AIProvider` interface:
   ```nim
   type OpenAIProvider = ref object of AIProvider
   
   method generate*(provider: OpenAIProvider, 
                   model: AIModel, 
                   request: CompletionRequest): CompletionResponse =
     # Call OpenAI API
   ```
3. Register provider in `gene_init`
4. Build as extension: `nim c --app:lib ...`

## Benefits

1. **Provider Independence**: Application code doesn't change when switching providers
2. **Extensibility**: New providers can be added without modifying core
3. **Type Safety**: Strong typing through Nim's type system
4. **Performance**: Native code execution, no Python overhead
5. **Flexibility**: Mix and match providers for different tasks

## Current Status

### ✅ Completed
- Generic AI interface design
- Core native functions
- Mock provider implementation
- Llama.cpp provider structure
- Provider registration system

### 🚧 TODO
- Complete llama.cpp integration (link actual library)
- Add streaming support
- Implement OpenAI provider
- Add Anthropic provider
- Add model caching
- Implement batch processing

## Building Extensions

```bash
# Build mock provider
nim c --app:lib -d:release --mm:orc \
  -o:build/libai_mock.dylib src/genex/ai_mock.nim

# Build llama provider (requires llama.cpp)
nim c --app:lib -d:release --mm:orc \
  -L:external/llama.cpp -l:llama \
  -o:build/libai_llama.dylib src/genex/ai_llama.nim
```

## Conclusion

Gene's AI architecture provides a clean separation between:
- **Generic interface** in core (provider-agnostic)
- **Specific implementations** in extensions (provider-specific)

This design allows Gene to work with any AI/LLM backend while maintaining a consistent API for applications.