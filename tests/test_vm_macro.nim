import unittest

import gene/types

import ./helpers

test_vm """
  (macro m [])
""", proc(r: Value) =
  check r.ref.macro.name == "m"

test_vm """
  (macro m a
    a
  )
  (m b)
""", "b".to_symbol_value()

test_vm """
  (macro m [a b]
    (a + b)
  )
  (m 1 2)
""", 3

# test_vm true, """
#   (macro m a
#     ($caller_eval a)
#   )
#   (var b 1)
#   (m b)
# """, 1
