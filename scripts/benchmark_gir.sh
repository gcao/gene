#!/bin/bash

# Gene GIR Performance Benchmark Script
# Compares execution time between .gene files (parse+compile+execute)
# and precompiled .gir files (load+execute)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GENE_BIN="./bin/gene"
BUILD_DIR="build"
SMALL_BENCHMARK="examples/gir_benchmark_small.gene"
LARGE_BENCHMARK="examples/gir_benchmark_large.gene"
NUM_RUNS=5

# Check if gene binary exists
if [ ! -f "$GENE_BIN" ]; then
    echo -e "${RED}Error: Gene binary not found at $GENE_BIN${NC}"
    echo "Please run 'nimble build' first"
    exit 1
fi

# Function to run benchmark
run_benchmark() {
    local file=$1
    local mode=$2
    local name=$3
    
    echo -e "\n${BLUE}=== $name ===${NC}"
    
    # Compile to GIR if needed
    if [ "$mode" = "gir" ] || [ "$mode" = "both" ]; then
        echo -e "${YELLOW}Compiling to GIR...${NC}"
        $GENE_BIN compile "$file" >/dev/null 2>&1
        # GIR file maintains directory structure under build/
        gir_file="${BUILD_DIR}/${file%.gene}.gir"
        
        if [ ! -f "$gir_file" ]; then
            echo -e "${RED}Error: Failed to create GIR file${NC}"
            exit 1
        fi
        
        # Show file sizes
        gene_size=$(wc -c < "$file")
        gir_size=$(wc -c < "$gir_file")
        echo -e "Source size: $(printf "%'d" $gene_size) bytes"
        echo -e "GIR size:    $(printf "%'d" $gir_size) bytes"
    fi
    
    # Run benchmarks
    if [ "$mode" = "gene" ] || [ "$mode" = "both" ]; then
        echo -e "\n${GREEN}Direct .gene execution (parse + compile + execute):${NC}"
        total_gene=0
        for i in $(seq 1 $NUM_RUNS); do
            start=$(date +%s.%N)
            $GENE_BIN run --no-gir-cache "$file" > /dev/null 2>&1
            end=$(date +%s.%N)
            elapsed=$(echo "$end - $start" | bc)
            printf "  Run %d: %.4fs\n" $i $elapsed
            total_gene=$(echo "$total_gene + $elapsed" | bc)
        done
        avg_gene=$(echo "scale=4; $total_gene / $NUM_RUNS" | bc)
        echo -e "  ${GREEN}Average: ${avg_gene}s${NC}"
    fi
    
    if [ "$mode" = "gir" ] || [ "$mode" = "both" ]; then
        echo -e "\n${GREEN}Precompiled .gir execution (load + execute):${NC}"
        total_gir=0
        for i in $(seq 1 $NUM_RUNS); do
            start=$(date +%s.%N)
            $GENE_BIN run "$gir_file" > /dev/null 2>&1
            end=$(date +%s.%N)
            elapsed=$(echo "$end - $start" | bc)
            printf "  Run %d: %.4fs\n" $i $elapsed
            total_gir=$(echo "$total_gir + $elapsed" | bc)
        done
        avg_gir=$(echo "scale=4; $total_gir / $NUM_RUNS" | bc)
        echo -e "  ${GREEN}Average: ${avg_gir}s${NC}"
    fi
    
    # Calculate speedup if both modes were run
    if [ "$mode" = "both" ]; then
        if (( $(echo "$avg_gir > 0" | bc -l) )); then
            speedup=$(echo "scale=2; $avg_gene / $avg_gir" | bc)
            savings=$(echo "scale=1; ($avg_gene - $avg_gir) * 1000" | bc)
            percentage=$(echo "scale=1; (($avg_gene - $avg_gir) / $avg_gene) * 100" | bc)
            echo -e "\n${YELLOW}Performance Summary:${NC}"
            echo -e "  Speedup factor: ${speedup}x"
            echo -e "  Time saved: ${savings}ms"
            echo -e "  Improvement: ${percentage}%"
        fi
    fi
}

# Main script
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}    Gene GIR Performance Benchmark   ${NC}"
echo -e "${BLUE}=====================================${NC}"

# Parse command line arguments
BENCHMARK="both"
MODE="both"

while [[ $# -gt 0 ]]; do
    case $1 in
        --small)
            BENCHMARK="small"
            shift
            ;;
        --large)
            BENCHMARK="large"
            shift
            ;;
        --gene-only)
            MODE="gene"
            shift
            ;;
        --gir-only)
            MODE="gir"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --small      Run only the small benchmark (2KB)"
            echo "  --large      Run only the large benchmark (100KB)"
            echo "  --gene-only  Only test direct .gene execution"
            echo "  --gir-only   Only test .gir execution"
            echo "  --help       Show this help message"
            echo ""
            echo "By default, runs both benchmarks in both modes"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Run benchmarks
if [ "$BENCHMARK" = "small" ] || [ "$BENCHMARK" = "both" ]; then
    run_benchmark "$SMALL_BENCHMARK" "$MODE" "Small Benchmark (2KB)"
fi

if [ "$BENCHMARK" = "large" ] || [ "$BENCHMARK" = "both" ]; then
    run_benchmark "$LARGE_BENCHMARK" "$MODE" "Large Benchmark (87KB)"
fi

echo -e "\n${BLUE}=====================================${NC}"
echo -e "${GREEN}Benchmark complete!${NC}"
echo -e "${BLUE}=====================================${NC}"