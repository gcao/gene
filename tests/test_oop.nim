import unittest, tables

import gene/types

import ./helpers

# OOP tests for VM implementation
# Only including tests that work with current VM capabilities

# Basic class creation
test_vm "(class A)", proc(r: Value) =
  check r.ref.class.name == "A"

# Basic object creation
test_vm """
  (class A)
  (new A)
""", proc(r: Value) =
  check r.ref.instance_class.name == "A"

# Multiple classes
test_vm """
  (class A)
  (class B)
  B
""", proc(r: Value) =
  check r.ref.class.name == "B"

# The following tests require features not yet fully implemented in VM:

# Class inheritance
test_vm """
  (class A)
  (class B < A)
  B
""", proc(r: Value) =
  check r.ref.class.name == "B"
  check r.ref.class.parent.name == "A"

# Namespace class definition
# test_vm """
#   (ns n
#     (ns m)
#   )
#   (class n/m/A)
#   n/m/A/.name
# """, "A"

# Constructor - needs method compilation
# test_vm """
#   (class A
#     (.ctor _
#       (/p = 1)
#     )
#   )
#   (var a (new A))
#   a/p
# """, 1

# Namespaced class - needs complex symbol support
# test_vm """
#   (ns n)
#   (class n/A)
#   n/A
# """, proc(r: Value) =
#   check r.class.name == "A"

# Methods - needs method compilation and calling
test_vm """
  (class A
    (.fn test _
      1
    )
  )
  ((new A).test)
""", 1

# Instance variables - needs constructor support
# test_vm """
#   (class A
#     (.ctor _
#       (/a = 1)
#     )
#   )
#   ((new A)./a)
# """, 1

# Method with parameters
# test_vm """
#   (class A
#     (.fn test a
#       a
#     )
#   )
#   ((new A).test 1)
# """, 1

# Inheritance with method override
# test_vm """
#   (class A
#     (.fn test []
#       "A.test"
#     )
#   )
#   (class B < A
#   )
#   ((new B) .test)
# """, "A.test"

# Super calls
# test_vm """
#   (class A
#     (.fn test a
#       a
#     )
#   )
#   (class B < A
#     (.fn test a
#       (super a)
#     )
#   )
#   ((new B) .test 1)
# """, 1

# Inherited constructor
# test_vm """
#   (class A
#     (.ctor _
#       (/test = 1)
#     )
#   )
#   (class B < A)
#   ((new B)./test)
# """, 1

# Mixins
# test_vm """
#   (mixin M
#     (.fn test _
#       1
#     )
#   )
#   (class A
#     (include M)
#   )
#   ((new A) .test)
# """, 1

# Type checking
# test_vm """
#   ([] .is Array)
# """, true

# on_extended callback
# test_vm """
#   (class A
#     (var /children [])
#     (.on_extended
#       (fnx child
#         (/children .add child)
#       )
#     )
#   )
#   (class B < A)
#   A/children/.size
# """, 1

# Object syntax
# test_vm """
#   ($object a
#     (.fn test _
#       1
#     )
#   )
#   a/.test
# """, 1

# Macros in classes
# test_vm """
#   (class A
#     (.macro test a
#       a
#     )
#   )
#   (var b 1)
#   ((new A) .test b)
# """, new_gene_symbol("b")