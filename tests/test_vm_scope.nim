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

# Handling of arguments, optional arguments:
# Compilation:
# Note: basic scope shadowing/if-block tests exist in tests/test_scope.nim; keep only FP-related scope here

# Execution:


# test_vm """
#   (var a 1)
#   # Should suppress the warning about shadowing
#   (var a ^!warn 2)
#   a
# """, 2




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
