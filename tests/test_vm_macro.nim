import unittest, tables

import gene/types

import ./helpers

test_vm """
  (macro m [])
""", proc(r: Value) =
  check r.ref.macro.name == "m"

test_vm true, """
  (macro m a
    a
  )
  (m b)
""", "b".to_symbol_value()

# test_vm """
#   (macro m [a b]
#     (a + b)
#   )
#   (m 1 2)
# """, 3
