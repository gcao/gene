# Gene Language Test Suite

This directory contains the comprehensive test suite for the Gene programming language. These tests verify the language features from a user's perspective.

## Running Tests

To run all tests:
```bash
./run_tests.sh
```

## Test Structure

Tests are organized by feature category:

- **basics/** - Basic language features (literals, variables, etc.)
- **arithmetic/** - Arithmetic operations and comparisons
- **control_flow/** - If/else conditionals and do blocks
- **functions/** - Function definitions and calls
- **strings/** - String operations and methods
- **arrays/** - Array creation and methods
- **maps/** - Map/dictionary operations
- **oop/** - Object-oriented programming features
- **macros/** - Macro definitions and usage

## Test Format

Each test consists of:
1. A `.gene` file containing the test code
2. An optional `.expected` file containing the expected output

If a `.expected` file exists, the test runner will compare the actual output with the expected output. Otherwise, it just checks that the program runs without errors.

## Skipping Tests

Tests can be skipped by adding a comment at the beginning:
```gene
# SKIP: Reason for skipping
```

## Test Status

As of the last run:
- **Passed**: 16
- **Failed**: 0
- **Skipped**: 2 (float_literals, functions_in_expressions)

## Current Test Coverage

### Working Features ✅
- Basic literals (integers, strings, booleans)
- Variable declaration and shadowing (no reassignment)
- Arithmetic operations (+, -, *, /)
- Comparison operations (<)
- Methods on primitive values (.+, .-, .*, ./, .<, .length)
- If/else conditionals with proper else keyword
- Do blocks
- Function definitions and calls (including no-parameter functions)
- Recursion
- String operations (concatenation with .+, length method)
- Array operations (literals, indexing, length)
- Map operations (literals, key access, keys method)
- Basic classes with field access using / notation
- Core class hierarchy (Any, Number, Int, String)
- Basic macros with % unquote syntax

### Not Yet Supported ❌
- Float literals (tokenizer limitation)
- Greater than (>) and equality (==) operators
- Function definitions as expressions
- nil literal
- Variable reassignment (only shadowing works)
- Method calls on literals (must use variables)
- Pattern matching
- Modules and imports
- Exception handling
- != operator

## Adding New Tests

To add a new test:
1. Create a `.gene` file in the appropriate category
2. Create a corresponding `.expected` file with the expected output
3. Run `./run_tests.sh` to verify the test

## Example Test

`basics/hello_world.gene`:
```gene
#!/usr/bin/env gene run

# Test: Basic print statement
(print "Hello, World!")
```

`basics/hello_world.expected`:
```
Hello, World!
```