#!/bin/bash

# Run all VM internals benchmarks

echo "=== Gene VM Internals Benchmarks ==="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
VM_DIR="$BENCH_DIR/vm_internals"

# Ensure we're in the right directory
cd "$BENCH_DIR/.." || exit 1

# Enable detailed VM statistics
export GENE_MEMORY_STATS=1
export GENE_POOL_STATS=1
export GENE_FRAME_STATS=1
export GENE_VM_STATS=1

echo "VM statistics enabled"
echo ""

# Run TCO benchmarks
echo "1. Tail Call Optimization"
echo "------------------------"

if [ -f "$VM_DIR/tco.nim" ]; then
    echo "Compiling and running TCO benchmark..."
    if [ -f "./bin/tco" ]; then
        ./bin/tco
    else
        echo "Compiling TCO benchmark..."
        nim c -d:release -o:bin/tco "$VM_DIR/tco.nim"
        if [ -f "./bin/tco" ]; then
            ./bin/tco
        fi
    fi
    echo ""
fi

# Run simple profiling
echo "2. Simple VM Profile"
echo "-------------------"

if [ -f "$VM_DIR/simple_profile.nim" ]; then
    echo "Compiling and running simple profile..."
    if [ -f "./bin/simple_profile" ]; then
        ./bin/simple_profile
    else
        echo "Compiling simple profile..."
        nim c -d:release -o:bin/simple_profile "$VM_DIR/simple_profile.nim"
        if [ -f "./bin/simple_profile" ]; then
            ./bin/simple_profile
        fi
    fi
    echo ""
fi

# Run trace profiling
echo "3. Trace Profile"
echo "---------------"

if [ -f "$VM_DIR/trace_profile.nim" ]; then
    echo "Compiling and running trace profile..."
    if [ -f "./bin/trace_profile" ]; then
        GENE_TRACE=1 ./bin/trace_profile
    else
        echo "Compiling trace profile..."
        nim c -d:release -o:bin/trace_profile "$VM_DIR/trace_profile.nim"
        if [ -f "./bin/trace_profile" ]; then
            GENE_TRACE=1 ./bin/trace_profile
        fi
    fi
    echo ""
fi

# Run comprehensive VM profiling
echo "4. Comprehensive VM Profile"
echo "---------------------------"

if [ -f "$VM_DIR/vm_profile.nim" ]; then
    echo "Compiling and running VM profile..."
    if [ -f "./bin/vm_profile" ]; then
        ./bin/vm_profile
    else
        echo "Compiling VM profile..."
        nim c -d:release -o:bin/vm_profile "$VM_DIR/vm_profile.nim"
        if [ -f "./bin/vm_profile" ]; then
            ./bin/vm_profile
        fi
    fi
    echo ""
fi

echo "VM internals benchmarks complete."
echo ""
echo "Key metrics to review:"
echo "- Frame allocation and reuse rates"
echo "- Instruction execution performance"
echo "- Memory management efficiency"
echo "- Tail call optimization success"
echo "- Overall VM overhead"
