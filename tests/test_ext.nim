import unittest

import gene/types
import gene/vm

import ./helpers

suite "Extension":
  # Skip for now - extension system needs symbol table sharing
  skip()
  
  # init_all()
  # discard VM.exec("""
  #   (import test new_extension get_i from "./extension" ^^native)
  #   (import new_extension2 extension2_name from "./extension2" ^^native)
  # """, "test_setup")

  # test_vm """
  #   (test 1)
  # """, 1