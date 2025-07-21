import gene/types

import ./helpers

# (defined? a)
# (defined_in_scope? a)
# (scope)
# (scope ^!inherit)

# Basic variable scoping tests that work with our VM
test_vm """
  (var a 1)
  # Should produce a warning about shadowing
  (var a 2)
  a
""", 2

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

# Function parameter scoping tests
test_vm """
  (fn f [a]
    (a + 2)
  )
  (f 1)
""", 3

test_vm """
  (var a 1)
  (fn f [a]
    (a + 10)
  )
  (f 2)
""", 12

test_vm """
  (var a 1)
  (fn f [a = 2]
    (a + 10)
  )
  (f)
""", 12

# Function closure test
test_vm("""
  (var i 0)
  (fn f _
    i
  )
  (var i 1)
  (f)
""", 0)