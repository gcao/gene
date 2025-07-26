# Implementation Status

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
- 🚧 Classes and OOP (partial)
- 🚧 Pattern matching (partial)
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

## Development Strategy

1. The VM implementation is being developed to match the reference implementation's behavior
2. New language features are prototyped in the reference implementation first
3. The VM implementation focuses on performance while maintaining compatibility

## For Contributors

- **Performance work**: Focus on the VM implementation (`/src/`)
- **Language features**: Check the reference implementation (`/gene-new/`)
- **Bug fixes**: Fix in both implementations if applicable

## Why Two Implementations?

1. **Reference implementation** ensures language consistency and provides a stable baseline
2. **VM implementation** provides the performance needed for production use
3. Having both allows safe experimentation while maintaining stability