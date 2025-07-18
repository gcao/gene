import gene/types

import ./helpers

# Tests for repeat loop construct
# Most repeat functionality is not yet implemented in our VM
# These tests are commented out until those features are available:

# test_vm """
#   (var sum 0)
#   (repeat 3
#     (sum = (sum + 1))
#   )
#   sum
# """, 3

# test_vm """
#   (var i 0)
#   (repeat 3
#     (var i 1)
#   )
#   i
# """, 0

# test_vm """
#   (var sum 0)
#   (repeat 4 ^index i
#     (sum += i)
#   )
#   sum
# """, 6 # 0, 1, 2, 3

# test_vm """
#   (var sum 0)
#   (repeat 3 ^total total
#     (sum += total)
#   )
#   sum
# """, 9

# test_vm """
#   (var sum 0)
#   (repeat 3
#     # "$once" make sure the statement is executed at most once in a loop.
#     ($once (sum += 1))
#   )
#   sum
# """, 1

# Placeholder test for now
test_vm "1", 1