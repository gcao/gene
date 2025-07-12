# Gene Language Design Document

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Parser Design](#parser-design)
4. [Gene Data Structure](#gene-data-structure)
5. [Compiler Design](#compiler-design)
6. [Instruction Set (IR)](#instruction-set-ir)
7. [Virtual Machine Execution](#virtual-machine-execution)
8. [Command-Line Interface](#command-line-interface)
9. [Module and Namespace System](#module-and-namespace-system)
10. [Native Function Interface](#native-function-interface)
11. [Object-Oriented Programming](#object-oriented-programming)
12. [Functional Programming](#functional-programming)
13. [Macro System](#macro-system)
14. [Pattern Matching](#pattern-matching)
15. [Selectors](#selectors)
16. [Custom Instruction Support](#custom-instruction-support)

## Overview

Gene is a dynamic, interpreted programming language with Lisp-like syntax that compiles to bytecode for execution on a register-based virtual machine. It combines functional and object-oriented paradigms with a powerful macro system and property-based data model.

## Architecture

The Gene language follows a pipeline architecture:

```
Source Code → Parser → AST (Gene Data) → Compiler → Bytecode (IR) → VM → Result
```

### Key Components:

1. **Parser**: EDN-based parser extended for Gene-specific syntax
2. **Compiler**: Transforms AST to register-based bytecode instructions
3. **VM**: Register-based virtual machine with 32 registers
4. **Runtime**: Type system, memory management, native functions

## Parser Design

The parser is built on the EDN (Extensible Data Notation) parser with Gene-specific extensions.

### Lexical Elements

```nim
# Token types recognized by the lexer
TokenKind = enum
  TkEof, TkComma, TkNewLine
  TkInt, TkFloat, TkString, TkChar
  TkSymbol, TkKeyword, TkQuote, TkUnquote
  TkLeftParen, TkRightParen
  TkLeftBracket, TkRightBracket
  TkLeftBrace, TkRightBrace
  # Special tokens for Gene
  TkArrow           # ->
  TkPropShorthand   # ^
```

### Parsing Process

1. **Tokenization**: Source text → tokens
2. **Expression Parsing**: Tokens → Gene data structures
3. **Special Form Recognition**: Handle quote, unquote, property syntax

```nim
proc read_all*(code: string): Value =
  var self = new_parser(code, "code")
  self.read_stream()

proc read*(self: Parser): Value =
  case self.token.kind:
    of TkLeftParen:
      self.read_gene()
    of TkLeftBracket:
      self.read_array()
    of TkLeftBrace:
      self.read_map()
    of TkQuote:
      self.read_quote()
    # ... more cases
```

### Special Syntax

- **Quote**: `:expr` → `(quote expr)`
- **Unquote**: `%var` → `(unquote var)`
- **Properties**: `^key value` in maps and genes
- **Selectors**: `a/b/c` for hierarchical access
- **Blocks**: `(args -> body)` for lambda expressions

## Gene Data Structure

Gene uses a tagged union value system with 64-bit encoding:

```nim
type
  ValueKind* = enum
    VkNil = 0
    VkBool, VkInt, VkFloat
    VkChar, VkString, VkSymbol
    VkArray, VkSet, VkMap
    VkGene, VkQuote
    VkFunction, VkMacro, VkBlock
    VkClass, VkInstance, VkNamespace
    # ... more types

  Value* = distinct int64  # 64-bit tagged value

  Gene* = object
    type*: Value           # The "head" of the S-expression
    props*: Table[Key, Value]  # Properties (^key value pairs)
    children*: seq[Value]      # Positional arguments
```

### Value Encoding Scheme

Gene uses clever bit patterns for efficient value representation:

```nim
# Special constants
const NIL = 0x7FFA_A000_0000_0000'u64
const TRUE = 0x7FFA_B000_0000_0001'u64
const FALSE = 0x7FFA_B000_0000_0000'u64

# Small integers are stored directly
# Heap-allocated values use pointer tagging
```

## Compiler Design

The compiler transforms Gene AST into register-based bytecode.

### Compilation Unit

```nim
type
  CompilationUnit* = ref object
    id*: Id
    kind*: CompilationUnitKind
    instructions*: seq[Instruction]
    labels*: Table[Label, int]
    skip_return*: bool
```

### Compilation Process

```nim
proc compile*(input: Value): CompilationUnit =
  let self = Compiler(output: new_compilation_unit())
  self.output.instructions.add(Instruction(kind: IkStart))
  self.compile(input)
  self.output.instructions.add(Instruction(kind: IkEnd))
  self.output.update_jumps()  # Resolve jump labels
  result = self.output
```

### Key Compiler Methods

1. **Symbol Resolution**
```nim
proc compile_symbol(self: Compiler, input: Value) =
  # Check local scope
  let found = self.scope_tracker.locate(key)
  if found.local_index >= 0:
    self.output.instructions.add(
      Instruction(kind: IkVarResolve, var_arg0: found.local_index))
  else:
    # Global resolution
    self.output.instructions.add(
      Instruction(kind: IkResolveSymbol, var_arg0: input))
```

2. **Function Compilation**
```nim
proc compile_fn(self: Compiler, input: Value) =
  self.output.instructions.add(
    Instruction(kind: IkFunction, var_arg0: input))
  # Capture scope information
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.output.instructions.add(
    Instruction(kind: IkPushValue, push_value: r.to_ref_value()))
```

## Instruction Set (IR)

Gene uses a register-based instruction set optimized for common operations:

### Core Instructions

```nim
type
  InstructionKind* = enum
    # Control flow
    IkStart, IkEnd, IkNoop
    IkJump, IkJumpIfTrue, IkJumpIfFalse
    
    # Register operations
    IkPushValue    # Load value into register 0
    IkMove         # Move between registers
    
    # Arithmetic (operate on registers)
    IkAdd, IkSub, IkMul, IkDiv, IkPow
    
    # Comparison
    IkLt, IkLe, IkGt, IkGe, IkEq, IkNe
    
    # Variable management
    IkVar             # Declare variable
    IkVarResolve      # Load variable
    IkVarAssign       # Store to variable
    
    # Object operations
    IkGetMember       # obj/member
    IkSetMember       # obj/member = value
    IkGetChild        # array/index
    IkSetChild        # array/index = value
    
    # Function/Macro
    IkFunction        # Define function
    IkMacro          # Define macro
    IkGeneStart      # Begin gene construction
    IkGeneEnd        # End gene/invoke
    
    # Data construction
    IkArrayStart, IkArrayAddChild, IkArrayEnd
    IkMapStart, IkMapSetProp, IkMapEnd
```

### Register Convention

- **Register 0**: Primary accumulator, return values
- **Register 1**: Secondary operand
- **Register 2-31**: Temporary values

Example instruction sequence for `(a + b)`:
```
IkResolveSymbol a    # Load 'a' into reg 0
IkMove 1 0          # Move to reg 1
IkResolveSymbol b    # Load 'b' into reg 0
IkAdd               # Add reg1 + reg0 → reg0
```

## Virtual Machine Execution

The VM executes bytecode using a register-based architecture with computed goto dispatch.

### VM State

```nim
type
  VirtualMachine* = ref object
    cu*: CompilationUnit       # Current code
    frame*: Frame              # Call frame
    trace*: bool               # Debug flag
    
  Frame* = ref object
    registers*: array[MAX_REGISTERS, Value]
    scope*: Scope              # Variable scope
    ns*: Namespace             # Current namespace
    self*: Value               # For methods
    caller_frame*: Frame       # Call stack
```

### Execution Loop

```nim
proc exec*(self: VirtualMachine): Value =
  var pc = 0
  var inst = self.cu.instructions[pc].addr
  
  while true:
    {.computedGoto.}  # Performance optimization
    case inst.kind:
      of IkAdd:
        let a = self.frame.get_register(1)
        let b = self.frame.get_register(0)
        self.frame.set_register(0, add_values(a, b))
      
      of IkEnd:
        return self.frame.get_register(0)
      
      # ... handle all instructions
    
    pc.inc()
    inst = self.cu.instructions[pc].addr
```

### Function Calls

Function calls use a special protocol:
1. Create frame with IkGeneStartDefault
2. Add arguments with IkGeneAddChild
3. IkGeneEnd triggers actual call
4. New frame pushed, execution jumps to function body

## Command-Line Interface

Gene provides several execution modes through the CLI:

### gene parse
Parses code and displays AST:
```bash
$ gene parse "(+ 1 2)"
(+ 1 2)
```

### gene run
Executes a Gene source file:
```bash
$ gene run program.gene
```

### gene eval
Evaluates an expression:
```bash
$ gene eval "(* 6 7)"
42
```

### gene repl
Interactive Read-Eval-Print Loop:
```bash
$ gene repl
gene> (var x 10)
10
gene> (x + 5)
15
```

**Note**: The CLI implementation is incomplete with TODO markers in the code.

## Module and Namespace System

### Namespaces

Namespaces provide hierarchical organization:

```gene
(ns math
  (fn square [x] (* x x))
  (var PI 3.14159))
```

### Implementation

```nim
type
  Namespace* = ref object
    name*: string
    parent*: Namespace
    members*: Table[Key, Value]
    stop_inheritance*: bool

proc `[]`*(self: Namespace, key: Key): Value =
  # Check local members first
  let found = self.members.get_or_default(key, NOT_FOUND)
  if found != NOT_FOUND:
    return found
  # Check parent if inheritance allowed
  elif not self.stop_inheritance and self.parent != nil:
    return self.parent[key]
```

### Scope Resolution

Gene uses lexical scoping with parent chain lookup:
1. Local scope (current block/function)
2. Parent scopes (lexical chain)
3. Namespace scope
4. Global scope

## Native Function Interface

Native functions bridge Gene and Nim code:

### Definition

```nim
proc native_println(vm: VirtualMachine, args: Value): Value =
  for child in args.gene.children:
    stdout.write($child & " ")
  echo ""
  return NIL
```

### Registration

Native functions are registered in the core module:

```nim
# In vm/core.nim
VM.register_builtin("println", native_println)
VM.register_builtin("trace_start", native_trace_start)
VM.register_builtin("print_stack", native_print_stack)
```

### Built-in Functions

Current native functions:
- `println` - Output with newline
- `trace_start/trace_end` - VM execution tracing
- `print_stack` - Debug register contents
- `print_instructions` - Debug bytecode

## Object-Oriented Programming

Gene supports single inheritance OOP:

### Class Definition

```gene
(class Animal
  (.ctor [name]
    (self/name = name))
  
  (.fn speak []
    "generic sound"))

(class Dog < Animal
  (.fn speak []
    "woof!"))
```

### Implementation

```nim
type
  Class* = ref object
    name*: string
    parent*: Class
    ns*: Namespace      # Methods stored as namespace members
    constructor*: Value # .ctor function

  Instance* = ref object
    class*: Class
    members*: Table[Key, Value]
```

### Method Dispatch

1. Method lookup in instance's class namespace
2. Parent class chain traversal
3. Method bound to instance (self binding)
4. Invocation as regular function

### Object Creation

The `new` operator:
1. Creates instance with class reference
2. Calls constructor (.ctor) if defined
3. Returns initialized instance

## Functional Programming

Gene supports functional programming idioms:

### First-Class Functions

```gene
(var add (fn [x y] (+ x y)))
(add 3 4)  # 7
```

### Anonymous Functions

```gene
(fnx [x] (* x x))  # Lambda syntax
```

### Closures

Functions capture their lexical environment:

```gene
(fn make-adder [n]
  (fnx [x] (+ x n)))  # Captures 'n'

(var add5 (make-adder 5))
(add5 3)  # 8
```

### Higher-Order Functions

Functions can accept and return other functions:

```gene
(fn map [f coll]
  # Apply f to each element
  ...)

(map (fnx [x] (* x 2)) [1 2 3])  # [2 4 6]
```

## Macro System

Gene's macros operate on unevaluated AST:

### Macro Definition

```gene
(macro when [condition body]
  :(if %condition %body nil))
```

### Macro Expansion

1. **Parse**: `(when test expr)`
2. **Bind**: condition=test, body=expr (unevaluated)
3. **Execute macro**: Returns new AST
4. **Replace**: Original replaced with expansion
5. **Compile**: Expanded code compiled normally

### Quote/Unquote

- **Quote** (`:expr`): Prevents evaluation
- **Unquote** (`%var`): Evaluates within quote

```gene
(var x 10)
:(a + %x)  # Expands to: (a + 10)
```

### Implementation

Macros are compiled with quote level tracking:

```nim
proc compile_macro_call(self: Compiler, gene: ptr Gene) =
  self.quote_level.inc()  # Enter quote mode
  # Compile arguments as quoted
  self.quote_level.dec()
  # Generate macro invocation
```

## Pattern Matching

**Note**: Pattern matching syntax exists in examples but implementation is incomplete.

Planned syntax:
```gene
(match value
  pattern1 result1
  pattern2 result2
  _ default)
```

## Selectors

The `/` operator provides unified access:

### Usage

```gene
obj/prop          # Property access
array/0           # Array indexing
map/key           # Map lookup
ns/member         # Namespace member
obj/.method       # Method call (with .)
```

### Implementation

Selectors compile to appropriate get/set instructions:

```nim
# a/b/c compiles to:
IkResolveSymbol a
IkGetMember b
IkGetMember c
```

### Chaining

Complex paths are supported:
```gene
data/users/0/address/city
# Navigates through nested structures
```

## Custom Instruction Support

Gene allows extending the VM with custom instructions:

### Compile-Time Functions

```gene
(compile custom-add [a b]
  [
    ($vm/compile a)      # Compile argument
    ($vm/PUSH 2)         # Push constant
    ($vm/ADD)            # Add instruction
  ])
```

### Implementation

The `compile` form:
1. Executes at compile time
2. Returns array of instructions
3. Instructions replace the call site

### VM Instructions

Custom compile functions can generate:
- Standard VM instructions
- Direct register manipulation
- Complex instruction sequences

### Use Cases

- Domain-specific optimizations
- Macro-like code generation
- Performance-critical operations

## Summary

Gene is a well-architected language combining:

- **Lisp simplicity**: S-expressions with minimal syntax
- **Modern features**: OOP, closures, macros
- **Efficient execution**: Register-based VM
- **Extensibility**: Custom instructions, native functions
- **Clean design**: Clear separation of parser/compiler/VM

The architecture supports future enhancements while maintaining a clean, understandable codebase. The register-based VM provides good performance potential, and the macro system enables powerful metaprogramming.