# Working Tests - Based on Current VM Implementation

## What Works

Based on testing, here's what actually works in the current VM:

### Arithmetic
- `+`, `-`, `*`, `/` operators
- No `%` (modulo)

### Comparison
- Only `.< ` method on variables (not `<` operator)
- No `>`, `<=`, `>=`, `==`, `!=`

### Control Flow
- `if` with `else` keyword: `(if cond expr else expr)`
- `if` without else: `(if cond expr)`

### Variables
- `var` declaration
- No reassignment (`set` not implemented)

### Functions
- `fn` definitions
- Function calls
- Recursion works

### Data Structures
- Arrays: literals, indexing
- Maps: literals, key access
- No methods like push, pop, etc.

### Strings
- String literals
- String interpolation with `#"...{expr}..."`

### Not Working
- Pattern matching
- Exception handling
- Macros
- Classes/OOP
- Most methods