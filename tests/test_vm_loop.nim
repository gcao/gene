import gene/types

import ./helpers

# Use xloop and xbreak to implement loop with effects

# Loop implemented with effects

#     AddHandlers {range: [labelS, labelE], handlers: {break: labelB, next: labelN}
# labelS:
#     ...
#     Jump labelS
# labelB: # labelB is not required, break can point to labelE directly. We use labelB for clarity purpose here.
#     Jump labelE
# labelN: # labelN is not required, next can point to labelS directly. We use labelN for clarity purpose here.
#     Jump labelS
# labelE:
#     ...

# When execution moves out of the range, the handlers will be removed automatically.

test_vm """
  (loop
    (break)
  )
  1
""", 1

test_vm """
  (loop
    (break 1)
  )
""", 1

test_vm """
  (xloop
    (xbreak)
  )
  1
""", 1

test_vm """
  (var a 3)
  (xloop
    (if (a == 0)
      (xbreak)
    )
    (a = (a - 1))
  )
  a
""", 0

# test_vm """
#   (var a 0)
#   (loop
#     (a = 1)
#     (break)
#     (a = 2)
#   )
#   a
# """, 1

# test_vm """
#   (loop
#     (break 1)
#   )
# """, 1

# test_vm true, """
#   (var a 5)
#   (while (a > 0)
#     (a = (a - 1))
#   )
#   a
# """, 0

# test_vm true, """
#   (var a 5)
#   # Implement while using loop
#   (loop
#     (if_not (a > 0)
#       (break)
#     )
#     (a = (a - 1))
#   )
#   a
# """, 0
