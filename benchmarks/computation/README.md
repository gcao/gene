# Computation Benchmarks

This directory contains benchmarks focused on computational algorithms and mathematical operations.

## Benchmarks

### `fibonacci.gene` / `fibonacci.nim`
- **Purpose**: Tests recursive function calls and integer arithmetic
- **Algorithm**: Classic recursive Fibonacci sequence
- **Metrics**: Function calls per second, execution time
- **Variants**: Different input sizes (fib(20), fib(24), fib(30))

### `arithmetic.gene` / `arithmetic.nim`
- **Purpose**: Tests basic arithmetic operations
- **Operations**: Addition, subtraction, multiplication, division
- **Metrics**: Operations per second, numerical accuracy

### `loops.gene`
- **Purpose**: Tests loop constructs and iteration performance
- **Types**: for loops, while loops, nested loops
- **Metrics**: Iterations per second, loop overhead

### `primes.gene`
- **Purpose**: Tests computational algorithms with moderate complexity
- **Algorithm**: Prime number generation using sieve
- **Metrics**: Primes generated per second, memory efficiency

## Running Computation Benchmarks

```bash
# Run all computation benchmarks
../runners/run_computation.sh

# Run specific benchmark
gene fibonacci.gene

# Run with profiling
../scripts/profile.sh fibonacci.gene

# Compare with other languages
../comparison/fibonacci_compare.sh
```

## Performance Expectations

- **Fibonacci(24)**: Target ~200,000+ function calls/second
- **Arithmetic**: Target ~10M+ operations/second  
- **Loops**: Target ~1M+ iterations/second
- **Primes**: Target varies by algorithm complexity

## Optimization Notes

- Function call overhead is critical for recursive algorithms
- Integer arithmetic should be highly optimized
- Loop constructs should minimize interpreter overhead
- Consider tail call optimization for recursive functions
