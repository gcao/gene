import unittest

import gene/types
import gene/vm

import ./helpers

# Module system tests for VM
# The module system allows importing code from other files/modules

# TODO: Implement import functionality
# test_vm """
#   (import "math" [pi e])
#   pi
# """, 3.14159

# For now, let's test what we can with the current namespace system
test_vm """
  (ns math
    (var pi 3.14159)
    (var e 2.71828)
  )
  math/pi
""", 3.14159

test_vm """
  (ns math
    (var pi 3.14159)
    (fn circle_area r
      (* pi r r)
    )
  )
  (math/circle_area 2)
""", proc(r: Value) =
  check r.kind == VkFloat
  check abs(r.float - 12.56636) < 0.00001

test_vm """
  (ns outer
    (var x 1)
    (ns inner
      (var y 2)
    )
  )
  outer/inner/y
""", 2

test_vm """
  (ns test
    (fn get_x _ x)
  )
  (var x 42)
  (test/get_x)
""", 42