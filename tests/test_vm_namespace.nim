import unittest, tables

import gene/types

import ./helpers

# Use symbol `a` to define static member.
# Use `%a` to define dynamic member. `a` must be defined already.
# Use a string in place of a symbol to bypass adding to namespace.
#   E.g. (class "C") will create a class named C but not add it to current namespace.

test_vm """
  (ns n)
""", proc(r: Value) =
  check r.ref.ns.name == "n"

test_vm """
  (ns n
    (ns m)
  )
""", proc(r: Value) =
  check r.ref.ns.name == "n"
  check r.ref.ns["m".to_key()].ref.ns.name == "m"

test_vm """
  (ns n
    (ns m)
  )
  n/m
""", proc(r: Value) =
  check r.ref.ns.name == "m"
