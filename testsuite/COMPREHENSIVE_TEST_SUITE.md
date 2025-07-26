# Gene Comprehensive Test Suite

## Overview

This test suite provides systematic coverage of the Gene programming language features for the VM implementation.

## Test Structure

```
testsuite/
├── TEST_PLAN.md                 # Comprehensive test plan
├── run_tests.sh                 # Test runner script
├── basics/                      # Basic language features
│   ├── literals.gene           # Integer, string, boolean literals
│   ├── variables.gene          # Variable declaration and shadowing
│   ├── hello_world.gene        # Simple print test
│   └── float_literals.gene     # Float support (currently failing)
├── arithmetic/                  # Math operations
│   └── basic_math.gene         # +, -, *, /, % operations
├── operators/                   # Comparison and logical operators
│   └── comparison.gene         # <, >, <=, >=, ==, != operators
├── control_flow/               # Control structures
│   └── if_else.gene           # if/else expressions
├── functions/                  # Function features
│   └── basic_functions.gene   # Function definition, calls, recursion
├── arrays/                     # Array operations
│   └── array_operations.gene  # Creation, indexing, methods
├── maps/                       # Map/dictionary operations
│   └── map_operations.gene    # Creation, access, methods
├── strings/                    # String operations
│   └── string_operations.gene # Concatenation, methods, interpolation
├── error_handling/             # Exception handling
│   └── try_catch.gene         # try/catch/finally blocks
├── patterns/                   # Pattern matching
│   └── basic_patterns.gene    # match expressions, guards
└── macros/                     # Macro system
    └── basic_macros.gene      # defmacro, quoting, unquoting
```

## Running Tests

```bash
# Run all tests
./testsuite/run_tests.sh

# Run specific category
./gene run testsuite/functions/basic_functions.gene

# Compare output
./gene run testsuite/arrays/array_operations.gene | diff testsuite/arrays/array_operations.expected -
```

## Test Categories Created

### ✅ Implemented Tests

1. **Arithmetic** - Basic math operations
2. **Operators** - Comparison operators
3. **Control Flow** - if/else expressions
4. **Functions** - Basic functions and recursion
5. **Arrays** - Array creation and operations
6. **Maps** - Dictionary operations
7. **Strings** - String manipulation
8. **Error Handling** - Exception handling
9. **Pattern Matching** - Basic patterns
10. **Macros** - Macro definitions

### 🚧 TODO Tests

1. **Loops** - while, for loops
2. **Classes** - OOP features
3. **Modules** - Import/export
4. **Async** - Async/await
5. **Type System** - Type annotations
6. **Standard Library** - Built-in functions
7. **Extensions** - FFI tests
8. **Performance** - Benchmarks

## Test Format

Each test consists of:
- `.gene` file with test code
- `.expected` file with expected output
- Comments explaining what's being tested

## Adding New Tests

1. Create `.gene` file in appropriate category
2. Add expected output in `.expected` file
3. Use descriptive test names
4. Add comments explaining the test
5. Update this documentation

## Current Status

The test suite provides a solid foundation for regression testing. As the VM implementation progresses, more tests can be uncommented or added to match the reference implementation's capabilities.