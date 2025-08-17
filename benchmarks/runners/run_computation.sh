#!/bin/bash

# Run all computation benchmarks

echo "=== Gene Computation Benchmarks ==="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
COMPUTATION_DIR="$BENCH_DIR/computation"

# Ensure we're in the right directory
cd "$BENCH_DIR/.." || exit 1

# Build Gene if needed
if [ ! -f "./gene" ] && [ ! -f "./bin/gene" ]; then
    echo "Building Gene..."
    nimble build 2>&1 | grep -v "Warning:" | grep -v "ignoring duplicate" || true
    echo ""
fi

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

# Run Fibonacci benchmarks
echo "1. Fibonacci Benchmarks"
echo "----------------------"

if [ -f "$COMPUTATION_DIR/fibonacci.gene" ]; then
    echo "Running fibonacci.gene..."
    $GENE_CMD run "$COMPUTATION_DIR/fibonacci.gene"
    echo ""
fi

if [ -f "$COMPUTATION_DIR/fibonacci.nim" ]; then
    echo "Running compiled fibonacci benchmark..."
    if [ -f "./bin/fibonacci" ]; then
        ./bin/fibonacci
    else
        echo "Compiling fibonacci benchmark..."
        nim c -d:release -o:bin/fibonacci "$COMPUTATION_DIR/fibonacci.nim"
        if [ -f "./bin/fibonacci" ]; then
            ./bin/fibonacci
        fi
    fi
    echo ""
fi

# Run Arithmetic benchmarks
echo "2. Arithmetic Benchmarks"
echo "------------------------"

for file in "$COMPUTATION_DIR"/arithmetic*.nim; do
    if [ -f "$file" ]; then
        basename=$(basename "$file" .nim)
        echo "Running $basename..."
        if [ -f "./bin/$basename" ]; then
            "./bin/$basename"
        else
            echo "Compiling $basename..."
            nim c -d:release -o:"bin/$basename" "$file"
            if [ -f "./bin/$basename" ]; then
                "./bin/$basename"
            fi
        fi
        echo ""
    fi
done

# Run Loop benchmarks
echo "3. Loop Benchmarks"
echo "-----------------"

if [ -f "$COMPUTATION_DIR/loops.gene" ]; then
    echo "Running loops.gene..."
    $GENE_CMD run "$COMPUTATION_DIR/loops.gene"
    echo ""
fi

echo "Computation benchmarks complete."
