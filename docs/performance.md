# Gene Performance Guide

This document covers performance analysis, comparisons, and optimization strategies for the Gene VM.

## Current Performance

### Benchmark Results (fib(24) - 150,049 function calls)

| Language | Time (seconds) | Calls/second | Relative Speed |
|----------|---------------|--------------|----------------|
| Node.js  | 0.001         | 150,049,000  | 245x           |
| Ruby     | 0.004         | 35,074,800   | 57x            |
| Python   | 0.006         | 25,138,012   | 41x            |
| Gene VM  | 0.245         | 611,694      | 1x (baseline)  |

**Note**: None of these languages implement automatic memoization - all make the full 150,049 calls.

### Performance by Platform

- macOS x86_64: ~297K calls/sec
- Linux ARM64 (Vagrant): ~750K calls/sec
- Under Valgrind: ~10-12K calls/sec (expected slowdown)

## Bottleneck Analysis

### Valgrind Profiling Results

Top hotspots from callgrind analysis:

1. **Memory Allocation (15.46%)**
   - `newSeq` operations dominate
   - Every function call allocates a new frame
   - Temporary values create allocation pressure

2. **VM Execution (11.19%)**
   - Instruction dispatch overhead
   - No instruction caching
   - Branch misprediction in switch statement

3. **Type Checking (7.85%)**
   - `kind` field access for discriminated unions
   - Frequent type checks in generic operations
   - No type specialization

4. **Memory Operations (~20% combined)**
   - Value copying
   - Reference counting overhead
   - Cache misses on value access

### Cache Performance
- Instruction cache miss rate: 3.08%
- Data cache miss rate: 1.3%
- Last-level cache miss rate: 0.2%

Good cache performance indicates algorithmic rather than memory access issues.

## Optimization Strategies

### 1. Quick Wins (10-30% improvement each)

**Inline Critical Functions**
```nim
template kind_fast(v: Value): ValueKind {.inline.} =
  when NimMajor >= 2:
    {.cast(noSideEffect).}: v.kind
  else:
    v.kind
```

**Pool Common Objects**
```nim
var frame_pool: seq[Frame]
var array_pool: Table[int, seq[seq[Value]]]

proc new_frame_pooled(): Frame =
  if frame_pool.len > 0:
    result = frame_pool.pop()
    result.reset()
  else:
    result = Frame()
```

**Optimize Instruction Dispatch**
```nim
# Use computed goto if available
template dispatch() =
  when defined(computedGoto):
    goto labels[instructions[pc].kind]
  else:
    case instructions[pc].kind
```

### 2. Medium-term Improvements (2-5x speedup)

**Inline Caching**
- Cache method lookups at call sites
- Monomorphic inline caches first
- Polymorphic caches for hot paths

**Specialized Instructions**
```nim
# Instead of: IkPush 1, IkPush 2, IkAdd
# Generate: IkAddImm 1 2
```

**Type Specialization**
- Generate specialized code for common types
- Avoid boxing for primitive operations
- Fast paths for integer arithmetic

### 3. Long-term Architecture (10x+ speedup)

**Just-In-Time Compilation**
- Identify hot functions
- Generate native code
- Inline small functions

**Register-based VM**
- Reduce stack manipulation
- Better instruction-level parallelism
- Easier to JIT compile

**Escape Analysis**
- Stack-allocate non-escaping objects
- Eliminate unnecessary allocations
- Scalar replacement of aggregates

## Profiling Tools

### Built-in Profilers

1. **Simple Profiler** (`src/benchmark/simple_profile.nim`)
   - Shows bytecode statistics
   - Instruction distribution

2. **Trace Profiler** (`src/benchmark/trace_profile.nim`)
   - Captures instruction traces
   - Useful for debugging

3. **VM Profiler** (`src/benchmark/vm_profile.nim`)
   - Detailed instruction timing
   - Identifies hot instructions

### External Tools

**macOS**
```bash
# Instruments
instruments -t "Time Profiler" ./gene run script.gene

# Sample
sample gene 1000 -file samples.txt
```

**Linux**
```bash
# Perf
perf record -g ./gene run script.gene
perf report

# Valgrind
valgrind --tool=callgrind ./gene run script.gene
kcachegrind callgrind.out
```

## Optimization Checklist

When optimizing Gene code:

1. **Profile First**
   - Measure before optimizing
   - Focus on hot paths
   - Use appropriate tools

2. **Algorithm Level**
   - Better algorithms beat micro-optimizations
   - Reduce unnecessary work
   - Cache computed results

3. **VM Level**
   - Minimize allocations
   - Reduce function calls
   - Use efficient data structures

4. **Code Patterns**
   ```gene
   # Avoid
   (map (fn [x] (+ x 1)) list)
   
   # Prefer (when available)
   (map .+ list 1)
   ```

## Benchmarking

### Running Benchmarks
```bash
# Basic benchmark
./scripts/benchme

# Compare with other languages
./scripts/fib_compare

# Custom benchmark
nim c -d:release src/benchmark/custom.nim
```

### Writing Benchmarks
```nim
import times, strformat

let start = cpu_time()
# ... code to benchmark ...
let duration = cpu_time() - start
echo fmt"Time: {duration:.6f} seconds"
```

## Future Performance Goals

### Short Term (3-6 months)
- Target: 2-5M calls/sec
- Focus: Memory allocation optimization
- Approach: Object pooling, frame reuse

### Medium Term (6-12 months)  
- Target: 10-20M calls/sec
- Focus: Inline caching, specialized instructions
- Approach: Tier 1 JIT compiler

### Long Term (1+ years)
- Target: 100M+ calls/sec
- Focus: Full JIT compilation
- Approach: LLVM backend or custom code generator

## Monitoring Progress

Track these metrics:
- Instructions per second
- Function calls per second  
- Memory allocations per operation
- Cache hit rates
- Benchmark execution times

Regular benchmarking against reference implementations (Ruby, Python, Lua) ensures Gene remains competitive.