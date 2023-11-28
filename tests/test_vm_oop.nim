import unittest, tables

import gene/types

import ./helpers

test_vm """
  (class A)
""", proc(r: Value) =
  check r.to_ref().class.name == "A"

test_vm """
  (class A)
  (class B < A)
""", proc(r: Value) =
  check r.to_ref().class.name == "B"
  check r.to_ref().class.parent.name == "A"

test_vm """
  (class A
    (class B)
  )
  A/B
""", proc(r: Value) =
  check r.to_ref().class.name == "B"

test_vm true, """
  (class A)
  (new A)
""", proc(r: Value) =
  check r.to_ref().instance_class.name == "A"

# test_vm """
#   (class A
#     (.fn test _
#       1
#     )
#   )
#   ((new A).test)
# """, 1

# test_vm """
#   (class A
#     (.fn set_x a
#       (/x = a)
#     )
#     (.fn test _
#       /x
#     )
#   )
#   (var a (new A))
#   (a .set_x 1)
#   (a .test)
# """, 1

# test_vm """
#   (class A
#     (.fn test _
#       1
#     )
#   )
#   (var a (new A))
#   a/.test
# """, 1

# test_vm """
#   (class A
#     (.ctor _
#       (/test = 1)
#     )
#   )
#   (var a (new A))
#   a/test
# """, 1

# # test_vm """
# #   (class A
# #     (.ctor /test)
# #   )
# #   (var a (new A 1))
# #   a/test
# # """, 1
