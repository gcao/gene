import unittest

import gene/types

import ./helpers

# Macro support
#
# * A macro will generate an AST tree and pass back to the VM to execute.
#

# Basic macro that returns its argument
test_vm """
  (macro m a
    a
  )
  (m :b)
""", "b".to_symbol_value()

# Test that macro arguments are not evaluated
test_vm """
  (macro m a
    :macro_result
  )
  (m (this_would_fail_if_evaluated))
""", "macro_result".to_symbol_value()

# Test that macro result is evaluated - simple case without interpolation
test_vm """
  (macro m [a b]
    :(1 + 2)
  )
  (m ignored ignored)
""", 3

# TODO: Convert to test_vm when macro support is complete
# test_interpreter """
#   (macro m [a b]
#     (a + b)
#   )
#   (m 1 2)
# """, 3

# TODO: Convert to test_vm when macro support is complete
# test_interpreter """
#   (macro m [a = 1]
#     (a + 2)
#   )
#   (m)
# """, 3

# TODO: Convert to test_vm when macro support is complete
# test_interpreter """
#   (macro m []
#     ($caller_eval :a)
#   )
#   (fn f _
#     (var a 1)
#     (m)
#   )
#   (f)
# """, 1

# TODO: Convert to test_vm when macro support is complete
# test_interpreter """
#   (var a 1)
#   (macro m b
#     ($caller_eval b)
#   )
#   (m a)
# """, 1

# test_core """
#   (macro m _
#     (class A
#       (.fn test _ "A.test")
#     )
#     ($caller_eval
#       (:$def_ns_member "B" A)
#     )
#   )
#   (m)
#   ((new B) .test)
# """, "A.test"

# test_core """
#   (macro m name
#     (class A
#       (.fn test _ "A.test")
#     )
#     ($caller_eval
#       (:$def_ns_member name A)
#     )
#   )
#   (m "B")
#   ((new B) .test)
# """, "A.test"

# # TODO: this should be possible with macro/caller_eval etc
# # TODO: Convert to test_vm when macro support is complete
# test_interpreter """
#   (macro with [name value body...]
#     (var expr
#       :(do
#         (var %name %value)
#         %body...
#         %name))
#     ($caller_eval expr)
#   )
#   (var b "b")
#   (with a "a"
#     (a = (a b))
#   )
# """, "ab"

# Placeholder to ensure the file compiles
discard