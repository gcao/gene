#!/bin/bash

# Run all allocation benchmarks

echo "=== Gene Allocation Benchmarks ==="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
ALLOCATION_DIR="$BENCH_DIR/allocation"

# Ensure we're in the right directory
cd "$BENCH_DIR/.." || exit 1

# Find Gene executable
GENE_CMD=""
if [ -f "./gene" ]; then
    GENE_CMD="./gene"
elif [ -f "./bin/gene" ]; then
    GENE_CMD="./bin/gene"
else
    echo "Error: Gene executable not found"
    exit 1
fi

echo "Using Gene executable: $GENE_CMD"
echo ""

# Enable memory statistics
export GENE_MEMORY_STATS=1
export GENE_POOL_STATS=1

echo "Memory statistics enabled"
echo ""

# Run allocation stress test
echo "1. Allocation Stress Test"
echo "------------------------"

if [ -f "$ALLOCATION_DIR/stress_test.gene" ]; then
    echo "Running allocation stress test..."
    $GENE_CMD run "$ALLOCATION_DIR/stress_test.gene"
    echo ""
fi

# Run pool efficiency test
echo "2. Pool Efficiency Test"
echo "----------------------"

if [ -f "$ALLOCATION_DIR/pool_efficiency.gene" ]; then
    echo "Running pool efficiency test..."
    $GENE_CMD run "$ALLOCATION_DIR/pool_efficiency.gene"
    echo ""
fi

# Run basic allocation benchmark
echo "3. Basic Allocation Benchmark"
echo "----------------------------"

if [ -f "$ALLOCATION_DIR/alloc_bench.gene" ]; then
    echo "Running basic allocation benchmark..."
    $GENE_CMD run "$ALLOCATION_DIR/alloc_bench.gene"
    echo ""
fi

# Run other allocation tests
echo "4. Additional Allocation Tests"
echo "-----------------------------"

for file in "$ALLOCATION_DIR"/alloc_*.gene; do
    if [ -f "$file" ] && [ "$(basename "$file")" != "alloc_bench.gene" ]; then
        basename=$(basename "$file" .gene)
        echo "Running $basename..."
        $GENE_CMD run "$file"
        echo ""
    fi
done

# Run simple tests
for file in "$ALLOCATION_DIR"/simple_*.gene; do
    if [ -f "$file" ]; then
        basename=$(basename "$file" .gene)
        echo "Running $basename..."
        $GENE_CMD run "$file"
        echo ""
    fi
done

echo "Allocation benchmarks complete."
echo ""
echo "Note: Check memory statistics above for:"
echo "- Pool hit rates (should be >80% for common objects)"
echo "- Allocation counts and reuse rates"
echo "- Memory usage patterns"
