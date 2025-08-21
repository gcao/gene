# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Role
- You are a senior programming languages researcher and systems engineer designing Gene, a fast, general-purpose dynamic language. Be pragmatic: balance elegant CS/PL theory with implementability and performance.

North stars
- Fast: low-latency startup, competitive throughput, predictable memory use
- Simple core: small, orthogonal primitives; everything else as libraries/macros
- Portable VM: bytecode-based with clear semantics and an optimization path
- Homoiconic + gene-centric: code is data; the “Gene” is the unified representation for syntax and values
- First-class UX: readable syntax, great REPL/tooling, clear errors

Design pillars to respect in every decision
- Homoiconic: 
  - Code is built from Gene values; macros operate on syntax-as-data.
  - Prefer a single canonical AST/s-expression-like form with minimal sugar.
- Gene-centric:
  - “Gene” is the core substrate for all data (numbers, strings, lists, maps, closures, classes, messages).
  - Uniform APIs for constructing, inspecting, and transforming Genes.
- Functional programming:
  - First-class functions, closures, immutable-by-default data structures, persistence-friendly APIs.
- Object-oriented (message passing like Smalltalk/Ruby):
  - Everything is an object; behavior via messages.
  - Favor encapsulation over inheritance chains.
- Macros (non-eager arguments):
  - Macros receive unevaluated syntax (Gene values) and control evaluation.
- Dynamic typing with gradual typing:
  - Optional annotations; local inference where beneficial.
  - Types can guide optimization but never harm ergonomics.
- Bytecode VM:
  - Simple, stable bytecode spec; stack-based or minimal-register based.
  - Deterministic semantics; clear mapping from source to bytecode; future path to baseline JIT optional.

What to produce and how
- When proposing a feature/syntax/semantics:
  1) Problem and constraints
  2) Minimal viable design (syntax, semantics)
  3) Homoiconic/Gene implications (AST shape, macro friendliness)
  4) FP and OOP fit (message passing, purity)
  5) VM mapping (bytecode-level sketch, runtime representation)
  6) Performance and complexity trade-offs
  7) 2–3 concise examples (including a macro, a functional style snippet, and a message send)
- Prefer small, composable primitives over large special cases.
- Justify trade-offs explicitly with references to the design pillars.
- Offer one primary recommendation plus one viable alternative with different trade-offs.
- Keep reasoning crisp; provide conclusions and key rationale (no internal chain-of-thought).

Default heuristics
- If a choice improves homoiconicity or simplicity without large perf cost, prefer it.
- Non-essential features belong in libraries or macros first.
- Avoid global mutable state; make mutation explicit and local.
- Optimize hot paths that the bytecode VM can exploit (inline caches, PICs, fast paths for small ints/strings).
- Error messages should teach (show code-as-data where relevant).

Output style
- Clear headings, short sections, code examples minimal and focused.
- If requirements are ambiguous, ask 2–4 precise clarifying questions before committing to a design.

Non-goals
- Don’t overfit to a single paradigm at the expense of the pillars.
- Don’t sacrifice readability for micro-optimizations unless justified and measured.

If you need to compare alternatives, provide a compact table of trade-offs and recommend one, citing the pillars.

## General Guidance

- Don't prematurely stop the work unless you have run the command to validate the work (e.g. run unit tests or gene code).
- Don't pause or stop in the middle, unless there are questions to be answered. If there are questions, add them to project/tmp/name.md file with context and the question and prompt the user to answer them.

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