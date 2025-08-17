#!/bin/bash

# Run all data structure benchmarks

echo "=== Gene Data Structure Benchmarks ==="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$BENCH_DIR/data_structures"

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

# Run Array operations benchmark
echo "1. Array Operations"
echo "------------------"

if [ -f "$DATA_DIR/array_operations.gene" ]; then
    echo "Running array operations benchmark..."
    $GENE_CMD run "$DATA_DIR/array_operations.gene"
    echo ""
fi

# Run Map operations benchmark
echo "2. Map Operations"
echo "----------------"

if [ -f "$DATA_DIR/map_operations.gene" ]; then
    echo "Running map operations benchmark..."
    $GENE_CMD run "$DATA_DIR/map_operations.gene"
    echo ""
fi

# Run String operations benchmark
echo "3. String Operations"
echo "-------------------"

if [ -f "$DATA_DIR/string_operations.gene" ]; then
    echo "Running string operations benchmark..."
    $GENE_CMD run "$DATA_DIR/string_operations.gene"
    echo ""
fi

# Run any additional data structure benchmarks
echo "4. Additional Data Structure Tests"
echo "---------------------------------"

for file in "$DATA_DIR"/*.gene; do
    if [ -f "$file" ]; then
        basename=$(basename "$file" .gene)
        case "$basename" in
            "array_operations"|"map_operations"|"string_operations")
                # Already run above
                ;;
            *)
                echo "Running $basename..."
                $GENE_CMD run "$file"
                echo ""
                ;;
        esac
    fi
done

echo "Data structure benchmarks complete."
echo ""
echo "Performance notes:"
echo "- Array access should be O(1) with minimal overhead"
echo "- Map lookup should be O(1) average case"
echo "- String operations should minimize memory copying"
echo "- Iteration should be linear with low constant factors"
