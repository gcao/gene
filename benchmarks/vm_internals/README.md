# VM Internals Benchmarks

This directory contains benchmarks focused on Gene Virtual Machine internals and optimizations.

## Benchmarks

### `tco.nim` / `tco.rb`
- **Purpose**: Tests tail call optimization effectiveness
- **Algorithm**: Tail-recursive functions with deep call stacks
- **Metrics**: Stack usage, execution time, optimization success rate

### `simple_profile.nim`
- **Purpose**: Basic VM profiling and performance measurement
- **Focus**: Instruction execution, frame management, basic operations
- **Metrics**: Instructions per second, frame allocation overhead

### `trace_profile.nim`
- **Purpose**: Detailed execution tracing and analysis
- **Focus**: Instruction-level performance, hotspot identification
- **Metrics**: Instruction distribution, execution patterns

### `vm_profile.nim`
- **Purpose**: Comprehensive VM performance analysis
- **Focus**: Overall VM efficiency, memory usage, optimization effectiveness
- **Metrics**: VM overhead, memory efficiency, optimization impact

## Running VM Benchmarks

```bash
# Run all VM internal benchmarks
../runners/run_vm_internals.sh

# Run specific benchmark with compilation
nim c -d:release -o:bin/simple_profile simple_profile.nim
./bin/simple_profile

# Run with detailed profiling
GENE_TRACE=1 GENE_PROFILE=1 ./bin/vm_profile

# Analyze tail call optimization
./bin/tco
```

## Key Metrics

### Frame Management
- **Frame Allocation Rate**: Frames allocated per second
- **Frame Reuse Rate**: Percentage of frames reused from pool
- **Frame Overhead**: Memory and time overhead per frame

### Instruction Execution
- **Instructions Per Second**: Raw instruction execution rate
- **Instruction Distribution**: Frequency of different instruction types
- **Hotspot Analysis**: Most frequently executed code paths

### Memory Management
- **Allocation Overhead**: Time spent in memory allocation
- **GC Impact**: Garbage collection frequency and pause times
- **Pool Efficiency**: Object pool hit rates and effectiveness

### Optimization Effectiveness
- **TCO Success Rate**: Tail calls successfully optimized
- **Inlining Impact**: Performance improvement from function inlining
- **Constant Folding**: Compile-time optimization effectiveness

## Performance Targets

- **Frame Allocation**: >1M frames/second
- **Frame Reuse**: >80% pool hit rate
- **Instruction Execution**: >10M instructions/second
- **TCO Success**: >95% for tail-recursive functions
- **Memory Overhead**: <20% of total execution time

## VM Architecture Notes

### Frame Management
- Pooled frame allocation for reduced GC pressure
- Efficient frame stack management
- Optimized variable access patterns

### Instruction Set
- Stack-based virtual machine
- Optimized instruction encoding
- Efficient instruction dispatch

### Memory Model
- Reference counting with cycle detection
- Object pooling for common types
- Generational garbage collection

### Optimizations
- Tail call optimization
- Constant folding and propagation
- Dead code elimination
- Function inlining (planned)
