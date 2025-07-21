# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## General Guidance

- Don't prematurely stop the work unless you have run the command to validate the work (e.g. run unit tests or gene code).

## Project Overview

Gene is a general-purpose programming language written in Nim. This project is extending the current stack-based VM to support the comprehensive feature set found in the reference implementation.

- **Current implementation**: Root directory with basic parser, VM, and compiler (being enhanced)
- **Reference implementation**: `gene-new/` directory with comprehensive feature set (tree-walking interpreter)
- **Goal**: Achieve feature parity by extending VM architecture with full language features

## Development Commands

### Build and Run
```bash
# Build the gene executable
nimble build

# Run Gene files
./gene <file.gene>

# Run interactive mode
./gene
```

### Testing
```bash
# Run all tests
nimble test

# Run specific test file
nim c -r tests/test_vm.nim
nim c -r tests/test_parser.nim
nim c -r tests/test_types.nim

# Run examples
./scripts/run_examples
```

## Core Architecture

### Execution Model
The current implementation uses a stack-based virtual machine with:
1. **Parser** (`src/gene/parser.nim`): Converts Gene source to AST
2. **Compiler** (`src/gene/compiler.nim`): Compiles AST to VM bytecode
3. **VM** (`src/gene/vm.nim`): Executes bytecode instructions

### Key Components
- **VirtualMachine**: Main execution engine with instruction pointer and stack
- **CompiledUnit**: Contains bytecode instructions and metadata
- **Instruction**: VM operation with opcode and arguments
- **Value**: Discriminated union representing all Gene data types (100+ variants)

### VM Instructions
Located in `src/gene/vm/core.nim`, includes:
- Stack operations (push, pop, load, store)
- Control flow (jump, conditional branches)
- Function calls and returns
- Arithmetic and logical operations

### Data Types
Core type system in `src/gene/types.nim`:
- Basic types: nil, bool, int, float, char, string, symbol
- Collections: array, set, map, gene (S-expressions)
- Language constructs: function, macro, block, class, method
- Runtime objects: application, package, module, namespace

## Testing Architecture

Tests are organized by component:
- `test_vm.nim`: Core VM functionality
- `test_vm_*.nim`: Specific VM features (namespace, FP, scope, macro, block)
- `test_parser.nim`: Parser functionality
- `test_types.nim`: Type system tests

Individual tests can be run with `nim c -r tests/<test_file>.nim`

## Implementation Plan

See `docs/design.md` for the comprehensive plan to extend our VM architecture with full language features.

**Current Priority**: Phase 1 - VM Foundation Enhancement
- Extend type system (20 → 100+ Value variants)
- Enhance VM instruction set for advanced features
- Implement VM scope stack and namespace management
- Add garbage collection for complex types

**Architecture**: Keep stack-based VM, extend with comprehensive instruction set and runtime features

## Development Notes

- The main executable is built to `./gene` (no bin/ directory in current implementation)
- Examples are in `examples/` directory with `.gene` extension
- Use `scripts/run_examples` to test all examples
- VM tracing can be enabled for debugging instruction execution
- Reference implementation in `gene-new/` has 40+ feature modules
- Use `tmp/` directory for any temporary files during development