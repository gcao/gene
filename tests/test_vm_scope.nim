import gene/types

import ./helpers

# Scope logic during compilation:
#   Scope tracker is used in place of scope
#   Scope tracker stack is used to keep track of all scope trackers, with the
#     top of the stack being the current scope tracker
#   New scope tracker is created when entering a block
#   Scope tracker is destroyed when leaving a block
#   Scope tracker's parent is the last scope tracker that has variables declared already
#   The immediate preceding scope tracker may not be the parent of the current scope tracker
#   ScopeStart and ScopeEnd should always come in pairs
#   ScopeStart are generated when the first variable is declared in a block

# Scope logic during execution:
#   Scope contains a reference to the parent scope, which could be null.
#   Scope contains a reference to the scope tracker in order to support
#     compiation during execution.
#   Scopes are created implicitly (e.g. for functions with arguments) or by ScopeStart instruction
#   Scopes are destroyed at the end of the block before jumping, or by ScopeEnd instruction
#   When a scope is destroyed, the current scope is set to its parent scope
#   The current scope can be null if the block doesn't declare any variables
#   The compilation or execution should throw error when trying to access a variable
#     that doesn't exist.

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

test_vm true, """
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

test_vm true, """
  (var a 1)
  (if false
    (var a 2)
  else
    a
  )
""", 1
