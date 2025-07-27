#!/bin/bash

# Script to run only the tests that work with current VM implementation

GENE="../gene"

echo "=== Running Working Tests ==="
echo

# Basics
echo "--- basics ---"
for test in basics/hello_world.gene basics/literals.gene basics/variables.gene; do
    echo -n "$test: "
    if $GENE run "$test" > /tmp/out 2>&1; then
        echo "PASS"
    else
        echo "FAIL"
        cat /tmp/out | sed 's/^/  /'
    fi
done
echo

# Minimal tests
echo "--- minimal ---"
for test in minimal/arithmetic.gene minimal/control_flow.gene minimal/functions.gene minimal/strings.gene minimal/variables.gene; do
    echo -n "$test: "
    if $GENE run "$test" > /tmp/out 2>&1; then
        echo "PASS"
    else
        echo "FAIL"
        cat /tmp/out | sed 's/^/  /'
    fi
done
echo

# Strings
echo "--- strings ---"
echo -n "strings/basic_strings.gene: "
if $GENE run strings/basic_strings.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi
echo

# Arrays (just creation)
echo "--- arrays ---"
echo -n "arrays/basic_arrays.gene: "
if $GENE run arrays/basic_arrays.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi
echo

# Maps (just creation and access)
echo "--- maps ---"
echo -n "maps/basic_maps.gene: "
if $GENE run maps/basic_maps.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi
echo

# Functions
echo "--- functions ---"
echo -n "functions/basic_functions.gene: "
if $GENE run functions/basic_functions.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi
echo

# Control flow
echo "--- control_flow ---"
echo -n "control_flow/if_else.gene: "
if $GENE run control_flow/if_else.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi
echo

# Arithmetic
echo "--- arithmetic ---"
echo -n "arithmetic/basic_math.gene: "
if $GENE run arithmetic/basic_math.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi
echo

# Operators
echo "--- operators ---"
echo -n "operators/comparison.gene: "
if $GENE run operators/comparison.gene > /tmp/out 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    cat /tmp/out | sed 's/^/  /'
fi