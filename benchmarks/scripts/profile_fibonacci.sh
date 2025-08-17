#!/bin/bash

# Script to profile fibonacci benchmark with callgrind

echo "=== Profiling Gene Fibonacci Benchmark ==="

# Clean up previous results
rm -f callgrind.out.* bin/fibonacci_profile

# Compile with debug info and no optimizations for profiling
# Use --debugger:native for better debug symbols
# Use --opt:none to disable optimizations
# Use --debuginfo:on for full debug information
echo "Compiling fibonacci benchmark for profiling..."
nim c \
  --gc:orc \
  --debugger:native \
  --opt:none \
  --debuginfo:on \
  --lineDir:on \
  --stackTrace:on \
  --out:bin/fibonacci_profile \
  src/benchmark/fibonacci.nim

if [ $? -ne 0 ]; then
  echo "Compilation failed!"
  exit 1
fi

echo "Running valgrind/callgrind..."
valgrind \
  --tool=callgrind \
  --dump-instr=yes \
  --collect-jumps=yes \
  --callgrind-out-file=callgrind.out.fib \
  ./bin/fibonacci_profile 10  # Use smaller n for cleaner profile

echo ""
echo "Profiling complete! Output saved to callgrind.out.fib"
echo ""
echo "To view the results:"
echo "1. With kcachegrind: ./run_kcachegrind.sh callgrind.out.fib"
echo "2. With callgrind_annotate: callgrind_annotate callgrind.out.fib"
echo ""
echo "Top functions by self time:"
callgrind_annotate callgrind.out.fib | head -30