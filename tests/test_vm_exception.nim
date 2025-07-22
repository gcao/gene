import ./helpers

# Basic exception handling tests for the VM
# NOTE: This is a minimal implementation - full exception handling
# with try/catch/finally blocks is not yet complete

# Test basic throw
test_vm_error """
  (throw "test error")
"""

# Once try/catch is fully implemented, these tests should work:
# test_vm """
#   (try
#     (throw "error")
#     (catch e
#       "caught"))
# """, "caught"

# test_vm """
#   (try
#     "no error"
#     (catch e
#       "should not run"))
# """, "no error"