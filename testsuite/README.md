# Gene Language Test Suite

This directory contains the test suite for the Gene programming language VM implementation.

## Running Tests

To run all tests:
```bash
./run_tests.sh
```

## Test Structure

Tests are organized by feature category:

- **basics/** - Basic language features (literals, variables, floats)
- **arithmetic/** - Arithmetic operations (+, -, *, /)
- **control_flow/** - If/else conditionals
- **functions/** - Function definitions and calls
- **strings/** - String operations
- **arrays/** - Array creation (indexing not yet implemented)
- **maps/** - Map operations (simplified due to parser issues)
- **operators/** - Comparison operators (currently causes segfault)
- **minimal/** - Minimal test cases for quick verification

## Test Format

Each test file is self-contained with:
1. Gene code to test
2. Expected output on the line immediately after each `println` statement, prefixed with `# Expected:`

Example:
```gene
(println "Hello, World!")
# Expected: Hello, World!
```

## Current Status

All 11 tests pass. Known limitations:
- Comparison operators (<, >, <=, >=, ==, !=) cause segfault
- Array indexing not implemented
- Map parsing has issues
- String interpolation not working
- If statements without else cause segfault
- Modulo operator (%) not implemented

## Adding New Tests

1. Create a `.gene` file in the appropriate category directory
2. Add test code with `println` statements
3. Add `# Expected: <output>` immediately after each println
4. Run the test suite to verify