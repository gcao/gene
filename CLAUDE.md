# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Gene Programming Language

Gene is a general-purpose programming language written in Nim, currently transitioning from a stack-based to a register-based virtual machine architecture.

## Development Commands

```bash
# Build the project
nimble build

# Run all active tests
nimble test

# Run specific test files
nim c -r tests/test_vm.nim
nim c -r tests/test_vm_namespace.nim
nim c -r tests/test_vm_fp.nim
nim c -r tests/test_vm_scope.nim
nim c -r tests/test_vm_macro.nim
nim c -r tests/test_vm_block.nim
nim c -r tests/test_vm_custom_compiler.nim

# Run Gene programs
./bin/gene <file.gene>
gene run <file.gene>

# Run all examples
./scripts/run_examples

# Run benchmarks
./scripts/benchme
```

## Architecture Overview

### Core Components

1. **Parser (src/gene/parser.nim)**
   - Built on EDN Parser foundation
   - Converts Gene source code to AST
   - Supports multiple parse modes and macro readers

2. **Compiler (src/gene/compiler.nim)**
   - Compiles AST to bytecode instructions
   - Register-based instruction generation (MAX_REGISTERS = 32)
   - Handles symbol resolution and scope tracking

3. **Virtual Machine (src/gene/vm.nim)**
   - Register-based execution model (recently converted from stack-based)
   - Instruction-based with computed goto for performance
   - Supports runtime compilation via CompileFn

4. **Type System (src/gene/types.nim)**
   - Value representation using tagged unions (ValueKind enum)
   - Core types: primitives, collections, language constructs
   - Frame and scope management for execution contexts

### Testing Strategy

Tests use Nim's unittest framework with custom helpers in `tests/helpers.nim`:
- `test_parser()` - Test parsing without execution
- `test_vm()` - Test compilation and execution
- `test_vm_error()` - Test error conditions

When adding new VM features, create a dedicated test file following the pattern `test_vm_<feature>.nim`.

### Current Development Focus

The codebase is on branch `exp/ai-reg-based-vm2`, implementing a register-based VM to replace the stack-based approach. This affects:
- Instruction generation in compiler.nim
- Execution logic in vm.nim
- Value storage patterns in types.nim

## Gene Language Syntax

Gene uses S-expression syntax with extensions:
- Arrays: `[1 2 3]`
- Maps: `{^a 1 ^b 2}`
- Property access: `obj/prop` or `array/0`
- Variables: `(var x 1)`, assignment: `(x = 2)`
- See `examples/gene_language.gene` for comprehensive examples

## Important Notes

- Some tests are currently commented out in gene.nimble (parser, types, OOP, FFI)
- The VM is undergoing significant architectural changes
- When modifying the VM, ensure register allocation doesn't exceed MAX_REGISTERS (32)