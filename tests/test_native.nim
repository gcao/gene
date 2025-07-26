import gene/types

import ./helpers

# Native functions / methods

test_vm """
  (gene/test1)
""", 1

test_vm """
  (gene/test2 10 20)
""", 30