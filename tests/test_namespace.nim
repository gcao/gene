import unittest

import gene/types

import ./helpers

# Namespace related metaprogramming:
#
# * Namespace.member_defined (called when a member is defined or re-defined)
# * Namespace.member_removed
# * Namespace.on_member_missing (invoked only if <some_ns>/something is invoked and something is not defined)
# * Namespace.has_member - it should be consistent with member_missing

test_interpreter "(ns test)", proc(r: Value) =
  check r.ns.name == "test"

test_interpreter """
  (ns n
    (class A)
  )
  n/A
""", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (ns n
    (var /a 1)
  )
  n/a
""", 1

test_interpreter """
  (ns n)
  (class n/A)
  n/A
""", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (ns n)
  (var n/test 1)
  n/test
""", 1

test_interpreter """
  (ns n)
  (ns n/m)
  n/m
""", proc(r: Value) =
  check r.ns.name == "m"

test_interpreter """
  (ns n)
  (ns n/m
    (class A)
  )
  n/m/A
""", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (ns n)
  n
""", proc(r: Value) =
  check r.ns.name == "n"

test_interpreter """
  global
""", proc(r: Value) =
  check r.ns.name == "global"

test_interpreter """
  (class global/A)
  global/A
""", proc(r: Value) =
  check r.class.name == "A"

test_interpreter """
  (var global/a 1)
  a
""", 1

test_interpreter """
  (class A
    (fn f a a)
  )
  (A/f 1)
""", 1

test_interpreter """
  (ns n
    (class A)
    (ns m
      (class B < A)
    )
  )
  n/m/B
""", proc(r: Value) =
  check r.class.name == "B"

test_interpreter """
  (ns n
    (.on_member_missing
      (fnx name
        (if (name == "test")
          1
        else
          # What should we do here, in order to pass to the next namespace to search for the name?
          # Option 1: ($get_member /.parent name)
          # Option 2: ($not_found name)
          # Option 3: (throw (new MemberNotFound name))
        )
      )
    )
  )
  n/test
""", 1

test_interpreter """
  (ns n
    (.on_member_missing
      (fnx name
        ("" /.name "/" name)
      )
    )
  )
  n/test
""", "n/test"

test_interpreter """
  (class C
    (.on_member_missing
      (fnx name
        ("" /.name "/" name)
      )
    )
  )
  C/test
""", "C/test"

test_interpreter """
  (ns n
    (.on_member_missing
      (fnx name
        (if (name == "a")
          1
        )
      )
    )
    (.on_member_missing
      (fnx name
        (if (name == "b")
          2
        )
      )
    )
  )
  (n/a + n/b)
""", 3

test_interpreter """
  ($ns/a = 1)
  (a = 2)
  $ns/a
""", 2

test_interpreter """
  (var a 1)
  ($ns/a = 1)
  (a = 2)
  $ns/a
""", 1

test_interpreter """
  (ns n)
  (ns m
    (var /a 1)
  )
  (n .proxy :a m)
  n/a
""", 1
