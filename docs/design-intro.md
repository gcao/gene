# Gene Language Implementation Architecture

## Overview

Gene is a general-purpose programming language implemented in Nim using a **three-stage pipeline**: **Parser → Compiler → VM**. This document provides a high-level introduction to the architecture and key components.

## Architecture Flow

```
source.gene → Parser → AST → Compiler → Bytecode → VM → Result
```

## Core Components

### 1. Main Program (`src/gene.nim`)
- **Command-line interface** with `CommandManager`
- **Routes** to "run" command for file execution
- **Supports** REPL mode and debugging options

### 2. Parser (`src/gene/parser.nim`)
- **Input**: Gene source code
- **Output**: AST as nested `Value` objects
- **Features**: 
  - Macro expansion
  - String interpolation (`#"{expression}"`)
  - Complex symbols (namespaced like `a/b/c`)
- **Key Function**: `read_all` converts entire source to AST

### 3. Compiler (`src/gene/compiler.nim`)
- **Input**: AST from parser
- **Output**: Bytecode as `CompilationUnit`
- **Process**:
  - Variable scope tracking with `ScopeTracker`
  - Lazy compilation for functions/blocks/macros
  - Jump resolution for control flow
  - Generates 70+ instruction types

### 4. Virtual Machine (`src/gene/vm.nim`)
- **Input**: Bytecode instructions
- **Output**: Computation results
- **Architecture**: Stack-based with computed goto dispatch
- **Features**:
  - Function calls and method invocation
  - Exception handling with try/catch/finally
  - Async/await support with futures
  - Object-oriented programming support

## Type System

The language uses **NaN boxing** with a unified `Value` type supporting 100+ variants:

### Primitive Types
- `VkInt`, `VkFloat`, `VkBool`, `VkNil`, `VkString`, `VkChar`, `VkSymbol`

### Collection Types
- `VkArray`, `VkMap`, `VkSet`, `VkGene` (S-expressions)

### Function Types
- `VkFunction`, `VkMacro`, `VkBlock`, `VkCompileFn`, `VkNativeFn`

### Object-Oriented Types
- `VkClass`, `VkInstance`, `VkMethod`, `VkBoundMethod`

### Runtime Types
- `VkNamespace`, `VkApplication`, `VkFuture`, `VkException`

## Instruction Set

The VM supports 70+ instruction types across these categories:

- **Stack Operations**: Push, pop, duplicate, swap values
- **Variable Operations**: Store, load, assign variables
- **Control Flow**: Jump, conditional jump, loops, try/catch
- **Function Calls**: Compile function bodies and handle argument matching
- **Arithmetic & Logic**: Add, subtract, multiply, divide, comparisons
- **Collections**: Array, map, set, gene construction
- **Object-Oriented**: Class definition, method invocation, inheritance
- **Async Operations**: Async/await, future handling
- **Meta-programming**: Compile-time evaluation, macro expansion

## Execution Model

The VM uses a **computed goto** dispatch mechanism for optimal performance with:
- **Frame Management**: Handles function calls and scope transitions
- **Exception Handling**: Proper stack unwinding with try/catch/finally
- **Async Support**: Future-based async/await implementation
- **Garbage Collection**: Automatic memory management for complex types

## Development Commands

```bash
# Build the gene executable
nimble build

# Run Gene files
./gene run <file.gene>

# Run interactive mode
./gene

# Run all tests
nimble test

# Run specific test file
nim c -r tests/test_vm.nim
```

This architecture provides a robust foundation for a modern programming language with support for functional programming, object-oriented programming, metaprogramming, and asynchronous operations.