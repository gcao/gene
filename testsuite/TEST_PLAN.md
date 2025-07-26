# Gene Comprehensive Test Suite Plan

## Test Categories

### 1. Basics (✓ Started)
- [x] Literals (integers, strings, booleans)
- [x] Variables (declaration, shadowing)
- [ ] Comments
- [ ] nil values
- [ ] Character literals

### 2. Arithmetic & Operators
- [ ] Basic arithmetic (+, -, *, /, %)
- [ ] Power operator (**)
- [ ] Comparison operators (<, >, <=, >=, ==, !=)
- [ ] Logical operators (and, or, not)
- [ ] Bitwise operators (&, |, ^, ~, <<, >>)
- [ ] Operator precedence

### 3. Control Flow
- [ ] if/else expressions
- [ ] cond expressions
- [ ] case/when expressions
- [ ] do blocks
- [ ] begin blocks
- [ ] while loops
- [ ] for loops
- [ ] break and continue

### 4. Functions
- [ ] Function definition (fn)
- [ ] Function calls
- [ ] Parameters and arguments
- [ ] Default parameters
- [ ] Rest parameters (...)
- [ ] Keyword arguments
- [ ] Closures
- [ ] Recursion
- [ ] Tail recursion
- [ ] Anonymous functions
- [ ] Higher-order functions

### 5. Data Structures
- [ ] Arrays
  - [ ] Creation
  - [ ] Indexing
  - [ ] Slicing
  - [ ] Methods (push, pop, length, etc.)
- [ ] Maps/Dictionaries
  - [ ] Creation
  - [ ] Key access
  - [ ] Methods (keys, values, has_key, etc.)
- [ ] Sets
  - [ ] Creation
  - [ ] Operations (union, intersection, difference)
- [ ] Tuples
- [ ] Records/Structs

### 6. Strings
- [ ] String creation
- [ ] String interpolation
- [ ] String methods
- [ ] Multi-line strings
- [ ] Raw strings
- [ ] String escaping

### 7. Object-Oriented Programming
- [ ] Class definition
- [ ] Instance creation
- [ ] Field access
- [ ] Method definition
- [ ] Method calls
- [ ] Inheritance
- [ ] Super calls
- [ ] Interfaces/Protocols
- [ ] Static methods
- [ ] Properties

### 8. Pattern Matching
- [ ] Simple patterns
- [ ] Destructuring
- [ ] Array patterns
- [ ] Map patterns
- [ ] Guard clauses
- [ ] As patterns
- [ ] Wildcard patterns

### 9. Macros
- [ ] Macro definition
- [ ] Quoting
- [ ] Unquoting
- [ ] Splice unquoting
- [ ] Macro hygiene
- [ ] Reader macros

### 10. Modules & Namespaces
- [ ] Module definition
- [ ] Import statements
- [ ] Export statements
- [ ] Namespace resolution
- [ ] Circular dependencies
- [ ] Package management

### 11. Error Handling
- [ ] try/catch/finally
- [ ] throw expressions
- [ ] Custom exceptions
- [ ] Exception hierarchy
- [ ] Stack traces

### 12. Async/Concurrent
- [ ] async functions
- [ ] await expressions
- [ ] Futures/Promises
- [ ] Channels
- [ ] Threads
- [ ] Locks and synchronization

### 13. I/O Operations
- [ ] File reading
- [ ] File writing
- [ ] Directory operations
- [ ] stdin/stdout/stderr
- [ ] Network operations

### 14. Type System
- [ ] Type annotations
- [ ] Type inference
- [ ] Generic types
- [ ] Union types
- [ ] Type aliases

### 15. Standard Library
- [ ] Math functions
- [ ] String utilities
- [ ] Array utilities
- [ ] Date/Time
- [ ] JSON parsing
- [ ] Regular expressions
- [ ] Random numbers

### 16. Extensions & FFI
- [ ] Loading extensions
- [ ] Calling C functions
- [ ] Passing data to/from C

### 17. Performance
- [ ] Benchmark suite
- [ ] Memory usage tests
- [ ] Stress tests

### 18. Edge Cases
- [ ] Empty programs
- [ ] Very large numbers
- [ ] Deep recursion
- [ ] Circular references
- [ ] Unicode handling

## Test File Naming Convention

```
category/feature_name.gene
category/feature_name.expected
category/feature_name_error.gene
category/feature_name_error.expected
```

## Test Annotations

- `# TEST: description` - Test description
- `# SKIP: reason` - Skip this test
- `# ERROR: expected error` - Test expects an error
- `# BENCH: performance test` - Performance benchmark