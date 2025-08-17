# Allocation Benchmarks

This directory contains benchmarks focused on memory allocation, garbage collection, and object lifecycle management.

## Benchmarks

### `stress_test.gene`
- **Purpose**: Stress tests memory allocation with high object creation rates
- **Objects**: Gene expressions, arrays, maps, strings
- **Metrics**: Allocations per second, GC pressure, memory usage

### `pool_efficiency.gene`
- **Purpose**: Tests object pooling effectiveness
- **Focus**: Frame allocation/reuse, reference pooling
- **Metrics**: Pool hit rate, allocation overhead reduction

### `gc_behavior.gene`
- **Purpose**: Tests garbage collection behavior under various loads
- **Scenarios**: Burst allocation, steady allocation, mixed patterns
- **Metrics**: GC frequency, pause times, memory reclamation

### `nested_structures.gene`
- **Purpose**: Tests allocation of complex nested data structures
- **Structures**: Nested maps, arrays of objects, tree structures
- **Metrics**: Deep allocation performance, reference management

### `string_allocation.gene`
- **Purpose**: Tests string creation and manipulation performance
- **Operations**: String creation, concatenation, substring operations
- **Metrics**: String operations per second, memory efficiency

## Running Allocation Benchmarks

```bash
# Run all allocation benchmarks
../runners/run_allocation.sh

# Run with memory profiling
../scripts/memory_profile.sh stress_test.gene

# Monitor GC behavior
GENE_GC_STATS=1 gene gc_behavior.gene

# Test pool efficiency
../scripts/pool_analysis.sh pool_efficiency.gene
```

## Key Metrics

- **Allocation Rate**: Objects allocated per second
- **Pool Hit Rate**: Percentage of allocations served from pools
- **GC Frequency**: Garbage collection cycles per second
- **Memory Efficiency**: Peak memory usage vs. working set
- **Allocation Overhead**: Time spent in allocation vs. computation

## Optimization Targets

- **Object Pooling**: >80% pool hit rate for common objects
- **GC Overhead**: <5% of total execution time
- **Allocation Speed**: Competitive with native implementations
- **Memory Usage**: Minimal fragmentation and overhead

## Memory Management Features Tested

- Reference counting for immediate cleanup
- Object pooling for Gene, Array, Map objects
- String interning for common strings
- Frame pooling for function calls
- Generational GC for long-lived objects
