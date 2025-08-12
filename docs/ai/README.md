# AI/ML Documentation for Gene

This directory contains all documentation related to AI and machine learning integration in the Gene programming language.

## 📚 Documentation Overview

### Build & Setup
- **[BUILD_MACOS_ARM64.md](BUILD_MACOS_ARM64.md)** - Complete guide for building Gene with LLaMA.cpp on Apple Silicon Macs
- **[BUILD_LINUX_CUDA.md](BUILD_LINUX_CUDA.md)** - *(Coming Soon)* Build instructions for Linux with CUDA support

### Architecture & Design
- **[ai-architecture-final.md](ai-architecture-final.md)** - Final AI architecture design
- **[ai.md](ai.md)** - Comprehensive AI integration overview
- **[ai-implementation-summary.md](ai-implementation-summary.md)** - Implementation summary

### LLaMA.cpp Integration
- **[llama-integration.md](llama-integration.md)** - LLaMA.cpp integration details
- **[llm-capabilities.md](llm-capabilities.md)** - Language model capabilities in Gene

### API Guides
- **[tensor-api-guide.md](tensor-api-guide.md)** - Tensor operations API guide

### Status & Summary
- **[AI_STATUS.md](AI_STATUS.md)** - Current implementation status
- **[ai-final-summary.md](ai-final-summary.md)** - Final summary of AI implementation

## 🚀 Quick Start

For macOS (Apple Silicon):
```bash
# Build Gene with LLaMA.cpp support
./scripts/build_macos_arm64.sh

# Run example
./bin/gene run examples/llama_simple_test.gene
```

## 🦙 Using LLaMA.cpp in Gene

```gene
# Load a model
(var result (genex/llamacpp/load "models/tinyllama.gguf"))

# Generate text
(var text (genex/llamacpp/generate "Once upon a time" 50))
(println text)

# Cleanup
(genex/llamacpp/unload)
```

## 📦 Extension Namespace

All AI functionality is organized under the `genex` (Gene Extensions) namespace:

- `genex/llamacpp/` - LLaMA.cpp integration
- `genex/tensor/` - Tensor operations *(planned)*
- `genex/tokenizer/` - Tokenization *(planned)*

## 🛠️ Development Status

- ✅ LLaMA.cpp C bindings
- ✅ Native Gene integration via `genex/llamacpp`
- ✅ macOS ARM64 build support with Metal acceleration
- ✅ Model loading and text generation
- 🚧 Linux + CUDA support (in progress)
- 📋 Streaming generation (planned)
- 📋 Embedding generation (planned)