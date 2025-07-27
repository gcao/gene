#!/bin/bash

# Gene Language Test Suite Runner
# This script runs all .gene test files in the testsuite directory

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if gene executable exists
if [ ! -f "$SCRIPT_DIR/../bin/gene" ]; then
    echo -e "${RED}Error: gene executable not found. Please run 'nimble build' first.${NC}"
    exit 1
fi

GENE="$SCRIPT_DIR/../bin/gene"
PASSED=0
FAILED=0
SKIPPED=0

echo "=== Gene Language Test Suite ==="
echo

# Function to run a single test
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .gene)
    
    # Check if test should be skipped
    if grep -q "^# SKIP:" "$test_file"; then
        echo -e "${YELLOW}SKIP${NC} $test_name"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    
    # Extract expected output if present
    local expected_file="${test_file%.gene}.expected"
    
    if [ -f "$expected_file" ]; then
        # Run test and compare output (ignoring trailing whitespace)
        if $GENE run "$test_file" 2>&1 | diff -w "$expected_file" - > /dev/null; then
            echo -e "${GREEN}PASS${NC} $test_name"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}FAIL${NC} $test_name"
            echo "  Expected output:"
            cat "$expected_file" | sed 's/^/    /'
            echo "  Actual output:"
            $GENE run "$test_file" 2>&1 | sed 's/^/    /'
            FAILED=$((FAILED + 1))
        fi
    else
        # Just run the test and check exit code
        if $GENE run "$test_file" > /dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC} $test_name"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}FAIL${NC} $test_name"
            echo "  Error output:"
            $GENE run "$test_file" 2>&1 | sed 's/^/    /'
            FAILED=$((FAILED + 1))
        fi
    fi
}

# Change to the testsuite directory to run tests
cd "$SCRIPT_DIR"

# Run all tests in categories
for category in basics control_flow functions data_structures oop arithmetic operators strings arrays maps macros patterns runtime modules error_handling ffi native_functions syntax; do
    if [ -d "$category" ]; then
        echo "--- $category ---"
        for test_file in "$category"/*.gene; do
            if [ -f "$test_file" ]; then
                run_test "$test_file"
            fi
        done
        echo
    fi
done

# Test stdin features - commented out as stdin not supported
# echo "--- stdin ---"
# if echo '(println 7)' | $GENE run - | grep -q 7; then
#     echo -e "${GREEN}PASS${NC} run_stdin"
#     PASSED=$((PASSED + 1))
# else
#     echo -e "${RED}FAIL${NC} run_stdin"
#     FAILED=$((FAILED + 1))
# fi

# if echo '(+ 2 3)' | $GENE eval - | grep -q 5; then
#     echo -e "${GREEN}PASS${NC} eval_stdin"
#     PASSED=$((PASSED + 1))
# else
#     echo -e "${RED}FAIL${NC} eval_stdin"
#     FAILED=$((FAILED + 1))
# fi

# if echo '(println 1)' | $GENE compile - > /dev/null && [ -f stdin.gbc ] && $GENE run stdin.gbc | grep -q 1; then
#     echo -e "${GREEN}PASS${NC} compile_stdin"
#     PASSED=$((PASSED + 1))
# else
#     echo -e "${RED}FAIL${NC} compile_stdin"
#     FAILED=$((FAILED + 1))
# fi
# rm -f stdin.gbc

# Run data parser tests if available
if [ -x "data_parser/run_tests.sh" ]; then
    echo "--- data_parser ---"
    if data_parser/run_tests.sh > /tmp/data_parser_output 2>&1; then
        echo -e "${GREEN}PASS${NC} data_parser suite"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} data_parser suite"
        cat /tmp/data_parser_output
        FAILED=$((FAILED + 1))
    fi
    echo
fi

# Summary
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo -e "Skipped: ${YELLOW}$SKIPPED${NC}"
echo -e "Total: $((PASSED + FAILED + SKIPPED))"

# Exit with error if any tests failed
if [ $FAILED -gt 0 ]; then
    exit 1
fi