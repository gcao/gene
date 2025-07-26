# Gene Benchmarks

This directory contains performance benchmarks for the Gene programming language VM.

## Available Benchmarks

### fibonacci.nim
Classic recursive fibonacci benchmark. Tests function call overhead and integer arithmetic.

Usage:
```bash
# Run with default n=24
./scripts/benchme

# Run with custom n
./scripts/benchme 30
```

## Running Benchmarks

### Quick Benchmark
```bash
./scripts/benchme [n]
```

### Benchmark Suite
```bash
./scripts/bench_suite
```

### Compare with Other Languages
```bash
./scripts/bench_compare [n]
```

## Results

Current performance (M1 MacBook):
- fib(24): ~0.30 seconds (~245,000 function calls/second)

## Adding New Benchmarks

1. Create a new `.nim` file in this directory
2. Import required Gene modules
3. Implement the benchmark with timing
4. Add to `bench_suite` script

Example structure:
```nim
when isMainModule:
  import times, os, strformat
  import ../gene/types, ../gene/parser, ../gene/compiler, ../gene/vm

  init_app_and_vm()
  
  let code = """
    # Your Gene code here
  """
  
  let compiled = compile(read_all(code))
  # ... setup VM ...
  
  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  echo fmt"Result: {result}"
  echo fmt"Time: {duration:.6f} seconds"
```

## Optimization Tracking

See [optimization.md](../../docs/optimization.md) for performance improvement recommendations and tracking.