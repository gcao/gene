import unittest, tables

import gene/types

import ./helpers

# Custom compiler

# When a custom compiler is called, code is first compiled then executed automatically
# Q: How are arguments processed?
# A:
# Q: Should compilation output be cached?
# A: Yes. Each compilation call should be executed once, then cached.
# Custom compiler vs function vs macro

# Custom instruction

# Has to be highly efficient
# Can only be implemented in Nim, e.g.
# define_instruction "DoX", proc(self: var Frame, inst: Instruction) =
#   ...

test_vm """
  (compile c a
    [
      ($vm/Push a)
      ($vm/Push 1)
      ($vm/Add)
    ]
  )
  (c 1)
""", 2

test_vm """
  (compile c a
    [
      ($vm/Push a)
      ($vm/Push 1)
      ($vm/Add)
    ]
  )
  (var b 1)
  (c b)
""", 2
