# Gene Test Suite

A comprehensive test suite for the Gene programming language, organized by feature categories with numbered test files for clear execution order.

## Structure

```
testsuite/
├── basics/           # Fundamental language features
│   ├── 1_literals.gene
│   ├── 2_variables.gene
│   ├── 3_numbers.gene
│   └── 4_genes.gene
├── control_flow/     # Control structures
│   ├── 1_if.gene
│   ├── 2_loops.gene
│   └── 3_do_blocks.gene
├── operators/        # Operator tests
│   ├── 1_arithmetic.gene
│   └── 2_comparison.gene
├── arrays/           # Array operations
│   └── 1_basic_arrays.gene
├── maps/             # Map operations
│   └── 1_basic_maps.gene
├── strings/          # String operations
│   └── 1_basic_strings.gene
├── functions/        # Function definitions
│   └── 1_basic_functions.gene
├── scopes/           # Variable scoping
│   └── 1_basic_scopes.gene
└── run_tests.sh      # Test runner script
```

## Running Tests

### Run all tests:
```bash
./run_tests.sh
```

### Run individual test:
```bash
../bin/gene run basics/1_literals.gene
```

### Run tests for a specific feature:
```bash
for f in control_flow/*.gene; do ../bin/gene run "$f"; done
```

## Test Conventions

1. **Numbered Prefixes**: Tests are numbered (1_, 2_, etc.) to indicate execution order
2. **Expected Output**: Tests use `# Expected:` comments to specify expected output
3. **Auto-verification**: The test runner compares actual output against expected
4. **Feature Focus**: Each test focuses on a specific language feature
5. **Flexible Testing**: Tests without `# Expected:` just verify successful execution

## Current Status

✅ **All 14 tests passing** (100% pass rate)

| Feature | Tests | Status |
|---------|-------|--------|
| Basics | 4 | ✅ |
| Control Flow | 3 | ✅ |
| Operators | 2 | ✅ |
| Arrays | 1 | ✅ |
| Maps | 1 | ✅ |
| Strings | 1 | ✅ |
| Functions | 1 | ✅ |
| Scopes | 1 | ✅ |

## Adding New Tests

When adding tests:
1. Use the next available number in the feature directory
2. Keep tests simple and focused
3. Use print statements for output
4. Test one concept at a time
5. Include a completion message

See `TEST_ORGANIZATION.md` for detailed documentation.