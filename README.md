# Gene Programming Language

Gene is a general-purpose programming language with a Lisp-like syntax, implemented in Nim. This repository contains the VM-based implementation that compiles Gene code to bytecode for execution.

## Project Status

This is the **active development branch** implementing a bytecode VM for improved performance. For the reference tree-walking interpreter implementation, see the `gene-new/` directory.

## Features

- **Homoiconic** - Code is data (like Lisp)
- **Functional Programming** - First-class functions, closures
- **Object-Oriented Programming** - Classes and methods  
- **Pattern Matching** - Destructuring and matching
- **Macros** - Code generation at compile time
- **Dynamic Typing** - With optional type annotations
- **Bytecode VM** - Compiles to bytecode for execution
- **AI/ML Support** - Native tensor operations and model management (new!)
- **FFI System** - Call C libraries directly
- **Python Bridge** - Interoperate with Python ecosystem

## Quick Start

### Prerequisites

- [Nim](https://nim-lang.org/) 1.6+ 
- C compiler (gcc, clang, or Visual Studio)

### Building

```bash
# Clone the repository
git clone https://github.com/gcao/gene
cd gene

# Build the Gene executable
nimble build

# Or build directly with Nim
nim c -o:gene src/gene.nim
```

### Running Gene

```bash
# Run a Gene file
./gene run examples/hello_world.gene

# Start interactive REPL
./gene repl

# Evaluate an expression
./gene eval '(+ 1 2)'

# Parse and show AST
./gene parse examples/simple.gene

# Compile and show bytecode
./gene compile examples/simple.gene
```

## Examples

```gene
# Hello World
(print "Hello, World!")

# Define a function
(fn add [a b]
  (+ a b))

# Fibonacci
(fn fib [n]
  (if (< n 2)
    n
    (+ (fib (- n 1)) (fib (- n 2)))))

(print "fib(10) =" (fib 10))
```

See the `examples/` directory for more examples.

## Project Structure

```
gene/
├── src/               # Source code
│   ├── gene.nim      # Main entry point
│   ├── gene/
│   │   ├── types.nim     # Core type definitions
│   │   ├── parser.nim    # Parser implementation  
│   │   ├── compiler.nim  # Bytecode compiler
│   │   ├── vm.nim        # Virtual machine
│   │   └── commands/     # CLI commands
├── tests/            # Unit tests
├── testsuite/        # Integration tests
├── examples/         # Example Gene programs
├── docs/            # Documentation
├── scripts/         # Utility scripts
└── gene-new/        # Reference implementation

```

## Development

### Running Tests

```bash
# Run all unit tests
nimble test

# Run specific test file
nim c -r tests/test_parser.nim

# Run integration test suite
./testsuite/run_tests.sh
```

### Benchmarking

```bash
# Run performance benchmarks
./scripts/benchme

# Compare with other languages
./scripts/fib_compare
```

## AI/ML Capabilities (New!)

Gene now includes native support for AI/ML workloads:

### Tensor Operations
```gene
# Create and manipulate tensors
(var a (tensor/create [2 3] :float32 :cuda))
(var b (tensor/create [3 4] :float32 :cuda))
(var c (tensor/matmul a b))  # Matrix multiplication
```

### Model Management
```gene
# Load and run models
(var model (model/create "my-model" "onnx"))
(var output (model/forward model input))
```

### FFI and Python Integration
```gene
# Call C libraries
(ffi/load "torch" "/path/to/libtorch.so")

# Use Python libraries (coming soon)
(python/import numpy :as np)
```

See [AI/ML Guide](docs/tensor-api-guide.md) for complete documentation.

## Documentation

- [Getting Started](docs/getting-started.md) - Tutorial for new users
- [Language Reference](docs/language-reference.md) - Complete language guide
- [Architecture](docs/architecture.md) - VM design and implementation
- [AI/ML Guide](docs/tensor-api-guide.md) - Tensor and AI features
- [Contributing](docs/contributing.md) - How to contribute

## Performance

Current VM performance (fib(24) benchmark):
- Gene VM: ~600K function calls/sec
- Python: ~25M calls/sec (41x faster)
- Ruby: ~35M calls/sec (57x faster)

See [Performance Analysis](docs/performance_analysis.md) for optimization roadmap.

## License

[MIT License](LICENSE)

## Credits

Created by Yanfeng Liu (@gcao)