# Implementation Status

*Last Updated: August 12, 2025*

This repository contains **two implementations** of the Gene programming language:

## 1. VM Implementation (Root Directory) - ACTIVE DEVELOPMENT

Location: `/src/`

This is the **current focus** - a bytecode VM implementation for better performance.

### Status
- ✅ Parser 
- ✅ Bytecode compiler
- ✅ Basic VM with stack-based execution
- ✅ Core data types (int, string, bool, array, map, etc.)
- ✅ Functions and closures
- ✅ Basic control flow (if/else, loops)
- ✅ REPL
- ✅ AI/ML Integration (LLaMA.cpp via genex/llamacpp namespace)
- 🚧 Classes and OOP (partial)
- 🚧 Pattern matching (partial)
- 🚧 Tensor operations (basic implementation)
- ❌ Macros
- ❌ Modules/imports
- ❌ Async/await

### Performance
- Current: ~600K function calls/sec (fib benchmark)
- Target: 5-10M calls/sec

## 2. Reference Implementation (gene-new/) - FEATURE COMPLETE

Location: `/gene-new/`

This is the **reference implementation** - a tree-walking interpreter with all language features.

### Status
- ✅ All language features implemented
- ✅ Complete standard library
- ✅ Extensive test suite
- ✅ Production-ready

### Purpose
- Language specification reference
- Testing new language features
- Validating VM implementation behavior

## AI/ML Capabilities (New!)

Location: `/src/gene/ai/`

The VM implementation now includes native AI/ML integration:

### Features
- ✅ **LLaMA.cpp Integration**: Native bindings for local LLM inference
- ✅ **genex Namespace**: Extension system (`genex/llamacpp`)
- ✅ **Model Support**: GGUF format models (TinyLlama, Mistral, Llama 2, etc.)
- ✅ **Hardware Acceleration**: Metal on macOS, CUDA on Linux (planned)
- 🚧 **Tensor Operations**: Basic tensor API for numerical computing
- 📋 **Streaming Generation**: Planned for real-time text generation
- 📋 **Embeddings**: Planned for semantic search and RAG

### Documentation
See `/docs/ai/` for comprehensive AI documentation including build guides and API references.

## Development Strategy

1. The VM implementation is being developed to match the reference implementation's behavior
2. New language features are prototyped in the reference implementation first
3. The VM implementation focuses on performance while maintaining compatibility
4. AI/ML features are implemented as native extensions for maximum performance

## For Contributors

- **Performance work**: Focus on the VM implementation (`/src/`)
- **Language features**: Check the reference implementation (`/gene-new/`)
- **AI/ML features**: See `/src/gene/ai/` and `/docs/ai/` for integration guides
- **Bug fixes**: Fix in both implementations if applicable
- **Build instructions**: 
  - General: `nimble build`
  - macOS ARM64 with AI: `./scripts/build_macos_arm64.sh`

## Why Two Implementations?

1. **Reference implementation** ensures language consistency and provides a stable baseline
2. **VM implementation** provides the performance needed for production use
3. Having both allows safe experimentation while maintaining stability