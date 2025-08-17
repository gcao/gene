# Data Structures Benchmarks

This directory contains benchmarks focused on data structure operations and access patterns.

## Benchmarks

### `array_operations.gene`
- **Purpose**: Tests array creation, access, and manipulation
- **Operations**: Creation, indexing, iteration, modification, resizing
- **Metrics**: Operations per second, memory efficiency

### `map_operations.gene`
- **Purpose**: Tests map/dictionary performance
- **Operations**: Creation, key lookup, insertion, deletion, iteration
- **Metrics**: Lookup speed, hash collision handling, resize performance

### `string_operations.gene`
- **Purpose**: Tests string manipulation and processing
- **Operations**: Creation, concatenation, substring, search, replace
- **Metrics**: String operations per second, memory usage

### `collection_iteration.gene`
- **Purpose**: Tests iteration performance across different collection types
- **Collections**: Arrays, maps, sets, custom collections
- **Metrics**: Iteration speed, memory access patterns

### `nested_access.gene`
- **Purpose**: Tests deep nested structure access performance
- **Patterns**: Deep object graphs, nested arrays, complex maps
- **Metrics**: Access time complexity, cache efficiency

### `serialization.gene`
- **Purpose**: Tests data structure serialization/deserialization
- **Formats**: Gene native format, JSON-like structures
- **Metrics**: Serialization speed, size efficiency

## Running Data Structure Benchmarks

```bash
# Run all data structure benchmarks
../runners/run_data_structures.sh

# Test specific operations
gene array_operations.gene
gene map_operations.gene

# Profile memory access patterns
../scripts/cache_profile.sh nested_access.gene

# Compare with native implementations
../comparison/data_structures_compare.sh
```

## Performance Expectations

- **Array Access**: O(1) random access, competitive with native arrays
- **Map Lookup**: O(1) average case, good hash distribution
- **String Operations**: Efficient for common patterns, minimal copying
- **Iteration**: Linear performance, minimal overhead
- **Nested Access**: Reasonable performance for deep structures

## Key Metrics

- **Access Time**: Time for single element access
- **Throughput**: Operations per second for bulk operations
- **Memory Efficiency**: Memory overhead vs. data size
- **Cache Performance**: CPU cache hit rates for access patterns
- **Scalability**: Performance with increasing data sizes

## Data Structure Features Tested

- **Arrays**: Dynamic resizing, bounds checking, iteration
- **Maps**: Hash table implementation, collision resolution, load factor
- **Strings**: Immutable strings, efficient concatenation, substring views
- **Collections**: Generic collection interfaces, type safety
- **Memory Layout**: Cache-friendly data organization
