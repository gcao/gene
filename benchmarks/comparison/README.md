# Cross-Language Performance Comparisons

This directory contains benchmarks that compare Gene's performance with other programming languages.

## Available Comparisons

### `fibonacci_compare.sh`
- **Languages**: Gene, Ruby, Python, Node.js
- **Algorithm**: Recursive Fibonacci(24)
- **Metrics**: Function calls per second, execution time
- **Purpose**: Compare function call overhead and basic arithmetic

### `compare_languages`
- **Languages**: Gene, Ruby, Python
- **Tests**: Multiple algorithm implementations
- **Purpose**: Comprehensive language performance comparison

## Running Comparisons

```bash
# Run Fibonacci comparison
./fibonacci_compare.sh

# Run comprehensive language comparison
./compare_languages

# Run all comparisons
../runners/run_all.sh --compare
```

## Benchmark Standards

All comparison benchmarks follow these standards:

- **Equivalent Algorithms**: Same algorithmic complexity across languages
- **Fair Testing**: No language-specific optimizations that others can't use
- **Consistent Metrics**: Same measurement methodology for all languages
- **Multiple Runs**: Average results over multiple executions when possible

## Expected Performance

### Fibonacci(24) Baseline Results
- **Ruby**: ~50,000-100,000 calls/sec
- **Python**: ~100,000-200,000 calls/sec  
- **Node.js**: ~500,000-1,000,000 calls/sec
- **Gene Target**: >200,000 calls/sec

### Performance Goals
- **Competitive**: Within 2-5x of interpreted languages (Ruby, Python)
- **Reasonable**: Within 10x of JIT-compiled languages (Node.js)
- **Improving**: Consistent performance improvements over time

## Adding New Comparisons

1. Choose a representative algorithm
2. Implement equivalent versions in each language
3. Use consistent timing methodology
4. Document expected performance characteristics
5. Add to the comparison runner scripts

## Language-Specific Notes

### Ruby
- Uses standard MRI Ruby interpreter
- No special optimizations or gems
- Represents typical dynamic language performance

### Python
- Uses Python 3.x interpreter
- No NumPy or other performance libraries
- Pure Python implementations only

### Node.js
- Uses V8 JavaScript engine
- Benefits from JIT compilation
- Represents modern dynamic language performance

### Gene
- Uses Gene VM with current optimizations
- Tests real-world Gene performance
- Includes memory management overhead
