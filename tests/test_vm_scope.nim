import unittest

import gene/types

import ./helpers

test_vm """
  (var a 1)
  (if true
    (var a 2)
  )
  a
""", 1
