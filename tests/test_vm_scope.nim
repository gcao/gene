import unittest

import gene/types

import ./helpers

test_vm """
  (var a 1)
  # Should produce a warning about shadowing
  (var a 2)
  a
""", 2

# test_vm """
#   (var a 1)
#   # Should suppress the warning about shadowing
#   (var a ^!warn 2)
#   a
# """, 2

test_vm """
  (var a 1)
  (if true
    (var a 2)
  )
  a
""", 1

test_vm """
  (var a 1)
  (if true
    (var a 2)
    a
  )
""", 2

test_vm """
  (var a 1)
  (if false
    (var a 2)
  else
    a
  )
""", 1
