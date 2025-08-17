# Gene Benchmarks

This directory contains performance benchmarks for the Gene programming language, organized by functionality.

## Directory Structure

### 📊 Core Benchmark Categories

- **`computation/`** - Computational algorithms and mathematical operations
  - Fibonacci sequences, arithmetic operations, loops
  - Tests CPU-intensive operations and function call overhead

- **`allocation/`** - Memory allocation and garbage collection
  - Object creation/destruction, memory pools, GC stress tests
  - Tests memory management efficiency

- **`data_structures/`** - Data structure operations
  - Arrays, maps/dictionaries, strings, collections
  - Tests data access patterns and structure manipulation

- **`oop/`** - Object-oriented programming features
  - Class instantiation, method calls, inheritance
  - Tests OOP performance characteristics

- **`vm_internals/`** - Virtual machine internals and optimizations
  - Bytecode execution, frame management, tail call optimization
  - Tests VM implementation efficiency

### 🔧 Supporting Infrastructure

- **`comparison/`** - Cross-language performance comparisons
  - Equivalent benchmarks in Ruby, Python, JavaScript, etc.
  - Standardized comparison scripts

- **`scripts/`** - Benchmark execution and analysis tools
  - Profiling scripts, result analysis, automation tools

- **`runners/`** - Unified benchmark execution systems
  - Main benchmark runner, category-specific runners

## Quick Start

```bash
# Run all benchmarks
./benchmarks/runners/run_all.sh

# Run specific category
./benchmarks/runners/run_computation.sh

# Compare with other languages
./benchmarks/comparison/compare_all.sh

# Profile a specific benchmark
./benchmarks/scripts/profile.sh computation/fibonacci
```

## Adding New Benchmarks

1. Choose the appropriate category directory
2. Create your benchmark file (`.gene` for Gene code, `.nim` for Nim runners)
3. Add documentation explaining what the benchmark tests
4. Update the category's runner script
5. Add comparison implementations if relevant

## Benchmark Standards

- All benchmarks should include timing measurements
- Use consistent output format for automated analysis
- Include memory usage statistics where relevant
- Document expected performance characteristics
- Provide both Gene and native implementations for comparison

## Performance Tracking

Results are tracked in `results/` with historical data for regression detection.
See `scripts/analyze_trends.sh` for performance trend analysis.

## Migration from Old Structure

This benchmark system replaces the previous scattered structure:

### Old Locations → New Locations
- `bench/fibonacci.gene` → `computation/fibonacci.gene`
- `bench/loop_bench.gene` → `computation/loops.gene`
- `bench/dict_bench.gene` → `data_structures/map_operations.gene`
- `benchmarks/alloc_*.gene` → `allocation/`
- `scripts/bench_*` → `runners/` and `scripts/`
- `scripts/fib_compare` → `comparison/fibonacci_compare.sh`
- `src/benchmark/` → Various categories (now removed)

### Command Migration
```bash
# Old commands (no longer available)
./scripts/bench_suite
./scripts/fib_compare
nim c -r src/benchmark/fibonacci.nim

# New commands
./benchmarks/runners/run_all.sh
./benchmarks/comparison/fibonacci_compare.sh
nim c benchmarks/computation/fibonacci.nim
```

## Performance Expectations

### Computation Benchmarks
- **Fibonacci(24)**: Target >200,000 function calls/second
- **Arithmetic**: Target >10M operations/second
- **Loops**: Target >1M iterations/second

### Allocation Benchmarks
- **Object Pooling**: >80% pool hit rate for common objects
- **GC Overhead**: <5% of total execution time
- **Allocation Speed**: Competitive with native implementations

### Data Structure Benchmarks
- **Array Access**: O(1) random access, competitive with native arrays
- **Map Lookup**: O(1) average case, good hash distribution
- **String Operations**: Efficient for common patterns, minimal copying

### VM Internals
- **Frame Allocation**: >1M frames/second
- **Frame Reuse**: >80% pool hit rate
- **Instruction Execution**: >10M instructions/second
- **TCO Success**: >95% for tail-recursive functions
