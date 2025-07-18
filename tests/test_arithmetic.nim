import gene/types

import ./helpers

# Tests for arithmetic operations
# Basic arithmetic operations are implemented in our VM

test_vm "(1 + 2)", 3
test_vm "(5 - 3)", 2
test_vm "(4 * 2)", 8
test_vm "(8 / 2)", 4.0
test_vm "(9 / 3)", 3.0

# Test precedence with parentheses
test_vm "((1 + 2) * 3)", 9
test_vm "(1 + (2 * 3))", 7
test_vm "((10 - 4) / 2)", 3.0

# More advanced arithmetic features not yet implemented in VM:
# Test with floats
# test_vm "(1.5 + 2.5)", 4.0
# test_vm "(5.0 - 2.5)", 2.5
# test_vm "(3.0 * 2.0)", 6.0
# test_vm "(10.0 / 2.0)", 5.0

# Test with negative numbers
# test_vm "(-1 + 2)", 1
# test_vm "(1 + -2)", -1
# test_vm "(-3 * 2)", -6
# test_vm "(6 / -2)", -3.0

# More complex arithmetic - not yet implemented in VM
# test_vm "(1 + 2 + 3)", 6
# test_vm "(2 * 3 + 4)", 10
# test_vm "(2 + 3 * 4)", 14