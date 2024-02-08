import unittest, tables

import gene/types

import ./helpers

test_vm """
  (a -> (a + 1))
""", proc(r: Value) =
  check r.kind == VkBlock

test_vm """
  (fn f _
    (g
      (a -> (a + 1))
    )
  )
  (fn g b
    (b 1)
  )
  (f)
""", 2
