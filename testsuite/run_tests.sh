#!/bin/bash

# Gene Test Suite Runner
# Compares output against # Expected: comments when present
# Otherwise just verifies the test runs without error

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if gene executable exists
if [ ! -f "$SCRIPT_DIR/../bin/gene" ]; then
    echo -e "${RED}Error: gene executable not found at $SCRIPT_DIR/../bin/gene${NC}"
    echo "Please run 'nimble build' first."
    exit 1
fi

GENE="$SCRIPT_DIR/../bin/gene"
PASSED=0
FAILED=0
TOTAL=0

echo "================================"
echo "    Gene Test Suite Runner"
echo "================================"
echo

# Function to run a single test file
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .gene)
    
    TOTAL=$((TOTAL + 1))
    
    # Check if test has expected output
    if grep -q "^# Expected:" "$test_file"; then
        # Extract all expected output lines (skip empty Expected: lines)
        local expected_output=$(grep "^# Expected:" "$test_file" | sed 's/^# Expected: //' | grep -v '^$' || true)
        
        if [ -z "$expected_output" ]; then
            # Empty expected output - just check if it runs
            if $GENE run "$test_file" > /dev/null 2>&1; then
                printf "  %-40s ${GREEN}✓ PASS${NC}\n" "$test_name"
                PASSED=$((PASSED + 1))
            else
                printf "  %-40s ${RED}✗ FAIL${NC}\n" "$test_name"
                FAILED=$((FAILED + 1))
            fi
        else
            # Run test and capture output
            if actual_output=$($GENE run "$test_file" 2>&1); then
                # Filter out empty lines from actual output for comparison
                actual_output=$(echo "$actual_output" | grep -v '^$' || true)
                
                # Normalize outputs (remove trailing spaces)
                echo "$expected_output" | sed 's/[[:space:]]*$//' > /tmp/expected_$$.txt
                echo "$actual_output" | sed 's/[[:space:]]*$//' > /tmp/actual_$$.txt
                
                # Compare outputs
                if diff -B -w /tmp/expected_$$.txt /tmp/actual_$$.txt > /dev/null 2>&1; then
                    printf "  %-40s ${GREEN}✓ PASS${NC}\n" "$test_name"
                    PASSED=$((PASSED + 1))
                else
                    printf "  %-40s ${RED}✗ FAIL${NC}\n" "$test_name"
                    echo "    Expected:"
                    echo "$expected_output" | sed 's/^/      /'
                    echo "    Actual:"
                    echo "$actual_output" | sed 's/^/      /'
                    FAILED=$((FAILED + 1))
                fi
                
                # Clean up temp files
                rm -f /tmp/expected_$$.txt /tmp/actual_$$.txt
            else
                printf "  %-40s ${RED}✗ ERROR${NC}\n" "$test_name"
                echo "    Error output:"
                echo "$actual_output" | head -5 | sed 's/^/      /'
                FAILED=$((FAILED + 1))
            fi
        fi
    else
        # No expected output - just check if it runs without error
        if $GENE run "$test_file" > /dev/null 2>&1; then
            printf "  %-40s ${GREEN}✓ PASS${NC}\n" "$test_name"
            PASSED=$((PASSED + 1))
        else
            printf "  %-40s ${RED}✗ FAIL${NC}\n" "$test_name"
            error_output=$($GENE run "$test_file" 2>&1 || true)
            echo "    Error output:"
            echo "$error_output" | head -5 | sed 's/^/      /'
            FAILED=$((FAILED + 1))
        fi
    fi
}

# Function to run tests in a directory
run_category() {
    local category=$1
    local dir=$2
    
    if [ -d "$dir" ]; then
        echo -e "${BLUE}Testing $category:${NC}"
        
        # Run numbered tests in order
        for i in 1 2 3 4 5 6 7 8 9; do
            for test_file in "$dir"/${i}_*.gene; do
                if [ -f "$test_file" ]; then
                    run_test "$test_file"
                fi
            done
        done
        
        echo
    fi
}

# Change to testsuite directory
cd "$SCRIPT_DIR"

# Run tests in specific order
run_category "Basic Literals & Variables" "basics"
run_category "Control Flow" "control_flow"
run_category "Operators" "operators"
run_category "Arrays" "arrays"
run_category "Maps" "maps"
run_category "Strings" "strings"
run_category "Functions" "functions"
run_category "Scopes" "scopes"

# Summary
echo "================================"
echo "        Test Summary"
echo "================================"
echo
printf "  Total Tests:  %3d\n" "$TOTAL"
printf "  ${GREEN}Passed:       %3d${NC}\n" "$PASSED"
printf "  ${RED}Failed:       %3d${NC}\n" "$FAILED"

if [ $FAILED -eq 0 ]; then
    echo
    echo -e "${GREEN}✓ All tests passed successfully!${NC}"
    exit 0
else
    PASS_RATE=$((PASSED * 100 / TOTAL))
    echo
    echo -e "${YELLOW}⚠ Pass rate: ${PASS_RATE}%${NC}"
    exit 1
fi