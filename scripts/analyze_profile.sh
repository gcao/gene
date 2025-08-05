#!/bin/bash

# Analyze callgrind output for Gene VM

echo "=== Analyzing Gene VM Profile ==="
echo ""

# Show top functions excluding system libraries
echo "Top Gene VM functions (excluding stdlib):"
callgrind_annotate callgrind.out.fib | grep -E "(src/gene|vm/)" | head -20

echo ""
echo "=== VM-specific statistics ==="

# Look for VM execution functions
echo ""
echo "VM execution functions:"
callgrind_annotate callgrind.out.fib | grep -E "(exec|eval|dispatch|opcode)" | head -10

echo ""
echo "Type system overhead:"
callgrind_annotate callgrind.out.fib | grep -E "(Value|eqcopy|to_int|new_)" | head -10

echo ""
echo "Memory management overhead:"
callgrind_annotate callgrind.out.fib | grep -E "(alloc|free|gc)" | head -10

echo ""
echo "To visualize interactively, run:"
echo "  ./run_kcachegrind.sh callgrind.out.fib"