# Gene Unit Tests

This directory contains unit tests for the Gene VM implementation.

## Running Tests

```bash
# Run all tests
nimble test

# Run specific test file
nim c -r tests/test_parser.nim

# Run with verbose output
nim c -r -d:verbose tests/test_vm.nim
```

## Test Organization

### Core Components
- `test_parser.nim` - Parser tests
- `test_compiler.nim` - Bytecode compiler tests  
- `test_vm.nim` - Virtual machine tests
- `test_types.nim` - Type system tests

### VM Features
- `test_vm_namespace.nim` - Namespace handling
- `test_vm_fp.nim` - Functional programming features
- `test_vm_scope.nim` - Scope management
- `test_vm_macro.nim` - Macro system
- `test_vm_block.nim` - Block expressions
- `test_vm_class.nim` - Class/OOP features
- `test_vm_pattern.nim` - Pattern matching

### Language Features  
- `test_int.nim` - Integer operations
- `test_string.nim` - String operations
- `test_array.nim` - Array operations
- `test_map.nim` - Map/dictionary operations
- `test_function.nim` - Function tests
- `test_if.nim` - Conditional tests
- `test_loop.nim` - Loop constructs

### Extensions
- `test_ext.nim` - Extension system tests

## Test Conventions

1. Each test file focuses on a specific component or feature
2. Tests use Nim's unittest framework
3. Test names should be descriptive: `test "parse simple addition"`
4. Group related tests in suites

## Integration Tests

For end-to-end integration tests, see `/testsuite/` which tests complete Gene programs.

## Adding New Tests

When adding new tests:
1. Create appropriately named test file
2. Import necessary modules and unittest
3. Write focused unit tests
4. Ensure tests are included in `nimble test` run
5. Update this README if adding new test categories